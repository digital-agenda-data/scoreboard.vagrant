#!/usr/bin/env bash
#################################################################
# Digital Agenda Data (build system requirements)
export DAD_HOME=/vagrant

# Disable SELinux permanently after reboot
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
# Disable SELinux this session
setenforce 0

# nameserver and yum update
echo 'nameserver 8.8.8.8' > /etc/resolv.conf
rm -f /var/cache/yum/timedhosts.txt
yum update -y --exclude=kernel*

# Apache
yum install -y httpd
usermod apache -G vagrant
systemctl enable httpd
systemctl start httpd

firewall-cmd --zone=public --add-port=80/tcp --permanent
firewall-cmd --zone=public --add-port=443/tcp --permanent
# Remove these on public/production servers
firewall-cmd --zone=public --add-port=8080-8082/tcp --permanent
firewall-cmd --zone=public --add-port=8890-8891/tcp --permanent
firewall-cmd --zone=public --add-port=8441-8448/tcp --permanent
firewall-cmd --zone=public --add-port=1111-1112/tcp --permanent
firewall-cmd --reload
#systemctl disable firewalld

#restorecon -R /var/www/

# systemctl restart httpd

yum install -y telnet git

yum clean all

user=scoreboard
adduser $user
chmod o+w /var/local


echo "WARNING! All passwords are set to 'vagrant'. The vagrant account is insecure (password/key)!"

install_virtuoso() {
  yum install -y gcc gmake autoconf automake libtool flex bison gperf gawk m4 make openssl-devel readline-devel wget net-tools
  pushd /var/local
  # git clone -b stable/7 git://github.com/openlink/virtuoso-opensource.git virtuoso-src
  # download and compile virtuoso
  VIRTUOSO_HOME=/var/local/virtuoso
  if [ -f "$DAD_HOME/bin/virtuoso-bin-7.2.4.2.CentOS7_2.x86_64.tar.gz" ]
  # pre-compiled binary files available at http://85.9.22.69/download/vagrant/virtuoso-bin-7.2.4.2.CentOS7_2.x86_64.tar.gz
  then
    tar xzf $DAD_HOME/bin/virtuoso-bin-7.2.4.2.CentOS7_2.x86_64.tar.gz -C /var/local --no-same-owner
  else
    # download 7.2.4.2
    wget -nv -N -P $DAD_HOME/bin/ https://github.com/openlink/virtuoso-opensource/releases/download/v7.2.4.2/virtuoso-opensource-7.2.4.2.tar.gz
    tar xzf $DAD_HOME/bin/virtuoso-opensource-7.2.4.2.tar.gz --no-same-owner
    cd virtuoso-opensource-7.2.4.2
    ./autogen.sh
    ./configure --prefix=$VIRTUOSO_HOME --with-readline --enable-fct-vad --enable-conductor-vad --with-port=1111
    make
    mkdir $VIRTUOSO_HOME
    make install
  fi
  # update config files and data files
  VIRTUOSO_INI=$VIRTUOSO_HOME/var/lib/virtuoso/db/virtuoso.ini
  cp $VIRTUOSO_INI $VIRTUOSO_INI.original
  sed -i "/HTTPLogFile/c\HTTPLogFile\=/var\/local\/virtuoso\/production.log" $VIRTUOSO_INI
  sed -i "/^MaxClientConnections/c\MaxClientConnections=4" $VIRTUOSO_INI
  sed -i "/^ServerThreads/c\ServerThreads=4" $VIRTUOSO_INI

  sed -i "/^NumberOfBuffers/c\NumberOfBuffers=170000" $VIRTUOSO_INI
  sed -i "/^MaxDirtyBuffers/c\MaxDirtyBuffers=130000" $VIRTUOSO_INI

  sed -i '/^DirsAllowed/ s/$/, \/tmp, \/var\/www\/html\/download\/, \/var\/local\/cr\/apphome\/tmp, \/var\/local\/cr\/apphome\/staging/' $VIRTUOSO_INI

  sed -i "/^ResultSetMaxRows/c\ResultSetMaxRows=1000000" $VIRTUOSO_INI
  sed -i "/^MaxQueryCostEstimationTime/c\MaxQueryCostEstimationTime=5000; in seconds" $VIRTUOSO_INI
  sed -i "/^MaxQueryExecutionTime/c\MaxQueryExecutionTime=300; in seconds" $VIRTUOSO_INI
  sed -i "/^DynamicLocal/c\DynamicLocal=1" $VIRTUOSO_INI

  # do not load the default plugins
  sed -i 's/^\(Load[1-3]\)/;\1/g' $VIRTUOSO_INI

  chown -R $user.$user $VIRTUOSO_HOME

  # Put virtuoso bin into PATH.
  echo 'export PATH=$PATH:/var/local/virtuoso/bin' | tee --append /home/$user/.bashrc > /dev/null
  echo 'export PATH=$PATH:/var/local/virtuoso/bin' | tee --append /home/vagrant/.bashrc > /dev/null

  cp $DAD_HOME/etc/virtuoso7.service /etc/systemd/system/
  cp $DAD_HOME/etc/virtuoso.env /root/virtuoso.env
  cp $DAD_HOME/misc/shutdown.sql $VIRTUOSO_HOME/var/lib/virtuoso/db/
  systemctl enable virtuoso7
  systemctl start virtuoso7

  # download the graph and import it
  echo "Importing the production graph..."
  rm -rf /tmp/prod_export_graph
  wget -nv -N -P /tmp/ http://85.9.22.69/download/vagrant/prod_export_graph.tgz
  tar xzf /tmp/prod_export_graph.tgz -C /tmp --no-same-owner
  $VIRTUOSO_HOME/bin/isql 1111 dba dba $DAD_HOME/misc/import_prod.sql

  popd
}

install_plone() {
  pushd /var/local

  curl https://bootstrap.pypa.io/get-pip.py | python -
  yum install -y python-virtualenv libffi-devel cairo libxslt-devel mod_ssl git libjpeg-devel freetype-devel
  mkdir -p plone
  git clone https://github.com/digital-agenda-data/scoreboard.buildout.git plone
  cd plone
  virtualenv-2.7 .
  source bin/activate
  pip install setuptools==7.0 zc.buildout==2.2.5
  deactivate
  ln -s production.cfg buildout.cfg
  bin/buildout

  #get data fs
  wget -nv -N -P $DAD_HOME/data http://85.9.22.69/download/vagrant/plone-storage.tar.gz
  tar -xzvf $DAD_HOME/data/plone-storage.tar.gz --directory=/var/local/plone/var

  chown -R $user.$user /var/local/plone

  #create cron for data export
  chmod +x /var/local/plone/export/export_datasets_prod.sh /var/local/plone/export/export_datasets.py

  line="30 23 * * * /var/local/plone/export/export_datasets_prod.sh"
  (crontab -u $user -l; echo "$line" ) | crontab -u $user -

  cp $DAD_HOME/etc/scoreboard-prod.conf /etc/httpd/conf.d
  mkdir -p /var/www/html/download
  chown apache.scoreboard /var/www/html -R
  chmod g+w /var/www/html -R
  systemctl reload httpd

  cp $DAD_HOME/etc/supervisord.service /etc/systemd/system/
  systemctl enable supervisord
  systemctl start supervisord

  popd
}

install_java() {
  pushd /var/local
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
  echo "$RCLINES" >> /home/vagrant/.bashrc
  echo "$RCLINES" >> ~/.bashrc
  source ~/.bashrc
  echo "Apache Maven installed in $M2_HOME"

  popd
}

# ELDA (1.2.21 vesion used)
install_elda() {
    mkdir -p /var/local/elda
    pushd /var/local/elda
      # Install and update the elda software
      wget -nv -N -P $DAD_HOME/bin https://elda.googlecode.com/files/elda-standalone-1.2.21.jar
      jar xf $DAD_HOME/bin/elda-standalone-1.2.21.jar
      chmod 777 logs
      # Update the configuration files
      sed -i "s/8080/8082/g" etc/jetty.xml
      sed -i "s/8443/8445/g" etc/jetty.xml
      cp $DAD_HOME/etc/elda-scoreboard.ttl webapps/elda/specs/scoreboard.ttl
      sed -i "s/hello::specs\/hello-world.ttl/specs\/scoreboard.ttl/g" webapps/elda/WEB-INF/web.xml
      sed -i "/,.*\.ttl/d" webapps/elda/WEB-INF/web.xml
      # Fix some bugs
      sed -i "s/8080/8082/g" webapps/elda/index.html
      sed -i "s/url=E1.2.19-index.html/url=E1.2.21-index.html/g" webapps/elda/lda-assets/docs/quickstart.html
      for f in webapps/elda/lda-assets/images/grey/16x16/*%20*; do
        newname="$(echo $f | sed s/%20/\ /)"
        mv "$f" "$newname"
      done
      chown -R $user.$user /var/local/elda
    popd

    cp $DAD_HOME/etc/elda.service /etc/systemd/system
    systemctl enable elda
    systemctl start elda
}

install_sparql_client() {
    curl https://bootstrap.pypa.io/get-pip.py | python -
    yum install -y python-virtualenv
    pushd /var/local
      git clone https://github.com/digital-agenda-data/sparql-browser.git
      cd sparql-browser
      chmod +x run_sparql_browser.sh
      virtualenv sandbox
      source sandbox/bin/activate
      pip install -r requirements-dev.txt
      deactivate
      chown -R $user.$user /var/local/sparql-browser
      cp $DAD_HOME/etc/sparql.service /etc/systemd/system/
      systemctl enable sparql
      systemctl start sparql
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
    
    echo "Installing Tomcat..."
    # install Apache Tomcat 8
    CATALINA_HOME=/var/local/cr/tomcat
    wget -nv -N -P $DAD_HOME/bin http://archive.apache.org/dist/tomcat/tomcat-8/v8.0.30/bin/apache-tomcat-8.0.30.tar.gz
    tar xvf $DAD_HOME/bin/apache-tomcat-8.0.30.tar.gz -C /var/local
    mv /var/local/apache-tomcat-8.0.30 $CATALINA_HOME

    cp $DAD_HOME/etc/cr.service /etc/systemd/system/
    systemctl enable cr

    echo "Cloning and building production CR source code..."

    # Go into CR build directory and checkout CR source code from GitHub.
    pushd /var/local/cr/build
    git clone https://github.com/digital-agenda-data/scoreboard.contreg.git
    cd scoreboard.contreg
    #git checkout upgrade-2016-incl-sesame-and-liquibase-v7201

    # Prepare local.properties.
    cp sample.properties local.properties
    sed -i "/^\s*application.homeDir/c\application.homeDir\=/var\/local\/cr\/apphome" local.properties
    sed -i "/^\s*application.homeURL/c\application.homeURL\=http:\/\/digital-agenda-data.eu\/data" local.properties

    # Build with Maven
    mvn -Dmaven.test.skip=true clean package

    # Create required CR users in Virtuoso and other CR-specific Virtuoso preparations.
    echo "Preparing Virtuoso for CR production schema ..."
    /var/local/virtuoso/bin/isql 1111 dba dba sql/virtuoso-preparation-before-schema-created.sql

    echo "Creating production CR's schema with Liquibase ..."
    mvn liquibase:update

    echo "Creating some initial data in CR production database..."
    /var/local/virtuoso/bin/isql 1111 dba dba sql/initial-data-after-schema-created.sql

    # Deploy to Tomcat.
    echo "Deploying production CR to production Tomcat ..."
    rm -rf $CATALINA_HOME/webapps/data
    rm -rf $CATALINA_HOME/work/Catalina/localhost/data
    rm -rf $CATALINA_HOME/conf/Catalina/localhost/data.xml
    cp ./target/cr-das.war $CATALINA_HOME/webapps/data.war

    # Ensure the correct owner of CR application directory.
    chown -R $user.$user /var/local/cr

    echo "Starting production Tomcat ..."
    # Start Tomcat.
    systemctl start cr

    # Pop the current directory.
    popd
}

### TEST APPLICATIONS ###

install_test_virtuoso() {
  yum install -y gcc gmake autoconf automake libtool flex bison gperf gawk m4 make openssl-devel readline-devel wget net-tools
  pushd /var/local
  # git clone -b stable/7 git://github.com/openlink/virtuoso-opensource.git virtuoso-src
  # download and compile virtuoso
  VIRTUOSO_HOME=/var/local/test-virtuoso
  if [ -f "$DAD_HOME/bin/virtuoso-test-bin-7.2.4.2.CentOS7_2.x86_64.tar.gz" ]
  # pre-compiled binary files available at http://85.9.22.69/download/vagrant/virtuoso-test-bin-7.2.4.2.CentOS7_2.x86_64.tar.gz
  then
    tar xzf $DAD_HOME/bin/virtuoso-test-bin-7.2.4.2.CentOS7_2.x86_64.tar.gz -C /var/local --no-same-owner
  else
    # download 7.2.0.1
    wget -nv -N -P $DAD_HOME/bin/ https://github.com/openlink/virtuoso-opensource/releases/download/v7.2.4.2/virtuoso-opensource-7.2.4.2.tar.gz
    tar xzf $DAD_HOME/bin/virtuoso-opensource-7.2.4.2.tar.gz --no-same-owner
    cd virtuoso-opensource-7.2.4.2
    ./autogen.sh
    ./configure --prefix=$VIRTUOSO_HOME --with-readline --enable-fct-vad --enable-conductor-vad --with-port=1112
    make
    mkdir $VIRTUOSO_HOME
    make install
  fi
  # update config files and data files
  VIRTUOSO_INI=$VIRTUOSO_HOME/var/lib/virtuoso/db/virtuoso.ini
  cp $VIRTUOSO_INI $VIRTUOSO_INI.original
  sed -i "/HTTPLogFile/c\HTTPLogFile\=/var\/local\/virtuoso\/test.log" $VIRTUOSO_INI
  sed -i "/^MaxClientConnections/c\MaxClientConnections=4" $VIRTUOSO_INI
  sed -i "/^ServerThreads/c\ServerThreads=4" $VIRTUOSO_INI

  sed -i "/^NumberOfBuffers/c\NumberOfBuffers=170000" $VIRTUOSO_INI
  sed -i "/^MaxDirtyBuffers/c\MaxDirtyBuffers=130000" $VIRTUOSO_INI

  sed -i '/^DirsAllowed/ s/$/, \/tmp, \/var\/www\/test-html\/download\/, \/var\/local\/test-cr\/apphome\/tmp, \/var\/local\/test-cr\/apphome\/staging/' $VIRTUOSO_INI

  sed -i "/^ResultSetMaxRows/c\ResultSetMaxRows=1000000" $VIRTUOSO_INI
  sed -i "/^MaxQueryCostEstimationTime/c\MaxQueryCostEstimationTime=5000; in seconds" $VIRTUOSO_INI
  sed -i "/^MaxQueryExecutionTime/c\MaxQueryExecutionTime=300; in seconds" $VIRTUOSO_INI
  sed -i "/^DynamicLocal/c\DynamicLocal=1" $VIRTUOSO_INI

  sed -i "s/1111/1112/g" $VIRTUOSO_INI
  sed -i "s/8890/8891/g" $VIRTUOSO_INI

  # do not load the default plugins
  sed -i 's/^\(Load[1-3]\)/;\1/g' $VIRTUOSO_INI


  chown -R $user.$user $VIRTUOSO_HOME

  # Put virtuoso bin into PATH.
  echo 'export PATH=$PATH:/var/local/test-virtuoso/bin' | tee --append /home/$user/.bashrc > /dev/null
  echo 'export PATH=$PATH:/var/local/test-virtuoso/bin' | tee --append /home/vagrant/.bashrc > /dev/null

  cp $DAD_HOME/etc/virtuoso7-test.service /etc/systemd/system/
  cp $DAD_HOME/etc/virtuoso.env /root/virtuoso7-test.env
  cp $DAD_HOME/misc/shutdown.sql $VIRTUOSO_HOME/var/lib/virtuoso/db/
  systemctl enable virtuoso7-test
  systemctl start virtuoso7-test

  echo "Importing the test graph..."
  rm -rf /tmp/test_export_graph
  wget -nv -N -P /tmp/ http://85.9.22.69/download/vagrant/test_export_graph.tgz
  tar xzf /tmp/test_export_graph.tgz -C /tmp --no-same-owner
  $VIRTUOSO_HOME/bin/isql 1112 dba dba $DAD_HOME/misc/import_test.sql
  popd
}

install_test_plone() {
  pushd /var/local

  HOME_DIR=test-plone

  curl https://bootstrap.pypa.io/get-pip.py | python -
  yum install -y python-virtualenv libffi-devel cairo libxslt-devel mod_ssl git libjpeg-devel freetype-devel
  mkdir -p $HOME_DIR
  git clone https://github.com/digital-agenda-data/scoreboard.buildout.git $HOME_DIR
  cd $HOME_DIR
  virtualenv-2.7 .
  source bin/activate
  pip install setuptools==7.0 zc.buildout==2.2.5
  deactivate
  ln -s test.cfg buildout.cfg

  # copy eggs from production when found
  if [ -d "/var/local/plone/eggs" ]; then cp -r /var/local/plone/eggs .; fi
  bin/buildout

  #get data fs
  wget -nv -N -P $DAD_HOME/data http://85.9.22.69/download/vagrant/plone-storage-test.tar.gz
  tar -xzvf $DAD_HOME/data/plone-storage-test.tar.gz --directory=/var/local/$HOME_DIR/var

  chown -R $user.$user /var/local/$HOME_DIR

  #create cron for data export
  chmod +x /var/local/test-plone/export/export_datasets_test.sh /var/local/plone/export/export_datasets.py
  line="15 23 * * * /var/local/test-plone/export/export_datasets_test.sh"
  (crontab -u $user -l; echo "$line" ) | crontab -u $user -

  cp $DAD_HOME/etc/scoreboard-test.conf /etc/httpd/conf.d
  mkdir -p /var/www/test-html/download
  chown apache.scoreboard /var/www/test-html -R
  chmod g+w /var/www/test-html -R
  systemctl reload httpd


  cp $DAD_HOME/etc/supervisord-test.service /etc/systemd/system/
  systemctl enable supervisord-test
  systemctl start supervisord-test

  popd
}

install_test_sparql_client() {
    curl https://bootstrap.pypa.io/get-pip.py | python -
    yum install -y python-virtualenv
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

      chown -R $user.$user /var/local/test-sparql-browser
      cp $DAD_HOME/etc/sparql-test.service /etc/systemd/system/
      systemctl enable sparql-test
      systemctl start sparql-test
    popd
}

#
# Installation script for the test-instance of Content Registry, including test-Tomcat.
#
install_test_contreg() {

    mkdir -p /var/local/test-cr
    echo "Installing test Tomcat..."
    CATALINA_HOME=/var/local/test-cr/tomcat

    # Install Tomcat's test-instance.
    tar xvf $DAD_HOME/bin/apache-tomcat-8.0.30.tar.gz -C /var/local/test-cr
    mv /var/local/test-cr/apache-tomcat-8.0.30 $CATALINA_HOME

    echo "Configuring test Tomcat's server.xml ..."

    # Configure test-instance's server.xml
    sed -i '/^\s*<Server port="8005"/c\<Server port="8006" shutdown="SHUTDOWN">' $CATALINA_HOME/conf/server.xml
    sed -i 's|Connector port="8080"|Connector port="8081"|g' $CATALINA_HOME/conf/server.xml
    sed -i 's|redirectPort="8443"|redirectPort="8444"|g' $CATALINA_HOME/conf/server.xml
    sed -i 's|Connector port="8009"|Connector port="8010"|g' $CATALINA_HOME/conf/server.xml

    echo "Creating test Tomcat's service ..."

    # Create test-tomcat service, start it.
    cp $DAD_HOME/etc/cr-test.service /etc/systemd/system/
    systemctl enable cr-test

    echo "Preparing test CR's application home and build directories..."

    # Prepare CR-test application home and build directories.
    mkdir -p /var/local/test-cr/build
    mkdir -p /var/local/test-cr/apphome
    mkdir -p /var/local/test-cr/apphome/acl
    mkdir -p /var/local/test-cr/apphome/filestore
    mkdir -p /var/local/test-cr/apphome/staging
    mkdir -p /var/local/test-cr/apphome/tmp

    echo "Cloning and building test CR's source code..."

    # Go into test-CR build directory and checkout CR source code from GitHub.
    pushd /var/local/test-cr/build
    git clone https://github.com/digital-agenda-data/scoreboard.contreg.git
    cd scoreboard.contreg
    #git checkout upgrade-2016-incl-sesame-and-liquibase-v7201

    # Prepare local.properties.
    cp sample.properties local.properties
    sed -i "/^\s*application.homeDir/c\application.homeDir\=/var\/local\/test-cr\/apphome" local.properties
    sed -i "/^\s*application.homeURL/c\application.homeURL\=http:\/\/test-cr.digital-agenda-data.eu" local.properties
    sed -i "s/localhost:1111/localhost:1112/g" local.properties

    # Build with Maven and ensure Liquibase changelog is synced.
    mvn -Dmaven.test.skip=true clean package

    # Create required CR users in Virtuoso and other CR-specific Virtuoso preparations.
    echo "Preparing Virtuoso for test-CR schema ..."
    /var/local/test-virtuoso/bin/isql 1112 dba dba sql/virtuoso-preparation-before-schema-created.sql

    echo "Creating test-CR schema with Liquibase ..."
    mvn liquibase:update

    echo "Creating some initial data in CR test database..."
    /var/local/test-virtuoso/bin/isql 1112 dba dba sql/initial-data-after-schema-created.sql

    # Deploy to Tomcat.
    echo "Deploying test CR to test Tomcat ..."

    # Backup Tomcat's default ROOT webapp.
    mv $CATALINA_HOME/webapps/ROOT $CATALINA_HOME/webapps/ROOT_ORIG

    # Deploy to Tomcat.
    rm -rf $CATALINA_HOME/webapps/ROOT
    rm -rf $CATALINA_HOME/work/Catalina/localhost/ROOT*
    rm -rf $CATALINA_HOME/conf/Catalina/localhost/ROOT.xml
    cp ./target/cr-das.war $CATALINA_HOME/webapps/ROOT.war

    # Ensure the correct owner of CR application directory.
    chown -R $user.$user /var/local/test-cr

    echo "Starting test Tomcat ..."

    # Start test tomcat
    systemctl start cr-test

    # Pop the current directory.
    popd
}

#
# Installation script for piwik analytics.
#
install_piwik() {
  mkdir -p /var/www/test-html/analytics
  pushd /var/www/test-html
    wget -nv -N -P $DAD_HOME/bin/ http://builds.piwik.org/piwik.zip
    yum install -y unzip
    unzip $DAD_HOME/bin/piwik.zip -d analytics
    #TODO: change salt in config.ini.php
    cp $DAD_HOME/etc/config.ini.php analytics/piwik/config/
    #mariadb
    yum install -y mariadb-server mariadb
    systemctl enable mariadb
    systemctl start mariadb
    mysql -u root -e "CREATE DATABASE piwik"
    mysql -u root -e "CREATE USER 'piwik'@'localhost' IDENTIFIED BY 'piwik';"
    mysql -u root -e "GRANT ALL PRIVILEGES ON piwik.* TO 'piwik'@'localhost';"
    wget -nv -N -P $DAD_HOME/data http://85.9.22.69/download/vagrant/piwik_dump.sql.gz
    gunzip -c $DAD_HOME/data/piwik_dump.sql.gz > $DAD_HOME/data/piwik_dump.sql
    mysql -u root piwik < $DAD_HOME/data/piwik_dump.sql
    # PHP
    rpm -Uvh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    rpm -Uvh https://mirror.webtatic.com/yum/el7/webtatic-release.rpm
    yum install -y php55w php55w-cli php55w-common php55w-gd php55w-intl php55w-ldap php55w-mbstring php55w-mcrypt php55w-mysql php55w-opcache php55w-pdo php55w-pear php55w-pecl-imagick php55w-pecl-memcached php55w-xml
    chown apache.scoreboard /var/www/test-html -R
    chmod g+w /var/www/test-html -R
    systemctl restart httpd
  popd
}

#
# Installation script for Apache Solr
#
install_solr() {
  yum install -y lsof
  pushd /var/local
    SOLR_HOME=/var/local/solr
    wget -nv -N http://www-eu.apache.org/dist/lucene/solr/6.2.1/solr-6.2.1.tgz
    tar xzf solr-6.2.1.tgz solr-6.2.1/bin/install_solr_service.sh --strip-components=2
    ./install_solr_service.sh solr-6.2.1.tgz -d $SOLR_HOME -u $user
    # production
    mkdir -p $SOLR_HOME/data/scoreboard/data
    cp -r /opt/solr/server/solr/configsets/basic_configs/conf/ $SOLR_HOME/data/scoreboard/
    gunzip -c $DAD_HOME/etc/solr/synonyms_wordnet.txt.gz > $SOLR_HOME/data/scoreboard/conf/lang/synonyms_en.txt
    # replace solrconfig.xml; use backslash to avoid alias cp = cp -i
    \cp $DAD_HOME/etc/solr/solrconfig.xml $SOLR_HOME/data/scoreboard/conf
    \cp $DAD_HOME/etc/solr/en_GB.* $SOLR_HOME/data/scoreboard/conf/lang
    \cp $DAD_HOME/etc/solr/stemdict_en.txt $SOLR_HOME/data/scoreboard/conf/lang
    \cp $DAD_HOME/etc/solr/managed-schema $SOLR_HOME/data/scoreboard/conf

    # test
    mkdir -p $SOLR_HOME/data/scoreboardtest/data
    cp -r /opt/solr/server/solr/configsets/basic_configs/conf/ $SOLR_HOME/data/scoreboardtest/
    gunzip -c $DAD_HOME/etc/solr/synonyms_wordnet.txt.gz > $SOLR_HOME/data/scoreboardtest/conf/lang/synonyms_en.txt
    \cp $DAD_HOME/etc/solr/solrconfig.xml $SOLR_HOME/data/scoreboardtest/conf
    \cp $DAD_HOME/etc/solr/en_GB.* $SOLR_HOME/data/scoreboardtest/conf/lang
    \cp $DAD_HOME/etc/solr/stemdict_en.txt $SOLR_HOME/data/scoreboardtest/conf/lang
    \cp $DAD_HOME/etc/solr/managed-schema $SOLR_HOME/data/scoreboardtest/conf

    chown -R $user.$user $SOLR_HOME
    # start solr
    service solr start
    # create cores
    curl "http://localhost:8983/solr/admin/cores?action=CREATE&name=scoreboard&instanceDir=scoreboard&dataDir=data"
    curl "http://localhost:8983/solr/admin/cores?action=CREATE&name=scoreboardtest&instanceDir=scoreboardtest&dataDir=data"
  popd
}

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
if [ ! -d "/var/local/test-cr" ]; then
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
