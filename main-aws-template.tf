
# Configure the AWS Provider

provider "aws" {
  region     = "us-east-1"
  access_key = ""
  secret_key = ""
}




#Creating the VPC
resource "aws_vpc" "prod-vpc" {
    cidr_block = "10.0.0.0/16"
    tags = {
        Name = "production"
    }
}

#Creating the VPC's gateway
resource "aws_internet_gateway" "gw" {
    vpc_id = aws_vpc.prod-vpc.id

    tags = {
        Name = "prod-gw"
    }
}


#Creating the VPC's route table
resource "aws_route_table" "prod-route-table" {
    vpc_id = aws_vpc.prod-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id             = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "prod-rt"
  }
}

#Creating the VPC's subnet
resource "aws_subnet" "subnet-1" {
  vpc_id     = aws_vpc.prod-vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "prod-subnet"
  }
}

#Route table association
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.prod-route-table.id
}

#Security Group to allow ports 22, 80, & 443
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow Web Inbound traffic"
  vpc_id      = aws_vpc.prod-vpc.id

#From port
  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
#To port, -1 meeans "any protocol"
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

#Network interface creation
resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]


}

#Assign an AWS elastic ip -- create the gateway first!!  Terraform will give an error if none.
#TIP:  "depends_on" needs to be specified as a list, hence the [].
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.gw]
}

 output "server_public_ip" {
   value = aws_eip.one.public_ip
}

#TIP: choosing an AZ will prevent AWS from autoselecting one for you.  Your items will appear in different AZ (data centers) and may not communicate
resource "aws_instance" "web-server-instance" {
    ami = "ami-04505e74c0741db8d"
    instance_type = "t2.micro"
    availability_zone = "us-east-1a"
    key_name = "terraform-main"

    network_interface {
      device_index         = 0
      network_interface_id = aws_network_interface.web-server-nic.id
    }

    #Installing the apache server
    #TIP: EOF tags allows Bash scripting.  So "<<-EOF"(beginning) & "EOF" (end)
    user_data = <<-EOF
                    #!/bin/bash
                    sudo apt update -y
                    sudo apt install apache2 -y
                    sudo systemctl start apache2
                    sudo bash -c 'echo your very first web server > /var/www/html/index.html'
                    EOF
    tags = {
        Name = "web-server"
    }
}

 output "server_private_ip" {
   value = aws_instance.web-server-instance.private_ip

 }

 output "server_id" {
   value = aws_instance.web-server-instance.id
 }
