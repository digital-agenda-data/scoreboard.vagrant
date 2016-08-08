#!/usr/bin/env bash

# Simplified installation script for deploying the Digital Agenda Data tool suite
# This scripts only installs Content Registry and prerequisites (Java, Tomcat, Maven)
# Needs adaptations in case Java/Tomcat/Maven are already installed

export DAD_HOME=/var/local/scoreboard.install
export VIRTUOSO_ISQL=/var/local/virtuoso/bin/isql

export CR_HOME=/var/local/cr
export CR_SERVICE=cr
export CR_HOME_ESCAPED="/var\/local\/cr\/apphome"
export CR_HOME_URL="http:\/\/digital-agenda-data.eu\/data"
export CR_VIRTUOSO_HOST=localhost:1111
export CR_TOMCAT_WEBAPP=data
export CR_PORT_SHUTDOWN=8005
export CR_PORT_HTTP=8080
export CR_PORT_HTTPS=8443
export CR_PORT_AJP=8009


# for test environment use the variables below
#export CR_HOME=/var/local/test-cr
#export CR_SERVICE=cr-test
#export CR_HOME_ESCAPED="/var\/local\/test-cr\/apphome"
#export CR_HOME_URL="http:\/\/test-cr.digital-agenda-data.eu"
#export CR_VIRTUOSO_HOST=localhost:1112
#export CR_TOMCAT_WEBAPP=ROOT
#export CR_PORT_SHUTDOWN=8006
#export CR_PORT_HTTP=8081
#export CR_PORT_HTTPS=8444
#export CR_PORT_AJP=8010

export CATALINA_HOME=$CR_HOME/tomcat


# This script will not attempt to install httpd web server
# in case httpd is not installed, uncomment the following lines
#yum install -y httpd
#systemctl enable httpd
#systemctl start httpd
#firewall-cmd --zone=public --add-port=80/tcp --permanent
#firewall-cmd --zone=public --add-port=443/tcp --permanent


# Create user
user=scoreboard
adduser $user

# Make SELinux happy
restorecon -R /var/www/
setsebool -P httpd_can_network_connect 1

# Install git and various tools
yum install -y telnet git unzip vim
#  Install gcc and other prerequisites for Virtuoso
yum install -y gcc gmake autoconf automake libtool flex bison gperf gawk m4 make openssl-devel readline-devel wget net-tools
# Install python tools
yum install -y python-virtualenv libffi-devel cairo libxslt-devel mod_ssl git libjpeg-devel freetype-devel python-virtualenv
curl https://bootstrap.pypa.io/get-pip.py | python -

# Clone the repo in /var/local
git clone https://github.com/digital-agenda-data/scoreboard.vagrant.git $DAD_HOME

##############################
#   INSTALL JAVA and MAVEN   #
##############################

# Install Oracle Java 8
wget -nv -N -P $DAD_HOME/bin --no-cookies --no-check-certificate --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com%2F; oraclelicense=accept-securebackup-cookie" "http://download.oracle.com/otn-pub/java/jdk/8u60-b27/jdk-8u60-linux-x64.rpm"
yum localinstall -y $DAD_HOME/bin/jdk-8u60-linux-x64.rpm
# Fix this issue: https://wiki.apache.org/tomcat/HowTo/FasterStartUp#Entropy_Source
sed -i 's|securerandom.source=file:/dev/random|securerandom.source=file:/dev/./urandom|g' /usr/java/jdk1.8.0_60/jre/lib/security/java.security
echo "Java 8 installed in /usr/java/jdk1.8.0_60"
# Install Apache Maven
wget -nv -N -P $DAD_HOME/bin http://apache.javapipe.com/maven/maven-3/3.3.9/binaries/apache-maven-3.3.9-bin.tar.gz
tar xvf $DAD_HOME/bin/apache-maven-3.3.9-bin.tar.gz -C /var/local
read -r -d '' RCLINES <<- 'EOF'
	export M2_HOME=/var/local/apache-maven-3.3.9
	export M2=$M2_HOME/bin
	export PATH=$M2:$PATH
	export JAVA_HOME=/usr/java/latest
EOF
echo "$RCLINES" >> /home/$user/.bashrc
echo "$RCLINES" >> ~/.bashrc
source ~/.bashrc
echo "Apache Maven installed in $M2_HOME"



##########################################
#   INSTALL TOMCAT and CONTENT REGISTRY  #
##########################################

echo "Preparing production CR's application home and build directories..."
# Prepare CR application home and build directories.
mkdir -p $CR_HOME
mkdir -p $CR_HOME/build
mkdir -p $CR_HOME/apphome
mkdir -p $CR_HOME/apphome/acl
mkdir -p $CR_HOME/apphome/filestore
mkdir -p $CR_HOME/apphome/staging
mkdir -p $CR_HOME/apphome/tmp

echo "Installing Tomcat..."
# install Apache Tomcat 8
wget -nv -N -P $DAD_HOME/bin http://archive.apache.org/dist/tomcat/tomcat-8/v8.0.30/bin/apache-tomcat-8.0.30.tar.gz
tar xvf $DAD_HOME/bin/apache-tomcat-8.0.30.tar.gz -C /var/local
mv /var/local/apache-tomcat-8.0.30 $CATALINA_HOME


echo "Configuring test Tomcat's server.xml ..."
# Configure test-instance's server.xml
sed -i "/^\s*<Server port=\"8005\"/c\<Server port=\"8006\" shutdown=\"SHUTDOWN\">" $CATALINA_HOME/conf/server.xml
sed -i "s|Connector port=\"8080\"|Connector port=\"8081\"|g" $CATALINA_HOME/conf/server.xml
sed -i "s|redirectPort=\"8443\"|redirectPort=\"8444\"|g" $CATALINA_HOME/conf/server.xml
sed -i "s|Connector port=\"8009\"|Connector port=\"8010\"|g" $CATALINA_HOME/conf/server.xml

echo "Cloning and building CR source code..."
# Go into CR build directory and checkout CR source code from GitHub.
pushd $CR_HOME/build
git clone https://github.com/digital-agenda-data/scoreboard.contreg.git
cd scoreboard.contreg
#git checkout upgrade-2016-incl-sesame-and-liquibase-v7201
# Prepare local.properties.
cp sample.properties local.properties

sed -i "/^\s*application.homeDir/c\application.homeDir\=$CR_HOME_ESCAPED" local.properties
sed -i "/^\s*application.homeURL/c\application.homeURL\=$CR_HOME_URL" local.properties
sed -i "s/localhost:1111/$CR_VIRTUOSO_HOST/g" local.properties


# Build with Maven
mvn -Dmaven.test.skip=true clean package

# Deploy to Tomcat.
echo "Deploying production CR to production Tomcat ..."
rm -rf $CATALINA_HOME/webapps/$CR_TOMCAT_WEBAPP
rm -rf $CATALINA_HOME/work/Catalina/localhost/$CR_TOMCAT_WEBAPP
rm -rf $CATALINA_HOME/conf/Catalina/localhost/$CR_TOMCAT_WEBAPP.xml
cp ./target/cr-das.war $CATALINA_HOME/webapps/$CR_TOMCAT_WEBAPP.war

# Create required CR users in Virtuoso and other CR-specific Virtuoso preparations.
echo "Preparing Virtuoso for CR schema ..."
$VIRTUOSO_ISQL $CR_VIRTUOSO_HOST dba dba sql/virtuoso-preparation-before-schema-created.sql
echo "Creating CR's schema with Liquibase ..."
mvn liquibase:update

echo "Creating some initial data in CR production database..."
$VIRTUOSO_ISQL $CR_VIRTUOSO_HOST dba dba sql/initial-data-after-schema-created.sql

# Ensure the correct owner of CR application directory.
chown -R $user.$user $CR_HOME
echo "Starting $CR_SERVICE ..."
cp $DAD_HOME/etc/$CR_SERVICE.service /etc/systemd/system/
systemctl enable $CR_SERVICE
systemctl start $CR_SERVICE

###### END INSTALL CONTENT REGISTRY #################
