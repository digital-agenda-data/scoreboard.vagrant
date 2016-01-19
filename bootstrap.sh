#!/usr/bin/env bash
#################################################################
# Digital Agenda Data (build system requirements)


# Disable SELinux permanently after reboot
sudo sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
# Disable SELinux this session
sudo setenforce 0

# nameserver and yum update
sudo echo 'nameserver 8.8.8.8' > /etc/resolv.conf
sudo rm -f /var/cache/yum/timedhosts.txt
sudo yum update -y --exclude=kernel*

# Apache
sudo yum install -y httpd
usermod apache -G vagrant
sudo systemctl enable httpd
sudo systemctl start httpd

sudo firewall-cmd --zone=public --add-port=80/tcp --permanent
sudo firewall-cmd --zone=public --add-port=443/tcp --permanent
# Remove these on public/production servers
sudo firewall-cmd --zone=public --add-port=8080-8082/tcp --permanent
sudo firewall-cmd --zone=public --add-port=8890-8891/tcp --permanent
sudo firewall-cmd --zone=public --add-port=8441-8448/tcp --permanent
sudo firewall-cmd --zone=public --add-port=1111-1112/tcp --permanent
sudo firewall-cmd --reload
#sudo systemctl disable firewalld

#sudo restorecon -R /var/www/html/docroot/

# sudo systemctl restart httpd

sudo yum clean all

echo "WARNING! All passwords are set to 'vagrant'. The vagrant account is insecure (password/key)!"

install_virtuoso() {
  sudo yum install -y gcc gmake autoconf automake libtool flex bison gperf gawk m4 make openssl-devel readline-devel wget net-tools
  pushd /var/local
  # git clone -b stable/7 git://github.com/openlink/virtuoso-opensource.git virtuoso-src
  # download and compile virtuoso
  VIRTUOSO_HOME=/var/local/virtuoso
  if [ -f "/vagrant/bin/virtuoso-bin-7.2.0.1.CentOS7_2.x86_64.tar.gz" ]
  # pre-compiled binary files available at http://85.9.22.69/scoreboard/download/virtuoso-bin-7.2.0.1.CentOS7_2.x86_64.tar.gz
  then
    tar xzf /vagrant/bin/virtuoso-bin-7.2.0.1.CentOS7_2.x86_64.tar.gz -C /var/local --no-same-owner
  else
    # download 7.2.0.1
    wget -nv -N -P /vagrant/bin/ https://github.com/openlink/virtuoso-opensource/releases/download/v7.2.0.1/virtuoso-opensource-7.2.0_p1.tar.gz
    tar xzf /vagrant/bin/virtuoso-opensource-7.2.0_p1.tar.gz --no-same-owner
    cd virtuoso-opensource-7.2.0_p1
    ./autogen.sh
    ./configure --prefix=$VIRTUOSO_HOME --with-readline
    make
    mkdir $VIRTUOSO_HOME
    make install
  fi
  # update config files and data files
  VIRTUOSO_INI=$VIRTUOSO_HOME/var/lib/virtuoso/db/virtuoso.ini
  sudo cp $VIRTUOSO_INI $VIRTUOSO_INI.original
  sudo sed -i "/HTTPLogFile/c\HTTPLogFile\=/var\/local\/virtuoso\/production.log" $VIRTUOSO_INI
  sudo sed -i "/^MaxClientConnections/c\MaxClientConnections=4" $VIRTUOSO_INI
  sudo sed -i "/^ServerThreads/c\ServerThreads=4" $VIRTUOSO_INI

  sudo sed -i "/^NumberOfBuffers/c\NumberOfBuffers=170000" $VIRTUOSO_INI
  sudo sed -i "/^MaxDirtyBuffers/c\MaxDirtyBuffers=130000" $VIRTUOSO_INI

  sudo sed -i '/^DirsAllowed/ s/$/, \/tmp, \/var\/www\/html\/download/, \/var\/local\/cr\/apphome\/tmp, \/var\/local\/cr\/apphome\/staging/' $VIRTUOSO_INI

  sudo sed -i "/^ResultSetMaxRows/c\ResultSetMaxRows=1000000" $VIRTUOSO_INI
  sudo sed -i "/^MaxQueryCostEstimationTime/c\MaxQueryCostEstimationTime=5000; in seconds" $VIRTUOSO_INI
  sudo sed -i "/^MaxQueryExecutionTime/c\MaxQueryExecutionTime=300; in seconds" $VIRTUOSO_INI
  sudo sed -i "/^DynamicLocal/c\DynamicLocal=1" $VIRTUOSO_INI

  # do not load the default plugins
  sudo sed -i 's/^\(Load[1-3]\)/;\1/g' $VIRTUOSO_INI

  # copy data files
  wget -nv -N -P /vagrant/data http://85.9.22.69/scoreboard/download/virtuoso6-prod.db.gz
  if [ ! -f /vagrant/data/virtuoso.db ]
  then
    # store on the host machine, to fit in available disk size
  fi
  
  if [ ! -f $VIRTUOSO_HOME/var/lib/virtuoso/db/virtuoso.db ]
  then
	sudo ln -s /vagrant/data/virtuoso.db $VIRTUOSO_HOME/var/lib/virtuoso/db/virtuoso.db
  fi

  sudo chown -R $user.$user $VIRTUOSO_HOME

  # Put virtuoso bin into PATH.
  sudo echo 'export PATH=$PATH:/var/local/virtuoso/bin' | sudo tee --append /home/$user/.bashrc > /dev/null
  sudo echo 'export PATH=$PATH:/var/local/virtuoso/bin' | sudo tee --append /home/vagrant/.bashrc > /dev/null

  sudo cp /vagrant/etc/virtuoso7.service /etc/systemd/system/
  #sudo systemctl enable virtuoso7


  sudo systemctl start virtuoso7

  popd
}

install_plone() {
  pushd /var/local

  curl https://raw.githubusercontent.com/pypa/pip/master/contrib/get-pip.py | python -
  sudo yum install -y python-virtualenv libffi-devel cairo libxslt-devel mod_ssl
  mkdir -p plone
  git clone https://github.com/digital-agenda-data/scoreboard.buildout.git plone
  cd plone
  virtualenv-2.7 .
  source bin/activate
  pip install setuptools==7.0 zc.buildout==2.2.5
  ln -s production.cfg buildout.cfg
  bin/buildout

  #get data fs
  wget -nv -N -P /vagrant/data http://85.9.22.69/scoreboard/download/plone-storage.tar.gz
  sudo tar -xzvf /vagrant/data/plone-storage.tar.gz --directory=/var/local/plone/var

  sudo chown -R $user.$user /var/local/plone

  #create cron for data export
  sudo chmod +x /var/local/plone/export/export_datasets_prod.sh
  line="30 23 * * * /var/local/plone/export/export_datasets_prod.sh"
  (sudo crontab -u scoreboard -l; echo "$line" ) | sudo crontab -u scoreboard -

  sudo cp /vagrant/etc/scoreboard-prod.conf /etc/httpd/conf.d
  sudo mkdir -p /var/www/html/download
  sudo chown apache.scoreboard /var/www/html -R
  sudo chmod g+w /var/www/html -R
  sudo systemctl reload httpd

  sudo cp /vagrant/etc/supervisord.service /etc/systemd/system/
  sudo systemctl enable supervisord
  sudo systemctl start supervisord

  popd
}

install_java() {
  pushd /var/local
  # Install Oracle Java 8
  wget -nv -N -P /vagrant/bin --no-cookies --no-check-certificate --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com%2F; oraclelicense=accept-securebackup-cookie" "http://download.oracle.com/otn-pub/java/jdk/8u60-b27/jdk-8u60-linux-x64.rpm"
  sudo yum localinstall -y /vagrant/bin/jdk-8u60-linux-x64.rpm

  # Fix this issue: https://wiki.apache.org/tomcat/HowTo/FasterStartUp#Entropy_Source
  sudo sed -i 's|securerandom.source=file:/dev/random|securerandom.source=file:/dev/./urandom|g' /usr/java/jdk1.8.0_60/jre/lib/security/java.security

  echo "Java 8 installed in /usr/java/jdk1.8.0_60"
  # Install Apache Maven
  wget -nv -N -P /vagrant/bin http://apache.javapipe.com/maven/maven-3/3.3.3/binaries/apache-maven-3.3.3-bin.tar.gz
  tar xvf /vagrant/bin/apache-maven-3.3.3-bin.tar.gz -C /var/local
  read -r -d '' RCLINES <<- 'EOF'
	export M2_HOME=/var/local/apache-maven-3.3.3
	export M2=$M2_HOME/bin
	export PATH=$M2:$PATH
	export JAVA_HOME=/usr/java/latest
EOF
  echo "$RCLINES" >> /home/$user/.bashrc
  echo "$RCLINES" >> /home/vagrant/.bashrc
  echo "$RCLINES" >> ~/.bashrc
  source ~/.bashrc
  echo "Apache Maven installed in $M2_HOME"

  # install Apache Tomcat 8
  wget -nv -N -P /vagrant/bin http://archive.apache.org/dist/tomcat/tomcat-8/v8.0.30/bin/apache-tomcat-8.0.30.tar.gz
  tar xvf /vagrant/bin/apache-tomcat-8.0.30.tar.gz -C /var/local
  sudo chown -R $user.$user /var/local/apache-tomcat-8.0.30
  ln -s /var/local/apache-tomcat-8.0.30 /var/local/tomcat-latest
  sudo chown -R $user.$user /var/local/tomcat-latest

  sudo cp /vagrant/etc/tomcat-latest.service /etc/systemd/system/
  sudo systemctl enable tomcat-latest
  sudo systemctl start tomcat-latest

  popd
}

# ELDA (1.2.21 vesion used)
install_elda() {
    mkdir -p /var/local/elda
    pushd /var/local/elda
      # Install and update the elda software
      wget -nv -N -P /vagrant/bin https://elda.googlecode.com/files/elda-standalone-1.2.21.jar
      jar xf /vagrant/bin/elda-standalone-1.2.21.jar
      chmod 777 logs
      # Update the configuration files
      sed -i "s/8080/8082/g" etc/jetty.xml
      sed -i "s/8443/8445/g" etc/jetty.xml
      cp /vagrant/etc/elda-scoreboard.ttl webapps/elda/specs/scoreboard.ttl
      sed -i "s/hello::specs\/hello-world.ttl/specs\/scoreboard.ttl/g" webapps/elda/WEB-INF/web.xml
      sed -i "/,.*\.ttl/d" webapps/elda/WEB-INF/web.xml
      # Fix some bugs
      sed -i "s/8080/8082/g" webapps/elda/index.html
      sed -i "s/url=E1.2.19-index.html/url=E1.2.21-index.html/g" webapps/elda/lda-assets/docs/quickstart.html
      for f in webapps/elda/lda-assets/images/grey/16x16/*%20*; do
        newname="$(echo $f | sed s/%20/\ /)"
        mv "$f" "$newname"
      done
      sudo chown -R $user.$user /var/local/elda
    popd
	
    sudo cp /vagrant/etc/elda.service /etc/systemd/system
	sudo systemctl enable elda
    sudo systemctl start elda
}

install_sparql_client() {
    pushd /var/local
      git clone https://github.com/digital-agenda-data/sparql-browser.git
      cd sparql-browser
      chmod +x run_sparql_browser.sh
      virtualenv sandbox
      source sandbox/bin/activate
      pip install -r requirements-dev.txt
      deactivate
      sudo chown -R $user.$user /var/local/sparql-browser
    popd
}

#
# Installation script of Content Registry.
#

install_contreg() {

	echo "Preparing production CR's application home and build directories..."
	# Prepare CR application home and build directories.
	mkdir -p /var/local/cr
	mkdir -p /var/local/cr/build
	mkdir -p /var/local/cr/apphome
	mkdir -p /var/local/cr/apphome/acl
	mkdir -p /var/local/cr/apphome/filestore
	mkdir -p /var/local/cr/apphome/staging
	mkdir -p /var/local/cr/apphome/tmp

	echo "Cloning and building production CR source code..."

	# Go into CR build directory and checkout CR source code from GitHub.
	pushd /var/local/cr/build
	git clone https://github.com/digital-agenda-data/scoreboard.contreg.git
	cd scoreboard.contreg
	git checkout upgrade-2016-incl-sesame-and-liquibase-v7201

	# Prepare local.properties.
	cp sample.properties local.properties
	sudo sed -i "/^\s*application.homeDir/c\application.homeDir\=/var\/local\/cr\/apphome" local.properties
	sudo sed -i "/^\s*application.homeURL/c\application.homeURL\=http:\/\/digital-agenda-data.eu\/data" local.properties

	# Build with Maven and ensure Liquibase changelog is synced.
	mvn -Dmaven.test.skip=true clean install

	echo "Syncing production CR's Liquibase changelog ..."
	mvn liquibase:changelogSync

	echo "Deploying production CR to production Tomcat ..."

	# Deploy to Tomcat.
	sudo rm -rf /var/local/tomcat-latest/webapps/data
	sudo rm -rf /var/local/tomcat-latest/work/Catalina/localhost/data
	sudo rm -rf /var/local/tomcat-latest/conf/Catalina/localhost/data.xml
	sudo cp ./target/cr-das.war /var/local/tomcat-latest/webapps/data.war

	# Ensure the correct owner of CR application directory.
	sudo chown -R $user.$user /var/local/cr

	echo "Restarting production Tomcat ..."
	# Restart Tomcat.
	sudo systemctl start tomcat-latest

	# Pop the current directory.
	popd
}

### TEST APPLICATIONS ###

install_test_virtuoso() {
  sudo yum install -y gcc gmake autoconf automake libtool flex bison gperf gawk m4 make openssl-devel readline-devel wget net-tools
  pushd /var/local
  # git clone -b stable/7 git://github.com/openlink/virtuoso-opensource.git virtuoso-src
  # download and compile virtuoso
  VIRTUOSO_HOME=/var/local/test-virtuoso
  if [ -f "/vagrant/bin/virtuoso-test-bin-7.2.0.1.CentOS7_2.x86_64.tar.gz" ]
  # pre-compiled binary files available at http://85.9.22.69/scoreboard/download/virtuoso-test-bin-7.2.0.1.CentOS7_2.x86_64.tar.gz
  then
    tar xzf /vagrant/bin/virtuoso-test-bin-7.2.0.1.CentOS7_2.x86_64.tar.gz -C /var/local --no-same-owner
  else
    # download 7.2.0.1
    wget -nv -N -P /vagrant/bin/ https://github.com/openlink/virtuoso-opensource/releases/download/v7.2.0.1/virtuoso-opensource-7.2.0_p1.tar.gz
    tar xzf /vagrant/bin/virtuoso-opensource-7.2.0_p1.tar.gz --no-same-owner
    cd virtuoso-opensource-7.2.0_p1
    ./autogen.sh
    ./configure --prefix=$VIRTUOSO_HOME --with-readline
    make
    mkdir $VIRTUOSO_HOME
    make install
  fi
  # update config files and data files
  VIRTUOSO_INI=$VIRTUOSO_HOME/var/lib/virtuoso/db/virtuoso.ini
  sudo cp $VIRTUOSO_INI $VIRTUOSO_INI.original
  sudo sed -i "/HTTPLogFile/c\HTTPLogFile\=/var\/local\/virtuoso\/test.log" $VIRTUOSO_INI
  sudo sed -i "/^MaxClientConnections/c\MaxClientConnections=4" $VIRTUOSO_INI
  sudo sed -i "/^ServerThreads/c\ServerThreads=4" $VIRTUOSO_INI

  sudo sed -i "/^NumberOfBuffers/c\NumberOfBuffers=170000" $VIRTUOSO_INI
  sudo sed -i "/^MaxDirtyBuffers/c\MaxDirtyBuffers=130000" $VIRTUOSO_INI

  sudo sed -i '/^DirsAllowed/ s/$/, \/tmp, \/var\/www\/test-html\/download/, \/var\/local\/crtest\/apphome\/tmp, \/var\/local\/crtest\/apphome\/staging/' $VIRTUOSO_INI

  sudo sed -i "/^ResultSetMaxRows/c\ResultSetMaxRows=1000000" $VIRTUOSO_INI
  sudo sed -i "/^MaxQueryCostEstimationTime/c\MaxQueryCostEstimationTime=5000; in seconds" $VIRTUOSO_INI
  sudo sed -i "/^MaxQueryExecutionTime/c\MaxQueryExecutionTime=300; in seconds" $VIRTUOSO_INI
  sudo sed -i "/^DynamicLocal/c\DynamicLocal=1" $VIRTUOSO_INI

  sudo sed -i "s/1111/1112/g" $VIRTUOSO_INI
  sudo sed -i "s/8890/8891/g" $VIRTUOSO_INI

  # do not load the default plugins
  sudo sed -i 's/^\(Load[1-3]\)/;\1/g' $VIRTUOSO_INI

  # copy data file for test instance
  wget -nv -N -P /vagrant/data http://85.9.22.69/scoreboard/download/virtuoso6-test.db.gz
  if [ ! -f /vagrant/data/virtuosotest.db ]
  then
    # store on the host machine, to fit in available disk size
    gunzip -c /vagrant/data/virtuoso6-test.db.gz > /vagrant/data/virtuosotest.db
  fi
  
  if [ ! -f $VIRTUOSO_HOME/var/lib/virtuoso/db/virtuoso.db ]
  then
	sudo ln -s /vagrant/data/virtuosotest.db $VIRTUOSO_HOME/var/lib/virtuoso/db/virtuoso.db
  fi
  sudo chown -R $user.$user $VIRTUOSO_HOME

  # Put virtuoso bin into PATH.
  sudo echo 'export PATH=$PATH:/var/local/test-virtuoso/bin' | sudo tee --append /home/$user/.bashrc > /dev/null
  sudo echo 'export PATH=$PATH:/var/local/test-virtuoso/bin' | sudo tee --append /home/vagrant/.bashrc > /dev/null

  sudo cp /vagrant/etc/virtuoso7 /etc/init.d/virtuoso7-test
  sudo sed -i "s/production/test/g" /etc/init.d/virtuoso7-test
  sudo sed -i "s/\/var\/local\/virtuoso\//\/var\/local\/test-virtuoso\//g" /etc/init.d/virtuoso7-test

  sudo cp /vagrant/etc/virtuoso7-test.service /etc/systemd/system/
  #sudo systemctl enable virtuoso7-test
  sudo systemctl start virtuoso7-test

  popd
}

install_test_plone() {
  pushd /var/local

  HOME_DIR=test-plone

  curl https://raw.githubusercontent.com/pypa/pip/master/contrib/get-pip.py | python -
  sudo yum install -y python-virtualenv libffi-devel cairo libxslt-devel mod_ssl
  mkdir -p $HOME_DIR
  git clone https://github.com/digital-agenda-data/scoreboard.buildout.git $HOME_DIR
  cd $HOME_DIR
  virtualenv-2.7 .
  source bin/activate
  pip install setuptools==7.0 zc.buildout==2.2.5
  ln -s test.cfg buildout.cfg

  # copy eggs from production when found
  if [ -d "/var/local/plone/eggs" ]; then cp -r /var/local/plone/eggs .; fi
  bin/buildout

  #get data fs
  wget -nv -N -P /vagrant/data http://85.9.22.69/scoreboard/download/plone-storage-test.tar.gz
  tar -xzvf /vagrant/data/plone-storage-test.tar.gz --directory=/var/local/$HOME_DIR/var

  sudo chown -R $user.$user /var/local/$HOME_DIR

  #create cron for data export
  sudo chmod +x /var/local/test-plone/export/export_datasets_test.sh
  line="15 23 * * * /var/local/test-plone/export/export_datasets_test.sh"
  (sudo crontab -u scoreboard -l; echo "$line" ) | sudo crontab -u scoreboard -

  sudo cp /vagrant/etc/scoreboard-test.conf /etc/httpd/conf.d
  sudo mkdir -p /var/www/test-html/download
  sudo chown apache.scoreboard /var/www/test-html -R
  sudo chmod g+w /var/www/test-html -R
  sudo systemctl reload httpd

  #sudo cp /vagrant/etc/plone-test /etc/init.d
  #sudo chkconfig --add plone-test
  #sudo chkconfig --level 2345 plone-test on
  #sudo systemctl start plone-test

  sudo cp /vagrant/etc/supervisord-test.service /etc/systemd/system/
  sudo systemctl enable supervisord-test
  sudo systemctl start supervisord-test

  popd
}

install_test_sparql_client() {
    pushd /var/local
      git clone https://github.com/digital-agenda-data/sparql-browser.git test-sparql-browser
      cd test-sparql-browser
      chmod +x run_sparql_browser.sh
      virtualenv sandbox
      source sandbox/bin/activate
      pip install -r requirements-dev.txt
      deactivate
      sed -i "s/digital-agenda-data.eu/test-virtuoso.digital-agenda-data.eu/g" run_sparql_browser.sh
      sed -i "s/55000/45300/g" run_sparql_browser.sh

      sudo chown -R $user.$user /var/local/test-sparql-browser
    popd
}

#
# Installation script for the test-instance of Content Registry, including test-Tomcat.
#
install_test_contreg() {

	mkdir -p /var/local/crtest
	echo "Installing test Tomcat..."

	# Install Tomcat's test-instance.
	tar xvf /vagrant/bin/apache-tomcat-8.0.30.tar.gz -C /var/local/crtest
	sudo chown -R $user.$user /var/local/crtest/apache-tomcat-8.0.30
	ln -s /var/local/crtest/apache-tomcat-8.0.30 /var/local/tomcat-test
	sudo chown -R $user.$user /var/local/tomcat-test

	echo "Configuring test Tomcat's server.xml ..."

	# Configure test-instance's server.xml
	sudo sed -i '/^\s*<Server port="8005"/c\<Server port="8006" shutdown="SHUTDOWN">' /var/local/tomcat-test/conf/server.xml
	sudo sed -i 's|Connector port="8080"|Connector port="8081"|g' /var/local/tomcat-test/conf/server.xml
	sudo sed -i 's|redirectPort="8443"|redirectPort="8444"|g' /var/local/tomcat-test/conf/server.xml
	sudo sed -i 's|Connector port="8009"|Connector port="8010"|g' /var/local/tomcat-test/conf/server.xml

	echo "Creating test Tomcat's service ..."

	# Create test-tomcat service, start it.
	sudo cp /vagrant/etc/tomcat-test /etc/init.d/
	sudo chkconfig --add tomcat-test
	sudo chkconfig --level 2345 tomcat-test on

	echo "Preparing test CR's application home and build directories..."

	# Prepare CR-test application home and build directories.
	mkdir -p /var/local/crtest/build
	mkdir -p /var/local/crtest/apphome
	mkdir -p /var/local/crtest/apphome/acl
	mkdir -p /var/local/crtest/apphome/filestore
	mkdir -p /var/local/crtest/apphome/staging
	mkdir -p /var/local/crtest/apphome/tmp

	echo "Cloning and building test CR's source code..."

	# Go into test-CR build directory and checkout CR source code from GitHub.
	pushd /var/local/crtest/build
	git clone https://github.com/digital-agenda-data/scoreboard.contreg.git
	cd scoreboard.contreg
	git checkout upgrade-2016-incl-sesame-and-liquibase-v7201

	# Prepare local.properties.
	sudo cp sample.properties local.properties
	sudo sed -i "/^\s*application.homeDir/c\application.homeDir\=/var\/local\/crtest\/apphome" local.properties
	sudo sed -i "/^\s*application.homeURL/c\application.homeURL\=http:\/\/test-cr.digital-agenda-data.eu" local.properties
	sudo sed -i "s/localhost:1111/localhost:1112/g" local.properties

	# Build with Maven and ensure Liquibase changelog is synced.
	mvn -Dmaven.test.skip=true clean install

	echo "Syncing test CR's Liquibase changelog ..."
	mvn liquibase:changelogSync

	echo "Deploying test CR to test Tomcat ..."

	# Backup Tomcat's default ROOT webapp.
	sudo mv /var/local/tomcat-test/webapps/ROOT /var/local/tomcat-test/webapps/ROOT_ORIG

	# Deploy to Tomcat.
	sudo rm -rf /var/local/tomcat-test/webapps/ROOT
	sudo rm -rf /var/local/tomcat-test/work/Catalina/localhost/ROOT*
	sudo rm -rf /var/local/tomcat-test/conf/Catalina/localhost/ROOT.xml
	sudo cp ./target/cr-das.war /var/local/tomcat-test/webapps/ROOT.war

	# Ensure the correct owner of CR application directory.
	sudo chown -R $user.$user /var/local/crtest

	echo "Restarting test Tomcat ..."
	# Restart Tomcat.
	sudo systemctl start tomcat-test

	# Pop the current directory.
	popd
}

#
# Installation script for piwik analytics.
#
install_piwik() {
  pushd /var/www/test-html
    wget -nv -N -P /vagrant/bin/ http://builds.piwik.org/piwik.zip
    sudo yum install -y unzip
    sudo mkdir analytics
    sudo unzip /vagrant/bin/piwik.zip -d analytics
    #TODO: change salt in config.ini.php
    cp /vagrant/etc/config.ini.php analytics/piwik/config/
    #mariadb
    sudo yum install -y mariadb-server mariadb
    sudo systemctl enable mariadb
    sudo systemctl start mariadb
    sudo mysql -u root -e "CREATE DATABASE piwik"
    sudo mysql -u root -e "CREATE USER 'piwik'@'localhost' IDENTIFIED BY 'piwik';"
    sudo mysql -u root -e "GRANT ALL PRIVILEGES ON piwik.* TO 'piwik'@'localhost';"
    wget -nv -N -P /vagrant/data http://85.9.22.69/scoreboard/download/piwik_dump.sql.gz
    gunzip -c /vagrant/data/piwik_dump.sql.gz > /vagrant/data/piwik_dump.sql
    sudo mysql -u root piwik < /vagrant/data/piwik_dump.sql
    # PHP
    sudo rpm -Uvh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    sudo rpm -Uvh https://mirror.webtatic.com/yum/el7/webtatic-release.rpm
    sudo yum install -y php55w php55w-cli php55w-common php55w-gd php55w-intl php55w-ldap php55w-mbstring php55w-mcrypt php55w-mysql php55w-opcache php55w-pdo php55w-pear php55w-pecl-imagick php55w-pecl-memcached php55w-xml
    sudo systemctl restart httpd
    sudo chown -R apache.scoreboard analytics
  popd
}

user=scoreboard
sudo adduser $user
sudo chmod o+w /var/local

# install telnet
sudo yum install -y telnet

# Install Virtuoso.
if [ ! -d "/var/local/virtuoso" ]; then
    echo "Installing virtuoso (production) ..."
    install_virtuoso
else
    echo "Virtuoso (production) already installed"
fi

# Install Plone.
if [ ! -d "/var/local/plone" ]; then
    echo "Installing Plone (production)..."
    install_plone
else
    echo "Plone (production) already installed"
fi

# Install Java + Tomcat.
if [ ! -f "/usr/bin/java" ]; then
	echo "Installing Java + Maven + Tomcat..."
    install_java
else
    echo "Java already installed"
fi

# Install Content Registry.
if [ ! -d "/var/local/cr" ]; then
	echo "Installing Content Registry (production) ..."
    install_contreg
else
    echo "Content Registry already installed"
fi

# Install ELDA.
if [ ! -d "/var/local/elda" ]; then
	echo "Installing ELDA (production) ..."
    install_elda
else
    echo "Elda already installed"
fi

# Install SPARQL browser.
if [ ! -d "/var/local/sparql-browser" ]; then
	echo "Installing SPARQL browser (production) ..."
    install_sparql_client
else
    echo "SPARQL browser (production) already installed"
fi

## TEST

if [ ! -d "/var/local/test-virtuoso" ]; then
    echo "Installing virtuoso (test)..."
    install_test_virtuoso
else
    echo "Virtuoso (test) already installed"
fi

if [ ! -d "/var/local/test-plone" ]; then
    echo "Installing Plone (test)..."
    install_test_plone
else
    echo "Plone (test) already installed"
fi

if [ ! -d "/var/local/test-sparql-browser" ]; then
	echo "Installing SPARQL browser (test) ..."
    install_test_sparql_client
else
    echo "SPARQL browser (test) already installed"
fi

# Install test-CR.
if [ ! -d "/var/local/crtest" ]; then
	echo "Installing Content Registry (test) ..."
    install_test_contreg
else
    echo "Content Registry test instance already installed!"
fi

# Install piwik
if [ ! -d "/var/www/test-html/analytics" ]; then
	echo "Installing Piwik ..."
    install_piwik
else
    echo "Piwik already installed!"
fi
