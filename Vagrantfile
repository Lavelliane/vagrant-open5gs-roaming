# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
    # Use Ubuntu 22.04 (Jammy) as base
    config.vm.box = "ubuntu/jammy64"
    
    # Configure VM resources based on your machine's capabilities
    config.vm.provider "virtualbox" do |vb|
      vb.memory = 4096  # 4GB RAM
      vb.cpus = 2
    end
  
    # Network configuration
    # Set up port forwarding for MongoDB and other services
    config.vm.network "forwarded_port", guest: 27017, host: 27017  # MongoDB
    config.vm.network "forwarded_port", guest: 38412, host: 38412  # AMF N2 (SCTP)
    config.vm.network "forwarded_port", guest: 2152, host: 2152    # UPF N3 (UDP)
    
    # Create a private network with a specific IP
    config.vm.network "private_network", ip: "192.168.56.10"
  
    # Provision the VM
    config.vm.provision "shell", inline: <<-SHELL
      # Update package lists
      apt-get update
      
      # Install Docker and other dependencies
      apt-get install -y apt-transport-https ca-certificates curl software-properties-common git make gnupg lsb-release
  
      # Add Docker's official GPG key
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
      
      # Set up the Docker repository
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
      
      # Install Docker
      apt-get update --fix-missing
      apt-get install -y docker-ce docker-ce-cli containerd.io
      
      # Install Docker Compose
      curl -L "https://github.com/docker/compose/releases/download/v2.20.3/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
      chmod +x /usr/local/bin/docker-compose
      
      # Install Docker Buildx
      apt-get install -y docker-buildx-plugin
      
      # Add vagrant user to docker group
      usermod -aG docker vagrant
      
      # Clone the repository
      cd /home/vagrant
      git clone https://github.com/roastedbeans/open5gs-roaming.git
      chown -R vagrant:vagrant open5gs-roaming
      
      # Get the VM IP address
      VM_IP=$(ip -4 addr show enp0s8 | grep -oP 'inet \K[\d.]+')
      echo "VM IP Address: $VM_IP"
      
      # Update the .env file
      cd /home/vagrant/open5gs-roaming
      sed -i "s/MONGODB_VERSION=.*/MONGODB_VERSION=4.4/" .env
      sed -i "s/DOCKER_HOST_IP=.*/DOCKER_HOST_IP=$VM_IP/" .env
      
      echo "Setup complete!"
    SHELL
  end