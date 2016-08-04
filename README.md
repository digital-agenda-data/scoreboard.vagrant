## Prerequisites

1. VirtualBox (tested with 5.x)
2. Vagrant (tested with 1.7.4)

## Box
The CentOS 7.2 box is created using packer: https://github.com/cristiroma/centos-7-minimal

``vagrant box add cristiroma/centos-7-minimal``

* Install vagrant and plugins
``vagrant plugin install vagrant-vbguest``
``vagrant plugin install vagrant-cachier``

* Start the virtual machine: ``vagrant up``

* Connect to local box using ssh:
``vagrant ssh`` or ``ssh -o StrictHostKeyChecking=no -i .vagrant/machines/default/virtualbox/private_key -p 2222 vagrant@localhost``


## Local settings (on host machine)

* If the host machine runs windows, set `git config --global core.autocrlf false` unless you know how autcrlf works.
  Alternatively, after checkout, run dos2unix for all script and configuration files that will be copied or executed
  inside the virtual machine (etc/*, bootstrap.sh, post-mount.sh).

* Edit the hosts file and add
    172.28.128.3 semantic.digital-agenda-data.eu digital-agenda-data.eu virtuoso.digital-agenda-data.eu test.digital-agenda-data.eu test-cr.digital-agenda-data.eu test-virtuoso.digital-agenda-data.eu
(where 172.28.128.3 is the IP of the virtual machine)


## Data files

Some binary content is downloaded from the main DAD server (85.9.22.69):
* [plone-storage.tar.gz](http://85.9.22.69/download/vagrant/plone-storage.tar.gz) contains the default Plone settings and content (datasets, documentation, files etc.). The default login is admin/password.
* [plone-storage-test.tar.gz](http://85.9.22.69/download/vagrant/plone-storage-test.tar.gz) same as above, but for test environment (test.digital-agenda-data.eu)

## Troubleshooting
* Plone does not start. Can be caused by pypy errors during buildout, e.g.
```Can't download https://pypi.python.org/packages/source/P/Products.SimpleAttachment/Products.SimpleAttachment-4.4.tar.gz#md5=b067144b5a526b8314e8b5a52e27483e: 500 Internal Server Error```

Solution => Restart buildout
    cd /var/local/plone
    sudo su scoreboard
    bin/buildout

* /vagrant is not mounted. Can be caused by VirtualBox guest additions. Try setting config.vbguest.auto_update to true in Vagrant file or alternatively, run `vagrant vbguest` command.

* yum update takes a _very_ long time. Sometimes this can be caused by unavailable local mirrors. Eventually it works (after 20-30 minutes), or you can kill the process and retry.

## TODO
* Don't disable selinux
* Install fonts

## Various useful things

# Compile and run virtuoso with debug
    CFLAGS="-O -m64 -g"
    export CFLAGS
    ./configure --prefix=$VIRTUOSO_HOME --with-readline --program-transform-name="s/isql/isql-v/" --enable-fct-vad --enable-rdfmappers-vad --enable-conductor-vad --enable-maintainer-mode --with-debug --with-port=1114
    make
    make install

# Enable core dump
    ulimit -c unlimited

# Run Virtuoso in foreground with debug
    virtuoso-t +debug -f
