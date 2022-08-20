terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region  = "us-east-1"
}



resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

resource "aws_security_group" "allow_all" {
  name        = "allow_all"
  description = "Allow all inbound/outbound traffic"
  vpc_id      = aws_default_vpc.default.id

  ingress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    tpcentrale = "tpcentrale"
  }
}

resource "aws_key_pair" "google_compute_engine" {
  key_name   = "google_compute_engine"
  public_key = "ssh-key public here"
}

resource "aws_instance" "amitest-instance" {
  # ami           = "ami-090fa75af13c156b4"   # Amazon Linux 2 AMI (HVM) - Kernel 5.10, SSD Volume Type
  ami             = "ami-0728c171aa8e41159"   # Amazon Linux 2 with .NET 6, PowerShell, Mono, and MATE Desktop Environment
  instance_type = "t2.medium"
  vpc_security_group_ids = [aws_security_group.allow_all.id]
  key_name      =   aws_key_pair.google_compute_engine.key_name
  user_data = <<EOF
        #! /bin/bash
        sudo yum update -y
        # https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/add-repositories.html
        #        sudo amazon-linux-extras install -y mate-desktop1.x
        # Add passwd, create user, finalize xrdp config
        echo "*****" | sudo passwd ec2-user --stdin
        sudo useradd cloudus 
        echo "*****" | sudo passwd cloudus --stdin
        sudo usermod -aG wheel cloudus
        sudo openssl req -x509 -sha384 -newkey rsa:3072 -nodes -keyout /etc/xrdp/key.pem -out /etc/xrdp/cert.pem -days 365 -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=www.example.com"
        # install docker
        sudo yum install -y docker
        sudo systemctl enable docker
        sudo systemctl start docker
        sudo usermod -aG docker ec2-user
        sudo usermod -aG docker cloudus
        # Snapd install for microk8s install
        sudo yum install -y https://github.com/albuild/snap/releases/download/v0.1.0/snap-confine-2.36.3-0.amzn2.x86_64.rpm
        sudo yum install -y https://github.com/albuild/snap/releases/download/v0.1.0/snapd-2.36.3-0.amzn2.x86_64.rpm        
        sudo systemctl enable snapd
        sudo systemctl start snapd        
        # kubectl install
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm kubectl      
        # Install Micro k8s
        sudo snap install microk8s --classic --channel=1.24
        sudo usermod -a -G microk8s ec2-user
        sudo chown -f -R ec2-user ~/.kube
        sudo usermod -a -G microk8s cloudus
        sudo chown -f -R cloudus ~/.kube
        microk8s enable dns storage ingress
        sudo cp /var/snap/microk8s/current/credentials/client.config /home/ec2-user/.kube/config
        sudo mkdir -p /home/cloudus/.kube
        sudo chown cloudus:cloudus /home/cloudus/.kube
        sudo cp /var/snap/microk8s/current/credentials/client.config /home/cloudus/.kube/config
        sudo chown cloudus:cloudus /home/cloudus/.kube/config
        # # MiniKube install
        # curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
        # sudo install minikube-linux-amd64 /usr/local/bin/minikube
        # Install Lens
        sudo yum install -y https://api.k8slens.dev/binaries/Lens-6.0.1-latest.20220810.2.x86_64.rpm
        # Install POSTMAN
        sudo snap install postman
        # Install Insomnia (POSTMAN free equivalent)
        sudo snap install insomnia
        # Notify end of user_data
        touch /home/ec2-user/user_data_finished
        # Reboot for xrdp to work again
        sudo reboot
  EOF

  root_block_device {
    volume_size = 20 # in GB
  }

  tags = {
    tpcentrale = "tpcentrale"
  }
}

output "amitest-instance-ip" {
  value = aws_instance.amitest-instance.public_ip
}



# AMITEST_IP=$(terraform output -raw amitest-instance-ip)
# ssh -o StrictHostKeyChecking=no -i ~/.ssh/google_compute_engine -L 33389:localhost:3389 ec2-user@${AMITEST_IP}
# Depuis client XRDP, il faut se connecter à localhost:33389 on peut utiliser au choix le user cloudus ou ec2-user
