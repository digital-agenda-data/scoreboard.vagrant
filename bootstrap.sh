#!/usr/bin/env bash
#################################################################
# Digital Agenda Data (build system requirements) 


# Disable SELinux permanently after reboot
sudo sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
# Disable SELinux this session
sudo sudo setenforce 0

# nameserver and yum update
sudo echo 'nameserver 8.8.8.8' > /etc/resolv.conf
sudo rm -f /var/cache/yum/timedhosts.txt
sudo yum update -y

# Apache
sudo yum install -y httpd
usermod apache -G vagrant
sudo systemctl enable httpd
sudo systemctl start httpd

#sudo firewall-cmd --zone=public --add-port=80/tcp --permanent
#sudo firewall-cmd --reload
#sudo systemctl stop firewalld

sudo mkdir /var/www/html/docroot/
sudo chown -R root:apache /var/www/html/docroot/
sudo restorecon -R /var/www/html/docroot/


# Apache - fix the VH
# sudo cp /vagrant/etc/httpd.conf /etc/httpd/conf/
# sudo systemctl restart httpd

sudo yum clean all

echo "WARNING! All passwords are set to 'vagrant'. The vagrant account is insecure (password/key)!"
sudo adduser scoreboard
sudo chmod o+w /var/local

echo "Installing virtuoso..."
#install_virtuoso()

install_virtuoso() {
  sudo yum install -y gcc gmake autoconf automake libtool flex bison gperf gawk m4 make openssl-devel readline-devel wget net-tools
  pushd /var/local
  # download source
  # git clone -b stable/7 git://github.com/openlink/virtuoso-opensource.git virtuoso-src
  # download and compile virtuoso
  wget https://github.com/openlink/virtuoso-opensource/releases/download/v7.2.1/virtuoso-opensource-7.2.1.tar.gz
  tar xzf virtuoso-opensource-7.2.1.tar.gz
  cd virtuoso-opensource-7.2.1
  ./autogen.sh
  ./configure --prefix=/var/local/virtuoso --with-readline
  make
  mkdir /var/local/virtuoso
  make install
  # update config files and data files
  mkdir -p /var/local/virtuoso/var/lib/virtuoso/production
  mkdir -p /var/local/virtuoso/var/lib/virtuoso/test
  VIRTUOSO_INI=virtuoso/var/lib/virtuoso/production/virtuoso.ini
  cp virtuoso/var/lib/virtuoso/db/virtuoso.ini $VIRTUOSO_INI
  sed -i "/^;HTTPLogFile/c\HTTPLogFile\=/var\/local\/virtuoso\/production.log" $VIRTUOSO_INI
  sed -i "/^MaxClientConnections/c\MaxClientConnections=20" $VIRTUOSO_INI
  sed -i "/^ServerThreads/c\ServerThreads=20" $VIRTUOSO_INI

  sed -i "/^NumberOfBuffers/c\NumberOfBuffers=170000" $VIRTUOSO_INI
  sed -i "/^MaxDirtyBuffers/c\MaxDirtyBuffers=130000" $VIRTUOSO_INI

  sed -i '/^DirsAllowed/ s/$/, \/tmp, \/var\/local/' $VIRTUOSO_INI
  
  sed -i "/^ResultSetMaxRows/c\ResultSetMaxRows=1000000" $VIRTUOSO_INI
  sed -i "/^MaxQueryCostEstimationTime/c\MaxQueryCostEstimationTime=5000; in seconds" $VIRTUOSO_INI
  sed -i "/^MaxQueryExecutionTime/c\MaxQueryExecutionTime=300; in seconds" $VIRTUOSO_INI
  sed -i "/^DynamicLocal/c\DynamicLocal=1" $VIRTUOSO_INI

  sed -i  's/\/var\/local\/virtuoso\/var\/lib\/virtuoso\/db\//\/var\/local\/virtuoso\/var\/lib\/virtuoso\/production\//g' $VIRTUOSO_INI

  # copy data files
  chown -R scoreboard.scoreboard /var/local/virtuoso
  
  sudo cp /vagrant/etc/virtuoso7 /etc/init.d
  sudo chkconfig --add virtuoso7
  sudo chkconfig --level 2345 virtuoso7 on

  popd
}
