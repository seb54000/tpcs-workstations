

# We sometime use double $$ like in $${AZ::-1} - this is only because we are in template_file and theses are note TF vars
# https://discuss.hashicorp.com/t/extra-characters-after-interpolation-expression/29726
data "template_file" "docs" {
      ## TODO manage if / else to have different user_data file (or part) for kube and iac and serverinfo ?? 
      template = file("user_data_tpiac.sh")
      vars={
        cloudus_user_passwd = var.cloudus_user_passwd
        # iac_user_passwd = var.iac_user_passwd
        # ec2_user_passwd = var.ec2_user_passwd
        hostname_new = "docs"
        access_key = ""
        secret_key = ""
        console_user_name = ""
        console_passwd = ""
      }
}

resource "aws_instance" "docs" {
  ami             = "ami-01d21b7be69801c2f"   # eu-west-3 : Ubuntu 22.04 LTS Jammy jellifish -- https://cloud-images.ubuntu.com/locator/ec2/
  instance_type = "t2.medium"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.secgroup.id]
  key_name      = aws_key_pair.tpcs_key.key_name
  user_data     = data.template_file.docs.rendered

  tags = {
    Name = "docs"
    dns_record = "ovh_domain_zone_record.docs[*].subdomain"
  }
}

resource "aws_ec2_instance_state" "docs" {
  instance_id = aws_instance.docs.id
  state       = "running"
}

output "docs" {
    value = [
    {
    "public_ip" = aws_instance.docs.public_ip
    # "name" = aws_instance.docs[*].tags["Name"]
    "dns" = ovh_domain_zone_record.docs.subdomain
    }
  ]
}
