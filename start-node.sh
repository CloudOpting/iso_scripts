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
#	server_ip=$(cat /var/lib/NetworkManager/*.lease | grep dhcp-server-identifier | tail -1| awk '{print $NF}' | tr '\;' ' ')
#	server_ip2=${server_ip:0:${#server_ip}-1}
#	log "Cloudstsack virtual router" $server_ip2
	userdata=$(curl http://$server_ip2/latest/user-data)
#	log "userdata:" $userdata

	#transform userdata in env vars
#	eval $userdata
	
	# CHECK ENV VARS
	# could be from Cloudstack or have to have a default value
	if [[ -z "$timezone" ]]; then timezone='Rome'; fi
#	if [[ -z "$environment" ]]; then environment='production'; fi
	
	# ACPID
	systemctl start acpid
	systemctl enable acpid

	
	#install ntp  
	ensure_package_installed "ntp"
	rm -f /etc/localtime
	ln -s /usr/share/zoneinfo/Europe/$timezone /etc/localtime
	ntpdate 1.centos.pool.ntp.org
	systemctl start ntpd
	systemctl enable ntpd
	log "started ntp" $(service ntpd status)

	#install bind since it is needed by some puppet/facter plugin and cannot be installed by puppet itself
	ensure_package_installed "bind-utils"
	
	# Fail2ban for security
	ensure_package_installed fail2ban
	systemctl start fail2ban
	systemctl enable fail2ban

	# Configuration tool Augeas and facter
	ensure_package_installed "augeas"
	ensure_package_installed "facter"
	# Editor nano
	ensure_package_installed "nano"

	#configuring the resolv.conf
	myDomain=$(echo $(dig -x $(echo $(facter ipaddress) |sed 's/\(.*\)\.\(.*\)\.\(.*\)\.\(.*\)/\1.\2.\3.1/') +short) |awk -F. '{$1="";OFS="." ; print $0}' | sed 's/^.//'| sed s'/.$//')
	augtool set /files/etc/resolv.conf/search/domain ${myDomain,,} -s

	
	# -------------------- PUPPET STUFF
	# Puppet Master
	ensure_package_installed "puppet"
	
	#Puppet, PuppetDb, Dashboard and MCollective settings
	myHostname=$(if [[ -z "$(facter fqdn)" ]]; then echo "localhost"; else echo $(facter fqdn);fi)
	puppet_master=$(if [[ -z "$puppet_master" ]]; then echo "puppet."$(facter domain); else echo $puppet_master;fi)
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
#log "dash_db_pwd" $dash_db_pwd
	
	
	# Configuration of puppet.conf
	augtool defnode server /files/etc/puppet/puppet.conf/main/server $puppet_master -s
	augtool defnode certname /files/etc/puppet/puppet.conf/main/certname ${myHostname,,} -s
	augtool defnode pluginsync /files/etc/puppet/puppet.conf/main/pluginsync true -s
	augtool defnode report /files/etc/puppet/puppet.conf/agent/report true -s

	# Prepare for docker
	ensure_package_installed "wget"
	ensure_package_installed "docker"
	systemctl disable NetworkManager
	systemctl stop NetworkManager
	systemctl stop docker
	wget https://get.docker.com/builds/Linux/x86_64/docker-latest -O /usr/bin/docker && chmod +x /usr/bin/docker
	firewall-cmd --permanent --zone=trusted --add-interface=docker0
	systemctl start docker
	systemctl enable docker

	puppet agent  --environment=production
}

#execute the tasks
start-opendai | tee /root/all.log
