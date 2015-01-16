function package_installed (){
    name=$1
    if `rpm -q $name 1>/dev/null`; then
	return 0
    else
	return 1
    fi
}

function install_package (){
    `yum install --quiet -y $1 1>/dev/null`
    RET=$?
    if [ $RET == 0 ]; then
	return 0
    else
	echo "ERROR: Could not install package $1"
	log "ERROR: Could not install package $1"
	exit 1
    fi
}

function ensure_package_installed (){
    if ! package_installed $1 ; then
	echo "Installing ${1}"
	log "Installing ${1}"
	install_package $1
    fi
}


function start-opendai {
	log "start-opendai"
	
	log "fixing Vagrant keys"
	chmod 600 /home/vagrant/.ssh/authorized_keys
	chown -R vagrant:vagrant /home/vagrant/.ssh

	# Installing repositories
	log "adding repos"
	#add puppet repository
		rpm -ivh https://yum.puppetlabs.com/puppetlabs-release-el-7.noarch.rpm
	#add RPMFORGE repository
	rpm -ivh http://pkgs.repoforge.org/rpmforge-release/rpmforge-release-0.5.3-1.el7.rf.x86_64.rpm
	#add EPEL repository
	ensure_package_installed "epel-release"
	#zabbix repos
	rpm -ivh http://repo.zabbix.com/zabbix/2.4/rhel/7/x86_64/zabbix-release-2.4-1.el7.noarch.rpm
	log $(yum check-update)
	
	log "Cloudstack stuff"
	#First cloudstack recover virtual router IP
	server_ip=$(cat /var/lib/NetworkManager/*.lease | grep dhcp-server-identifier | tail -1| awk '{print $NF}' | tr '\;' ' ')
	server_ip2=${server_ip:0:${#server_ip}-1}
	log "Cloudstsack virtual router" $server_ip2
	userdata=$(curl http://$server_ip2/latest/user-data)
	log "userdata:" $userdata

	#transform userdata in env vars
	eval $userdata
	
	# CHECK ENV VARS
	# could be from Cloudstack or have to have a default value
	if [[ -z "$timezone" ]]; then timezone='Rome'; fi
#	if [[ -z "$environment" ]]; then environment='production'; fi
	
	# ACPID
	service acpid start
	chkconfig --levels 235 acpid on
	
	#install ntp  
	ensure_package_installed "ntp"
	rm -f /etc/localtime
	ln -s /usr/share/zoneinfo/Europe/$timezone /etc/localtime
	ntpdate 1.centos.pool.ntp.org
	service ntpd start
	chkconfig --levels 235 ntpd on
	log "started ntp" $(service ntpd status)

	#install bind since it is needed by some puppet/facter plugin and cannot be installed by puppet itself
	ensure_package_installed "bind-utils"
	
	# Fail2ban for security
	ensure_package_installed fail2ban
	service fail2ban start
	chkconfig fail2ban on

	# Configuration tool Augeas
	ensure_package_installed "augeas"
	# Editor nano
	ensure_package_installed "nano"

	# Apache
	ensure_package_installed "httpd"
	chkconfig --levels 235 httpd on
	service httpd start
	log "started httpd" $(service httpd status)
	
	# Postgresql
	log "Install Postgresql"
	ensure_package_installed "postgresql-server"
	service postgresql initdb
	service postgresql start
	chkconfig --levels 235 postgresql on
	log "setting the access to postgres with md5"
	postgres_pwd=pgopendai
	sudo -u postgres psql -c "ALTER USER Postgres WITH PASSWORD '$postgres_pwd';"
	log "ALTER USER Postgres WITH PASSWORD '$postgres_pwd';"
	augtool set /files/var/lib/pgsql/data/pg_hba.conf/1/method md5 -s
	augtool set /files/var/lib/pgsql/data/pg_hba.conf/2/method md5 -s
	augtool set /files/var/lib/pgsql/data/pg_hba.conf/3/method md5 -s
	service postgresql restart
	
	# PHP
	ensure_package_installed "php"
	augtool set /files/etc/php.ini/PHP/max_execution_time 600 -s
	augtool set /files/etc/php.ini/PHP/memory_limit 256M -s
	augtool set /files/etc/php.ini/PHP/post_max_size 32M -s
	augtool set /files/etc/php.ini/PHP/upload_max_filesize 16M -s
	augtool set /files/etc/php.ini/PHP/max_input_time 600 -s
	augtool set /files/etc/php.ini/PHP/expose_php off -s
	augtool defnode date.timezone /files/etc/php.ini/Date/date.timezone "Europe/$timezone" -s
	service httpd restart

	# -------------------- PUPPET STUFF
	# Puppet Master
	ensure_package_installed "puppet-server"
	
	#Puppet, PuppetDb, Dashboard and MCollective settings
	myHostname=$(if [[ -z "$(facter fqdn)" ]]; then echo "localhost"; else echo $(facter fqdn);fi)
	myIP=$(facter ipaddress)
	myDomain=$(facter domain)
	puppetDB=mgmtdb.$myDomain
	mc_pwd=mcopwd
	mc_stomp_pwd=mcopwd
	dash_db_pwd=dashboard
	log "hostname" $myHostname
	log "IP" $myIP
	log "domain" $myDomain
	log "mc_pwd" $mc_pwd
	log "mc_stomp_pwd" $mc_stomp_pwd
	log "dash_db_pwd" $dash_db_pwd
	
	# Configuration of puppet.conf
	augtool ins confdir before /files/etc/puppet/puppet.conf/main/logdir -s
	augtool set /files/etc/puppet/puppet.conf/main/confdir /etc/puppet -s
	augtool ins vardir before /files/etc/puppet/puppet.conf/main/logdir -s
	augtool set /files/etc/puppet/puppet.conf/main/vardir /var/lib/puppet -s
	augtool defnode hiera_config /files/etc/puppet/puppet.conf/main/hiera_config \$confdir/hiera/production/hiera.yaml -s
	res=$(augtool defnode certname /files/etc/puppet/puppet.conf/main/certname $myHostname -s)
	log $res
	augtool defnode storeconfigs /files/etc/puppet/puppet.conf/master/storeconfigs true -s
	augtool defnode storeconfigs_backend /files/etc/puppet/puppet.conf/master/storeconfigs_backend puppetdb -s
	augtool defnode reports /files/etc/puppet/puppet.conf/master/reports "store,puppetdb" -s
	augtool defnode environmentpath /files/etc/puppet/puppet.conf/master/environmentpath \$confdir/environments -s

	mkdir /etc/puppet/environments
	mkdir /etc/puppet/environments/production

	#create autosign.conf in /etc/puppet/
	echo -e "*.$(if [[ -z "$(facter domain)" ]]; then echo "*"; else echo $(facter domain);fi)" > /etc/puppet/autosign.conf
	log "edited autosign.conf"

	# append in file /etc/puppet/auth.conf
	############## GOES BEFORE last 2 rows
	echo -e "path /facts\nauth any\nmethod find, search\nallow *" >> /etc/puppet/auth.conf
	log "appended stuff in puppet/auth.conf"

	#### START PUPPET MASTER NOW
#	service puppetmaster start
	puppet master --verbose --debug
	chkconfig puppetmaster on
	
	# Install PUPPETDB
	log "puppetDB"
	puppet resource package puppetdb ensure=latest
	puppet resource service puppetdb ensure=running enable=true
	puppet resource package puppetdb-terminus ensure=latest
	chkconfig puppetdb on
		
	# set puppetdb.conf
	echo -e "[main]\nserver = $myHostname\nport = 8081" > /etc/puppet/puppetdb.conf 
	# set Routes.yaml
	echo -e "master:\n  facts:\n    terminus: puppetdb\n    cache: yaml" > /etc/puppet/routes.yaml

	#Will have to restart puppet master
	service puppetmaster restart
	
	#Setting the environments
	log "setting puppet's environments"
	#recovering the r10k file
	curl -L https://raw.githubusercontent.com/open-dai/platform/master/scripts/r10k_install.pp  >> /var/tmp/r10k_installation.pp
	#installing git
	ensure_package_installed "git"
	puppet module install zack/r10k
	puppet apply /var/tmp/r10k_installation.pp
	gem install r10k
	r10k deploy environment -pv
	
	
	#INSTALL Mcollective client
	log "Installing MCollective"
	ensure_package_installed "mcollective-client"
	ensure_package_installed "activemq"
	augtool set  /files/etc/mcollective/client.cfg/plugin.psk $mc_pwd -s
	augtool set  /files/etc/mcollective/client.cfg/plugin.activemq.pool.1.host $myHostname -s
	augtool set  /files/etc/mcollective/client.cfg/plugin.activemq.pool.1.password $mc_pwd -s
	augtool set  /files/etc/mcollective/client.cfg/plugin.activemq.pool.1.port 61613 -s
	augtool defnode plugin.activemq.base64 /files/etc/mcollective/client.cfg/plugin.activemq.base64 "yes" -s

	#Modify /etc/activemq/activemq.xml
	echo -e "set /augeas/load/activemq/lens Xml.lns\nset /augeas/load/activemq/incl /etc/activemq/activemq.xml\nload\nset /files/etc/activemq/activemq.xml/beans/broker/plugins/simpleAuthenticationPlugin/users/authenticationUser[2]/#attribute/password $mc_pwd"|augtool -s
	echo -e "set /augeas/load/activemq/lens Xml.lns\nset /augeas/load/activemq/incl /etc/activemq/activemq.xml\nload\nset /files/etc/activemq/activemq.xml/beans/broker/#attribute/brokerName $myHostname"|augtool -s

	service activemq start
	chkconfig activemq on
	
	### Mcollective plugins
	# packages
	ensure_package_installed "mcollective-service-client"
	ensure_package_installed "mcollective-puppet-client"
	# custom
	curl -L https://raw.githubusercontent.com/gioppoluca/mcollective-jboss/master/agent/jboss.ddl  >> /usr/libexec/mcollective/mcollective/agent/jboss.ddl
	
	#INSTALL Zabbix
	log "Installing Zabbix server"
	ensure_package_installed "zabbix-server-pgsql"
	ensure_package_installed "zabbix-web-pgsql"
	zabbixDBuser=zabbix
	zabbixBDpwd=zabbix
	
	sudo -u postgres PGPASSWORD=$postgres_pwd psql -c "CREATE USER $zabbixDBuser WITH PASSWORD '$zabbixBDpwd';"
	sudo -u postgres PGPASSWORD=$postgres_pwd psql -c "CREATE DATABASE zabbix OWNER $zabbixDBuser;"
	cat /usr/share/doc/$(rpm -qa --qf "%{NAME}-%{VERSION}" zabbix-server-pgsql)/create/schema.sql | sudo -u postgres PGPASSWORD=$zabbixBDpwd psql -U zabbix zabbix
	cat /usr/share/doc/$(rpm -qa --qf "%{NAME}-%{VERSION}" zabbix-server-pgsql)/create/images.sql | sudo -u postgres PGPASSWORD=$zabbixBDpwd psql -U zabbix zabbix
	cat /usr/share/doc/$(rpm -qa --qf "%{NAME}-%{VERSION}" zabbix-server-pgsql)/create/data.sql | sudo -u postgres PGPASSWORD=$zabbixBDpwd psql -U zabbix zabbix
	
	augtool defnode DBHost /files/etc/zabbix/zabbix_server.conf/DBHost '' -s
	augtool set /files/etc/zabbix/zabbix_server.conf/DBName zabbix -s
	augtool set /files/etc/zabbix/zabbix_server.conf/DBUser $zabbixDBuser -s
	augtool defnode DBPassword /files/etc/zabbix/zabbix_server.conf/DBPassword $zabbixBDpwd -s

	#Setting the Zabbix Web config file
	log "Zabbix web config file"
(
cat << EOF
<?php
// Zabbix GUI configuration file
global \$DB;

\$DB['TYPE']     = 'POSTGRESQL';
\$DB['SERVER']   = 'localhost';
\$DB['PORT']     = '0';
\$DB['DATABASE'] = 'zabbix';
\$DB['USER']     = '$zabbixDBuser';
\$DB['PASSWORD'] = '$zabbixBDpwd';

// SCHEMA is relevant only for IBM_DB2 database
\$DB['SCHEMA'] = '';

\$ZBX_SERVER      = 'localhost';
\$ZBX_SERVER_PORT = '10051';
\$ZBX_SERVER_NAME = '';

\$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;
?>
EOF
) > /etc/zabbix/web/zabbix.conf.php
	
	service httpd restart
	service zabbix-server start
	chkconfig zabbix-server on
	
	#set the encrypted hiera tool
	gem install hiera-eyaml
	mkdir /etc/puppet/secure
	cd /etc/puppet/secure
	eyaml createkeys
	chown -R puppet:puppet /etc/puppet/secure/keys
	chmod -R 0500 /etc/puppet/secure/keys
	chmod 0400 /etc/puppet/secure/keys/*.pem
	
	log "copy the config script"
	curl -L https://github.com/open-dai/platform/raw/master/scripts/config-master.sh >> /root/config-master.sh
	chmod +x /root/config-master.sh
	
	# MCOLLECTIVE stuff
#	wget http://www.kermit.fr/stuff/yum.repos.d/kermit.repo -O /etc/yum.repos.d/kermit.repo
#	rpm --import http://www.kermit.fr/stuff/gpg/RPM-GPG-KEY-lcoilliot
#	rpm -ivh http://www.kermit.fr/stuff/gpg/kermit-gpg_key_whs-1.0-1.noarch.rpm
#	rpm --import /etc/pki/rpm-gpg-kermit/RPM-GPG-KEY-*
#	ensure_package_installed "kermit-restmco" 
	chmod 644 /etc/mcollective/client.cfg
#	service kermit-restmco start
#	chkconfig kermit-restmco on
	
	# Installing the Joomla! web management
	joomlaDBuser=joomla
	joomlaDBpwd=joomla
	git clone https://github.com/open-dai/web-management.git /var/www/html
	chown apache:apache -R /var/www/html/
	sudo -u postgres PGPASSWORD=$postgres_pwd psql -c "CREATE USER $joomlaDBuser WITH PASSWORD '$joomlaDBpwd';"
	sudo -u postgres PGPASSWORD=$postgres_pwd psql -c "CREATE DATABASE joomla OWNER $joomlaDBuser;"
	# any change of data in the web site has to be done before loading the dump in the DB
	cat /var/www/html/odaimanagement.sql | sudo -u postgres PGPASSWORD=$joomlaDBpwd psql -U $joomlaDBuser joomla
	
	# could be needed to be done a second time for #2 bug
	r10k deploy environment -pv
	
	# setup fog
	ensure_package_installed "ruby-devel"
	ensure_package_installed "ruby-rgen" 
	ensure_package_installed "gcc" 
	ensure_package_installed "patch" 
	ensure_package_installed "libxslt-devel" 
	ensure_package_installed "libxml2-devel" 
	gem install fog
}

#execute the tasks
start-opendai | tee /root/all.log
