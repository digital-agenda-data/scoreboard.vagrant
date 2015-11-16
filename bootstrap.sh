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
