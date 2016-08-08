#!/usr/bin/env bash

# Simplified installation script for deploying the Digital Agenda Data tool suite
# This scripts only installs Virtuoso


export DAD_HOME=/var/local/scoreboard.install
export VIRTUOSO_HOME=/var/local/virtuoso
export VIRTUOSO_PORT=1111
export VIRTUOSO_HTTP_PORT=8890
export SERVICE_NAME=virtuoso7
export CR_HOME="\/var\/local\/cr"

# for test environment use the variables below
#export VIRTUOSO_HOME=/var/local/test-virtuoso
#export VIRTUOSO_PORT=1112
#export VIRTUOSO_HTTP_PORT=8891
#export SERVICE_NAME=virtuoso7-test
#export CR_HOME="\/var\/local\/test-cr"

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

# Prerequisites
yum install -y gcc gmake autoconf automake libtool flex bison gperf gawk m4 make openssl-devel readline-devel wget net-tools
# git clone -b stable/7 git://github.com/openlink/virtuoso-opensource.git virtuoso-src
# download and compile virtuoso 7.2.4.2
wget -nv -N -P $DAD_HOME/bin/ https://github.com/openlink/virtuoso-opensource/releases/download/v7.2.4.2/virtuoso-opensource-7.2.4.2.tar.gz

cd $DAD_HOME/..
tar xzf $DAD_HOME/bin/virtuoso-opensource-7.2.4.2.tar.gz --no-same-owner
cd virtuoso-opensource-7.2.4.2
./autogen.sh
./configure --prefix=$VIRTUOSO_HOME --with-readline --enable-fct-vad --enable-conductor-vad --with-port=$VIRTUOSO_PORT
make
mkdir $VIRTUOSO_HOME
make install

# update config files and data files
VIRTUOSO_INI=$VIRTUOSO_HOME/var/lib/virtuoso/db/virtuoso.ini
cp $VIRTUOSO_INI $VIRTUOSO_INI.original
sed -i "/HTTPLogFile/c\HTTPLogFile\=/var\/local\/virtuoso\/virtuoso.log" $VIRTUOSO_INI
sed -i "/^MaxClientConnections/c\MaxClientConnections=4" $VIRTUOSO_INI
sed -i "/^ServerThreads/c\ServerThreads=4" $VIRTUOSO_INI
sed -i "/^NumberOfBuffers/c\NumberOfBuffers=170000" $VIRTUOSO_INI
sed -i "/^MaxDirtyBuffers/c\MaxDirtyBuffers=130000" $VIRTUOSO_INI
sed -i '/^DirsAllowed/ s/$/, \/tmp, \/var\/www\/html\/download\/, \/var\/local\/cr\/apphome\/tmp, \/var\/local\/cr\/apphome\/staging/' $VIRTUOSO_INI
sed -i "/^ResultSetMaxRows/c\ResultSetMaxRows=1000000" $VIRTUOSO_INI
sed -i "/^MaxQueryCostEstimationTime/c\MaxQueryCostEstimationTime=5000; in seconds" $VIRTUOSO_INI
sed -i "/^MaxQueryExecutionTime/c\MaxQueryExecutionTime=300; in seconds" $VIRTUOSO_INI
sed -i "/^DynamicLocal/c\DynamicLocal=1" $VIRTUOSO_INI

sed -i "s/1111/$VIRTUOSO_PORT/g" $VIRTUOSO_INI
sed -i "s/8890/$VIRTUOSO_HTTP_PORT/g" $VIRTUOSO_INI

# do not load the default plugins
sed -i 's/^\(Load[1-3]\)/;\1/g' $VIRTUOSO_INI
chown -R $user.$user $VIRTUOSO_HOME
# Put virtuoso bin into PATH.
echo "export PATH=$PATH:$VIRTUOSO_HOME/bin" | tee --append /home/$user/.bashrc > /dev/null
cp $DAD_HOME/etc/$SERVICE_NAME.service /etc/systemd/system/
cp $DAD_HOME/etc/virtuoso.env /root/$SERVICE_NAME.env
cp $DAD_HOME/misc/shutdown.sql $VIRTUOSO_HOME/var/lib/virtuoso/db/
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME

# Optionally, load some data
#echo "Importing the DAD graphs..."
#rm -rf /tmp/prod_export_graph
#wget -nv -N -P /tmp/ http://85.9.22.69/download/vagrant/prod_export_graph.tgz
#tar xzf /tmp/prod_export_graph.tgz -C /tmp --no-same-owner
#$VIRTUOSO_HOME/bin/isql $VIRTUOSO_PORT dba dba $DAD_HOME/misc/import_prod.sql


###### END INSTALL VIRTUOSO #################
