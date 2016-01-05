#!/usr/bin/env bash
#use this script to prepare a physical machine for ./bootstrap.sh
#as root
yum install -y git
git clone https://github.com/digital-agenda-data/scoreboard.vagrant.git /vagrant
mkdir -p /vagrant/bin
mkdir -p /vagrant/data
find etc ! -name '*.ttl' ! -name '*.conf' | xargs chmod +x
# Optional: download binary files
wget -N -P /vagrant/bin --no-cookies --no-check-certificate --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com%2F; oraclelicense=accept-securebackup-cookie" "http://download.oracle.com/otn-pub/java/jdk/8u60-b27/jdk-8u60-linux-x64.rpm" 
wget -N -P /vagrant/bin http://apache.javapipe.com/maven/maven-3/3.3.3/binaries/apache-maven-3.3.3-bin.tar.gz
wget -N -P /vagrant/bin http://archive.apache.org/dist/tomcat/tomcat-8/v8.0.28/bin/apache-tomcat-8.0.28.tar.gz
wget -N -P /vagrant/bin https://elda.googlecode.com/files/elda-standalone-1.2.21.jar
wget -N -P /vagrant/bin http://85.9.22.69/scoreboard/download/virtuoso-bin-7.2.2.CentOS7_1.x86_64.tar.gz
wget -N -P /vagrant/data http://85.9.22.69/scoreboard/download/virtuoso7-prod.db.gz
wget -N -P /vagrant/data http://85.9.22.69/scoreboard/download/virtuoso7-test.db.gz
wget -N -P /vagrant/data http://85.9.22.69/scoreboard/download/plone-storage.tar.gz
wget -N -P /vagrant/data http://85.9.22.69/scoreboard/download/plone-storage-test.tar.gz
mkdir -p /var/local/virtuoso/var/lib/virtuoso/production
gunzip -c /vagrant/data/virtuoso7-prod.db.gz > /vagrant/data/virtuoso.db
mv /vagrant/data/virtuoso.db /var/local/virtuoso/var/lib/virtuoso/production
mkdir -p /var/local/virtuoso/var/lib/virtuoso/test
gunzip -c /vagrant/data/virtuoso7-test.db.gz > /vagrant/data/virtuosotest.db
mv /vagrant/data/virtuosotest.db /var/local/virtuoso/var/lib/virtuoso/test/virtuoso.db
