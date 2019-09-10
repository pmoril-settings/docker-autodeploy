#!/bin/sh

function populateFstab() {
	sudo mkdir /mnt/DATOS
	sudo mkdir /mnt/DATOS1
	sudo mkdir /mnt/SSD
	sudo sed -i '$a \
UUID=68cb4258-c2b8-4c66-84c4-d7a71c86c3c9 /mnt/DATOS    ext4 defaults 0 0\
UUID=abce8dd5-ff05-474d-ba08-8d5524ce587d /mnt/DATOS1   ext4 defaults 0 0\
UUID=20a12e3e-df84-4438-85c7-88b6082dd654 /mnt/SSD      ext4 defaults 0 0' /etc/fstab
}

function installDocker() {
	sudo apt-get update
	sudo apt-get install -y \
          apt-transport-https \
          ca-certificates \
          curl \
          gnupg-agent \
          software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository \
          "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) \
          stable"
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io
        sudo usermod -aG docker $USER
}

function installKubectl() {
	curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl
	sudo chmod +x ./kubectl
	sudo mv ./kubectl /usr/local/bin/kubectl
}

function installMinikube() {
	sudo apt install -y libvirt-clients libvirt-daemon-system qemu-kvm \
  	  && sudo usermod -a -G libvirt $(whoami) \
  	  && newgrp libvirt
	curl -LO https://storage.googleapis.com/minikube/releases/latest/docker-machine-driver-kvm2 \
	   && sudo install -y docker-machine-driver-kvm2 /usr/local/bin/
	curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 \
	  && sudo install -y minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64
	minikube config set vm-driver kvm2
}

function installSamba() {
	sudo apt update
        sudo apt install -y samba
        sudo sed -i '$a \
[NUC]\
  follow symlinks = yes\
  wide links = yes\
  comment = Samba on Ubuntu\
  path = /mnt/DATOS\
  read only = no\
  browsable = yes' /etc/samba/smb.conf
	sudo systemctl restart nmbd
}

function installZSH() {
	sudo apt install -y git zsh
	sudo rsync -a /opt/docker/compose/scripts/init-files/.oh-my-zsh ~
	sudo rsync -a /opt/docker/compose/scripts/init-files/.zshrc ~
        sudo rsync -a /opt/docker/compose/scripts/init-files/.p10k.zsh ~
        sudo rsync -a /opt/docker/compose/scripts/init-files/.zsh_history ~
	sudo chsh -s $(which zsh)
	source ~/.zshrc
}

echo 'Initial script running...'
echo 'Populating fstab and mounting drives'
echo -ne '# (10%)\r'
populateFstab && sudo mount -a
echo -ne '## (20%)\r'
echo 'Installing last Docker-CE version'
installDocker
echo -ne '### (30%)\r'
echo 'Installing Samba'
echo -ne '#### (40%)\r'
installSamba
echo -ne '###### (50%)\r'
echo -ne 'Installing kubectl'
installKubectl
echo -ne '####### (60%)\r'
echo 'Installing minikube'
installMinikube
echo -ne '######## (70%)\r'
echo 'Copy docker entire cluster to new installation'
sudo mkdir /opt/docker
sudo rsync -a --progress /mnt/SSD/opt/NVME/compose /opt/docker
echo -ne '######### (80%)\r'
echo 'Deploying docker-compose.yml'
sh /opt/docker/compose/scripts/docker-update.sh
echo -ne '##### (90%)\r'
echo 'Installing ZSH and OH MY ZSH'
installZSH
echo -ne '########## (100%)\r'
echo 'Done!'
echo 'Samba user need to be created, use sudo smbpasswd -a USER'
echo 'Crontab needs to be updated, see crontab-entries file'
