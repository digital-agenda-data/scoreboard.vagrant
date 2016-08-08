#!/usr/bin/env bash

# Simplified installation script for deploying the Digital Agenda Data tool suite
# This scripts only installs the Plone (the visualisation tool)

export DAD_HOME=/var/local/scoreboard.install
export PLONE_HOME=/var/local/plone
export PLONE_CFG=production.cfg
export INITIAL_DATA_FS=plone-storage.tar.gz
export CRON_EXPORT_COMMAND=export_datasets_prod.sh
export WWW_DIR=/var/www/html
export SUPERVISOR_SERVICE=supervisord

# for test environment use the variables below
#export PLONE_HOME=/var/local/test-plone
#export PLONE_CFG=test.cfg
#export INITIAL_DATA_FS=plone-storage-test.tar.gz
#export CRON_EXPORT_COMMAND=export_datasets_test.sh
#export WWW_DIR=/var/www/test-html
#export SUPERVISOR_SERVICE=supervisord-test


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

#####################
#   INSTALL PLONE   #
#####################

mkdir -p $PLONE_HOME
git clone https://github.com/digital-agenda-data/scoreboard.buildout.git $PLONE_HOME
cd $PLONE_HOME
virtualenv-2.7 .
source bin/activate
pip install setuptools==7.0 zc.buildout==2.2.5
deactivate
ln -s $PLONE_CFG buildout.cfg
bin/buildout

if [ $? -ne 0 ]; then
    echo "Plone buildout failed, run bin/buildout again and then continue"
else
	#get the preconfigured DAD website from the current digital-agenda-data.eu server
	wget -nv -N -P $DAD_HOME/data http://85.9.22.69/download/vagrant/$INITIAL_DATA_FS
	tar -xzvf $DAD_HOME/data/$INITIAL_DATA_FS --directory=$PLONE_HOME/var
	chown -R $user.$user $PLONE_HOME

	# create cron for data export. use export_datasets_test for test environment
	chmod +x $PLONE_HOME/export/*
	line="30 23 * * * /var/local/plone/export/$CRON_EXPORT_COMMAND"
	(crontab -u $user -l; echo "$line" ) | crontab -u $user -

	#configure httpd
	cp $DAD_HOME/etc/scoreboard-prod.conf /etc/httpd/conf.d
	mkdir -p $WWW_DIR/download
	chown apache.$user $WWW_DIR -R
	chmod g+w WWW_DIR -R
	systemctl reload httpd
	cp $DAD_HOME/etc/$SUPERVISOR_SERVICE.service /etc/systemd/system/
	systemctl enable $SUPERVISOR_SERVICE
	systemctl start $SUPERVISOR_SERVICE

	bin/supervisorctl status
fi


###### END INSTALL PLONE #################


# Change ownership for all apps
chown -R $user.$user $DAD_HOME $PLONE_HOME
