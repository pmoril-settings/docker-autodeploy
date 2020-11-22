#!/bin/sh

populateFstab() {
	sudo mkdir /mnt/DATOS1
	sudo sed -i '$a \
UUID=abce8dd5-ff05-474d-ba08-8d5524ce587d /mnt/DATOS1   ext4 defaults 0 0
UUID=4911A636-8A3F-4217-ADE7-76D5D599862B /mnt/DATOS    ext4 defaults 0 0
UUID=25678BCB-46A5-4310-B5C9-A66B905806C0 /mnt/SSD      ext4 defaults 0 0 ' /etc/fstab
}

installDocker() {
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
	# TODO: Discover why this line produces an exit
	# su - $USER
	sudo curl -L "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
	sudo chmod +x /usr/local/bin/docker-compose
}

installKubectl() {
	curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl
	sudo chmod +x ./kubectl
	sudo mv ./kubectl /usr/local/bin/kubectl
}

installMinikube() {
	sudo apt-get install -y libvirt-clients libvirt-daemon-system qemu-kvm
  	sudo usermod -a -G libvirt $(whoami)
	# TODO: Discover why this line produces an exit
  	# newgrp libvirt
	curl -LO https://storage.googleapis.com/minikube/releases/latest/docker-machine-driver-kvm2
	sudo install docker-machine-driver-kvm2 /usr/local/bin/
	curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
	sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64
	minikube config set vm-driver kvm2
}

installSamba() {
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

installZSH() {
	sudo apt install -y git zsh
	sudo rsync -a /opt/docker/compose/scripts/init-files/.oh-my-zsh ~
	sudo rsync -a /opt/docker/compose/scripts/init-files/.zshrc ~
        sudo rsync -a /opt/docker/compose/scripts/init-files/.p10k.zsh ~
        sudo rsync -a /opt/docker/compose/scripts/init-files/.zsh_history ~
}

installPostfix() {
	DEBIAN_FRONTEND=noninteractive sudo apt-get install -y postfix
	cd /etc/postfix
	sudo cp /mnt/DATOS1/Backup/NVME/compose/scripts/init-files/postfix/* .
	sudo postmap /etc/postfix/sasl_passwd
	sudo postmap /etc/postfix/generic
	sudo apt-get install -y mailutils
}

echo 'Initial script running...'
echo 'Populating fstab and mounting drives'
echo '# (10%)\r'
populateFstab && sudo mount -a
echo '## (20%)\r'
echo '### (30%)\r'
echo 'Installing Samba'
echo '#### (40%)\r'
installSamba
echo '###### (50%)\r'
installDocker
echo '####### (60%)\r'
echo '######## (70%)\r'
echo 'Copy docker entire cluster to new installation'
sudo mkdir /opt/docker
sudo rsync -a --progress /mnt/DATOS1/Backup/NVME/compose /opt/docker
echo '######### (80%)\r'
echo 'Deploying docker-compose.yml'
installPostfix
sh /opt/docker/compose/scripts/docker-update.sh
echo '##### (90%)\r'
echo 'Installing ZSH and OH MY ZSH'
installZSH
#echo 'Installing KVM/QEMU'
#sudo apt install -y qemu-kvm virt-manager libguestfs-tools
chsh -s $(which zsh)
echo '########## (100%)\r'
echo 'Done!'
echo '##################### NEXT STEPS ###################'
echo 'Samba user need to be created, use sudo smbpasswd -a USER'
echo 'To let symlinks in samba share, this line needs to be appended to [global] in /etc/samba/smb.conf allow insecure wide links = yes'
echo 'Crontab needs to be updated, see crontab-entries file'
echo 'You need to logout for docker, after execute sh /opt/docker/compose/scripts/docker-update.sh to deploy the cluster'
echo 'Is recommended to restart the system and execute newgrp libvirt if gitlab kubernetes integration is not working'
echo 'Once minikube is deployed and a cluster is created, is mandatory to restart minikube/system to make the endpoint visible to gitlab'

