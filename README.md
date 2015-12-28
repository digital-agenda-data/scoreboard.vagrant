## Prerequisites

1. VirtualBox (tested with 5.x)
2. Vagrant (tested with 1.7.4)

## Box
The CentOS 7 box is created using packer: https://github.com/cristiroma/centos-7-minimal
``vagrant box add cristiroma/centos-7-minimal``

* Install vagrant and plugins
``vagrant plugin install vagrant-vbguest``
``vagrant plugin install vagrant-cachier``

* Start the virtual machine: ``vagrant up``

* Connect to local box using ssh:
``vagrant ssh`` or ``ssh -o StrictHostKeyChecking=no -i .vagrant/machines/default/virtualbox/private_key -p 2222 vagrant@localhost``

## Local settings (on host machine)

* Edit the hosts file and add
``127.0.0.1    digital-agenda-data.lan test.digital-agenda-data.lan``

## Troubleshooting
* Plone does not start. Can be caused by pypy errors during buildout, e.g.
```Can't download https://pypi.python.org/packages/source/P/Products.SimpleAttachment/Products.SimpleAttachment-4.4.tar.gz#md5=b067144b5a526b8314e8b5a52e27483e: 500 Internal Server Error```
Solution => Restart buildout
    cd /var/local/plone
    sudo su scoreboard
    bin/buildout

## TODO
start memcache
/var/local/plone/parts/memcached/bin/memcached -d -u scoreboard -m 1024 -p 11210 -P /var/local/plone/var/memcached.pid
