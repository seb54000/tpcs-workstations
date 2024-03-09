resource "aws_vpc" "vpc" {
  cidr_block = "10.1.0.0/16"

  #### this is for internal vpc dns resolution
  enable_dns_support               = true
  enable_dns_hostnames             = true
  assign_generated_ipv6_cidr_block = true

  tags = {
    Name        = "infra-tp-vpc"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name        = "infra-tp"
  }
}

resource "aws_route_table" "internet" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name        = "infra-tp"
  }
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.gw.id
  }
  lifecycle {
    ignore_changes = [tags.Name]
  }
}

resource "aws_subnet" "public_subnet" {
  cidr_block                      = "10.1.1.0/24"
  vpc_id                          = aws_vpc.vpc.id
  map_public_ip_on_launch         = true

  availability_zone = "eu-west-3a"

  tags = {
    Name        = "infra-tp-public"
  }
}

resource "aws_route_table_association" "public_routing_table" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.internet.id
}


resource "aws_eip" "nat_gateway" {
  # domain = "vpc"
  tags = {
    Name        = "infra-tp-natgw"
  }  
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_gateway.id
  subnet_id     = aws_subnet.public_subnet.id
  tags = {
    Name = "infra-tp"
  }
  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.gw]
}

resource "aws_route_table" "nat_gateway" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name        = "infra-tp"
  }
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }
  # route {
  #   ipv6_cidr_block = "::/0"
  #   gateway_id      = aws_nat_gateway.nat_gw.id
  # }
  lifecycle {
    ignore_changes = [tags.Name]
  }
}

# resource "aws_route_table_association" "nat_gateway_routing_table" {
#   subnet_id      = aws_subnet.private_subnet.id
#   route_table_id = aws_route_table.nat_gateway.id
# }
