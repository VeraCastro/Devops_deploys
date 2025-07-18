Vagrant.configure("2") do |config|
  config.vm.box = "generic/rocky8"
  config.vm.hostname = "phpmyfaq"    
  config.vm.network "forwarded_port", guest: 80, host: 8888
  config.vm.provider "virtualbox" do |vb|
    vb.memory = "2048"
    vb.cpus = 2
    vb.name = "rocky8-phpmyfaq"
  end

  # Asegura que el script se ejecuta con privilegios de root
  config.vm.provision "shell", path: "deploy.sh", privileged: true 
end
