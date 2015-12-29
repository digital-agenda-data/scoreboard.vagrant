#!/usr/bin/env bash
#################################################################
# Digital Agenda Data (build system requirements) 


# Disable SELinux permanently after reboot
sudo sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
# Disable SELinux this session
sudo setenforce 0

# nameserver and yum update
sudo echo 'nameserver 8.8.8.8' > /etc/resolv.conf
sudo rm -f /var/cache/yum/timedhosts.txt
sudo yum update -y

# Apache
sudo yum install -y httpd
usermod apache -G vagrant
sudo systemctl enable httpd
sudo systemctl start httpd

sudo firewall-cmd --zone=public --add-port=80/tcp --permanent
# Remove these on public/production servers
sudo firewall-cmd --zone=public --add-port=8080-8082/tcp --permanent
sudo firewall-cmd --zone=public --add-port=8890/tcp --permanent
sudo firewall-cmd --zone=public --add-port=8441-8448/tcp --permanent
sudo firewall-cmd --reload
#sudo systemctl disable firewalld

#sudo mkdir /var/www/html/docroot/
#sudo chown -R root:apache /var/www/html/docroot/
#sudo restorecon -R /var/www/html/docroot/


# Apache - fix the VH
# sudo cp /vagrant/etc/httpd.conf /etc/httpd/conf/
# sudo systemctl restart httpd

sudo yum clean all

echo "WARNING! All passwords are set to 'vagrant'. The vagrant account is insecure (password/key)!"

install_virtuoso() {
  sudo yum install -y gcc gmake autoconf automake libtool flex bison gperf gawk m4 make openssl-devel readline-devel wget net-tools
  pushd /var/local
  # download source
  # git clone -b stable/7 git://github.com/openlink/virtuoso-opensource.git virtuoso-src
  # download and compile virtuoso
  if [ -f "/vagrant/bin/virtuoso-bin-7.2.2.CentOS7_1.x86_64.tar.gz" ]
  # pre-compiled binary files available at http://test.digital-agenda-data.eu/download/virtuoso-bin-7.2.2.CentOS7_1.x86_64.tar.gz
  then
    tar xzf /vagrant/bin/virtuoso-bin-7.2.2.CentOS7_1.x86_64.tar.gz -C /var/local
  else
    wget -N -P /vagrant/bin https://github.com/openlink/virtuoso-opensource/releases/download/v7.2.2.1/virtuoso-opensource-7.2.2.tar.gz
    tar xzf /vagrant/bin/virtuoso-opensource-7.2.2.tar.gz
    cd virtuoso-opensource-7.2.2
    ./autogen.sh
    ./configure --prefix=/var/local/virtuoso --with-readline
    make
    mkdir /var/local/virtuoso
    make install
  fi
  # update config files and data files
  mkdir -p /var/local/virtuoso/var/lib/virtuoso/production
  mkdir -p /var/local/virtuoso/var/lib/virtuoso/test
  VIRTUOSO_INI=virtuoso/var/lib/virtuoso/production/virtuoso.ini
  sudo cp virtuoso/var/lib/virtuoso/db/virtuoso.ini $VIRTUOSO_INI
  sudo sed -i "/^;HTTPLogFile/c\HTTPLogFile\=/var\/local\/virtuoso\/production.log" $VIRTUOSO_INI
  sudo sed -i "/^MaxClientConnections/c\MaxClientConnections=20" $VIRTUOSO_INI
  sudo sed -i "/^ServerThreads/c\ServerThreads=20" $VIRTUOSO_INI

  sudo sed -i "/^NumberOfBuffers/c\NumberOfBuffers=170000" $VIRTUOSO_INI
  sudo sed -i "/^MaxDirtyBuffers/c\MaxDirtyBuffers=130000" $VIRTUOSO_INI

  sudo sed -i '/^DirsAllowed/ s/$/, \/tmp, \/var\/local/' $VIRTUOSO_INI
  
  sudo sed -i "/^ResultSetMaxRows/c\ResultSetMaxRows=1000000" $VIRTUOSO_INI
  sudo sed -i "/^MaxQueryCostEstimationTime/c\MaxQueryCostEstimationTime=5000; in seconds" $VIRTUOSO_INI
  sudo sed -i "/^MaxQueryExecutionTime/c\MaxQueryExecutionTime=300; in seconds" $VIRTUOSO_INI
  sudo sed -i "/^DynamicLocal/c\DynamicLocal=1" $VIRTUOSO_INI

  sudo sed -i  's/\/var\/local\/virtuoso\/var\/lib\/virtuoso\/db\//\/var\/local\/virtuoso\/var\/lib\/virtuoso\/production\//g' $VIRTUOSO_INI

  # copy data files
  wget -N -P /vagrant/data http://test.digital-agenda-data.eu/download/virtuoso7-prod.db.gz
  #if [ ! -f /var/local/virtuoso/var/lib/virtuoso/production/virtuoso.db ]
  #then
  #  # gunzip on the host machine to prevent virtualbox crash
  #  gunzip -c /vagrant/data/virtuoso7-prod.db.gz > /var/local/virtuoso/var/lib/virtuoso/production/virtuoso.db
  #fi
  if [ ! -f /vagrant/data/virtuoso.db ]
  then
    # gunzip on the host machine to prevent virtualbox crash
    gunzip -c /vagrant/data/virtuoso7-prod.db.gz > /vagrant/data/virtuoso.db
    sudo ln -s /vagrant/data/virtuoso.db /var/local/virtuoso/var/lib/virtuoso/production/virtuoso.db
  fi

  sudo chown -R $user.$user /var/local/virtuoso

  # Put virtuoso bin into PATH.  
  sudo echo 'export PATH=$PATH:/var/local/virtuoso/bin' | sudo tee --append /home/$user/.bashrc > /dev/null
  sudo echo 'export PATH=$PATH:/var/local/virtuoso/bin' | sudo tee --append /home/vagrant/.bashrc > /dev/null

  sudo cp /vagrant/etc/virtuoso7 /etc/init.d
  sudo chkconfig --add virtuoso7
  sudo chkconfig --level 2345 virtuoso7 on
  sudo service virtuoso7 start

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
  wget -N -P /vagrant/data http://digital-agenda-data.eu/download/plone-storage.tar.gz
  sudo tar -xzvf /vagrant/data/plone-storage.tar.gz --directory=/var/local/plone/var

  sudo chown -R $user.$user /var/local/plone

  # TODO: fix apache config files
  sudo cp /vagrant/etc/scoreboard-prod.conf /etc/httpd/conf.d
  mkdir -p /var/www/html/prod/download
  sudo chown apache.apache /var/www/html -R
  sudo service httpd reload

  #start all
  sudo cp /vagrant/etc/supervisord-prod /etc/init.d
  sudo chkconfig --add supervisord-prod
  sudo chkconfig --level 2345 supervisord-prod on
  sudo service supervisord-prod start

  #su -c "/var/local/plone/bin/supervisord" scoreboard


  popd
}

install_java() {
  pushd /var/local
  # Install Oracle Java 8
  wget -N -P /vagrant/bin --no-cookies --no-check-certificate --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com%2F; oraclelicense=accept-securebackup-cookie" "http://download.oracle.com/otn-pub/java/jdk/8u60-b27/jdk-8u60-linux-x64.rpm" 
  sudo yum localinstall -y /vagrant/bin/jdk-8u60-linux-x64.rpm
  
  # Fix this issue: https://wiki.apache.org/tomcat/HowTo/FasterStartUp#Entropy_Source
  sudo sed -i 's|securerandom.source=file:/dev/random|securerandom.source=file:/dev/./urandom|g' /usr/java/jdk1.8.0_60/jre/lib/security/java.security
  
  echo "Java 8 installed in /usr/java/jdk1.8.0_60"
  # Install Apache Maven
  wget -N -P /vagrant/bin http://apache.javapipe.com/maven/maven-3/3.3.3/binaries/apache-maven-3.3.3-bin.tar.gz
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
  wget -N -P /vagrant/bin http://archive.apache.org/dist/tomcat/tomcat-8/v8.0.28/bin/apache-tomcat-8.0.28.tar.gz
  tar xvf /vagrant/bin/apache-tomcat-8.0.28.tar.gz -C /var/local
  sudo chown -R $user.$user /var/local/apache-tomcat-8.0.28
  ln -s /var/local/apache-tomcat-8.0.28 /var/local/tomcat-latest
  sudo chown -R $user.$user /var/local/tomcat-latest
  
  sudo cp /vagrant/etc/tomcat-latest /etc/init.d/
  sudo chkconfig --add tomcat-latest
  sudo chkconfig --level 2345 tomcat-latest on
  sudo service tomcat-latest start
  
  popd
}

# ELDA (1.2.21 vesion used)
install_elda() {
    mkdir -p /var/local/elda
    pushd /var/local/elda
      # Install and update the elda software
      wget -N -P /vagrant/bin https://elda.googlecode.com/files/elda-standalone-1.2.21.jar
      jar xf /vagrant/bin/elda-standalone-1.2.21.jar
      chmod 777 logs
      # Update the configuration files
      cp /vagrant/etc/elda-jetty.xml etc/jetty.xml
      cp /vagrant/etc/elda-scoreboard.ttl webapps/elda/specs/scoreboard.ttl
      cp /vagrant/etc/elda-web.xml webapps/elda/WEB-INF/web.xml
      cp /vagrant/etc/elda-index.html webapps/elda/WEB-INF/index.html
      cp /vagrant/etc/elda-E1.2.21-index.html /var/local/elda/webapps/elda/lda-assets/docs/E1.2.21-index.html
      cp /vagrant/etc/elda-E1.2.19-index.html /var/local/elda/webapps/elda/lda-assets/docs/E1.2.19-index.html
      cp -r webapps/elda/* webapps/root
      sudo chown -R $user.$user /var/local/elda
    popd
    sudo cp /vagrant/etc/elda /etc/init.d/
    sudo chkconfig --add elda
    sudo chkconfig --level 2345 elda on
    sudo service elda start
}

user=scoreboard
sudo adduser $user
sudo chmod o+w /var/local

if [ ! -d "/var/local/virtuoso" ]; then
    echo "Installing virtuoso..."
    install_virtuoso
else
    echo "Virtuoso already installed"
fi

if [ ! -d "/var/local/plone" ]; then
    echo "Installing Plone (production)..."
    install_plone
else
    echo "Plone (production) already installed"
fi

if [ ! -f "/usr/bin/java" ]; then
    install_java
else
    echo "Java already installed"
fi

if [ ! -f "/usr/local/elda" ]; then
    install_elda
else
    echo "Elda already installed"
fi

# install telnet
sudo yum install -y telnet
