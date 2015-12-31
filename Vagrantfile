# -*- mode: ruby -*-
# vi: set ft=ruby :

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure(2) do |config|
  config.vm.box = "cristiroma/centos-7-minimal"

  if Vagrant.has_plugin?("vagrant-cachier")
    config.cache.enable :yum
    config.cache.scope = :machine # use the per machine cache
  end
  if not ARGV.include?('--no-parallel') # when running in parallel,
  end

  # forwarded ports.
  TCP_PORTS_LIST={
    "80"   => 20080, # http
    "443"  => 20443, # https
    "8080" => 28080, # cr prod (tomcat)
    "8081" => 28081, # cr test (tomcat)
    "8082" => 28082, # elda prod (jetty)
    "8890" => 28890, # virtuoso web console
    "1111" => 21111, # virtuoso isql
    "8441" => 28441, # Plone
    "8442" => 28442, # Plone
    "8443" => 28443, # Plone
    "8448" => 28448, # Plone
  }
  TCP_PORTS_LIST.each do |guest, host|
    config.vm.network "forwarded_port", guest: "#{guest}", host: "#{host}", protocol: "tcp"
  end
  config.vm.network "private_network", type: "dhcp"

  config.vm.provider "virtualbox" do |vb|
      vb.name = "VagrantDigitalAgendaData"
      vb.gui = true
      vb.customize ["modifyvm", :id, "--memory", 4096]
      vb.customize ["modifyvm", :id, "--cpuexecutioncap", "50"]
      vb.customize ["modifyvm", :id, "--vram", 64]
      #vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      #vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
      #vb.customize ["modifyvm", :id, "--clipboard", "bidirectional"]
      #vb.customize ["modifyvm", :id, "--draganddrop", "bidirectional"]
  end

  #config.ssh.private_key_path
  #config.ssh.insert_key = "true"
  config.ssh.password = "vagrant"

  config.vm.provision :shell, path: "bootstrap.sh"
  config.vm.provision :shell, path: "post-mount.sh", run: "always", privileged: false
end
