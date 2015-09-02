# Puppet stuff
rpm -ivh https://yum.puppetlabs.com/puppetlabs-release-el-7.noarch.rpm
yum install -y puppet
gem install r10k

# CloudOptingData
mkdir /cloudOptingData
chown gioppo:gioppo /cloudOptingData/

# JAVA
yum remove -y java-1.7.0-openjdk

yum install -y java-1.8.0-openjdk java-1.8.0-openjdk-devel
yum install libreoffice

curl http://downloads.bouncycastle.org/java/bcprov-jdk15on-152.jar > /root/bcprov-jdk15on-152.jar
curl http://downloads.bouncycastle.org/java/bcprov-ext-jdk15on-152.jar > /root/bcprov-ext-jdk15on-152.jar
cp bcprov-jdk15on-152.jar /etc/alternatives/java_sdk/jre/lib/ext/bcprov-jdk15on-152.jar
cp bcprov-ext-jdk15on-152.jar /etc/alternatives/java_sdk/jre/lib/ext/bcprov-ext-jdk15on-152.jar

# Docker
curl -sSL https://get.docker.com/ | sh
usermod -aG docker gioppo
curl -L https://github.com/docker/compose/releases/download/1.4.0/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# STS
mkdir /home/gioppo/Development
curl http://dist.springsource.com/release/STS/3.7.0.RELEASE/dist/e4.5/spring-tool-suite-3.7.0.RELEASE-e4.5-linux-gtk-x86_64.tar.gz > /root/spring-tool-suite-3.7.0.RELEASE-e4.5-linux-gtk-x86_64.tar.gz

tar -zxvf spring-tool-suite-3.7.0.RELEASE-e4.5-linux-gtk-x86_64.tar.gz /home/gioppo/Development

cd /home/gioppo/Development/sts-bundle/sts-*

./STS -noSplash -application org.eclipse.equinox.p2.director  -u org.activiti.designer.feature.feature.group, com.objectaid.uml.cls.feature.group -r http://activiti.org/designer/update/, http://www.objectaid.net/update/site.xml

chown gioppo:gioppo -R /home/gioppo/Development
