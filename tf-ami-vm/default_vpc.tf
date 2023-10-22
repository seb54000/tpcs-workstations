
# In case default VPC or subnets do not exists, we want to create them (Or problem will occur for TP IAC)
# TODO, problme , we need to create default VPC in eu-west-3 

# https://docs.aws.amazon.com/vpc/latest/userguide/default-vpc.html#create-default-subnet
# aws ec2 create-default-subnet --availability-zone eu-west-3a


# We also need to vrify that route table associated with default VPC has a route for 0.0.0.0 to Internet gateway
# So we also need to verify there is a Internet GW

# TODO
# Myebe we need to use datasource to verify some points and resource to create if not (ofr example for route table ? Or create a new one anyway ??) 
# Default VPC includes a default internet service (I don't know what happens if default VPC is removed ? Do the defult subnets are removed and the default gateway ???)


# resource "aws_default_vpc" "default_vpc" {
#   tags = {
#     Name = "Default VPC"
#   }
# }

# resource "aws_default_subnet" "default_az1" {
#   availability_zone = "eu-west-3a"

#   tags = {
#     Name = "Default subnet for eu-west-3a"
#   }
# }

# resource "aws_default_subnet" "default_az2" {
#   availability_zone = "eu-west-3b"

#   tags = {
#     Name = "Default subnet for eu-west-3b"
#   }
# }

# resource "aws_default_subnet" "default_az3" {
#   availability_zone = "eu-west-3c"

#   tags = {
#     Name = "Default subnet for eu-west-3c"
#   }
# }