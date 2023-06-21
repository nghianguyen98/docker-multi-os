#!/bin/bash
# Check the operating system
OS=$(uname -s)

# Function to install Docker on CentOS
install_docker_centos() {
  sudo yum update -y
  sudo yum install -y yum-utils device-mapper-persistent-data lvm2
  sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  sudo yum install -y docker-ce docker-ce-cli containerd.io
  sudo systemctl start docker
  sudo systemctl enable docker
  sudo usermod -aG docker ${USER}
}

# Function to install Docker on Ubuntu
install_docker_ubuntu() {
  sudo apt-get update
  sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io
  sudo systemctl start docker
  sudo systemctl enable docker
  sudo usermod -aG docker ${USER}
}

# Function to install Docker on macOS
install_docker_macos() {
  brew install docker
}

# Function to install Docker Compose
install_docker_compose() {
  sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/bin/docker-compose
  sudo chmod +x /usr/bin/docker-compose
}

# Check the operating system and install Docker accordingly
if [ "$OS" == "Linux" ]; then
  if [ -f /etc/os-release ]; then
    source /etc/os-release
    if [ "$ID" == "centos" ]; then
      install_docker_centos
    elif [ "$ID" == "ubuntu" ]; then
      install_docker_ubuntu
    fi
  fi
elif [ "$OS" == "Darwin" ]; then
  install_docker_macos
else
  echo "Unsupported operating system: $OS"
  exit 1
fi

# Install Docker Compose
install_docker_compose

# Verify Docker installation
docker_version=$(docker --version)
echo "Docker version: $docker_version"

# Verify Docker Compose installation
docker_compose_version=$(docker-compose --version)
echo "Docker Compose version: $docker_compose_version"


echo "Docker and Docker Compose have been installed successfully."


