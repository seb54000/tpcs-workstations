

# We sometime use double $$ like in $${AZ::-1} - this is only because we are in template_file and theses are note TF vars
# https://discuss.hashicorp.com/t/extra-characters-after-interpolation-expression/29726
data "template_file" "access" {
      count = "${var.access_vm_enabled ? 1 : 0}"

      ## TODO manage if / else to have different user_data file (or part) for kube and iac and serverinfo ?? 
      template = file("user_data_guacamole.sh")
      vars={
        cloudus_user_passwd = var.cloudus_user_passwd
        # iac_user_passwd = var.iac_user_passwd
        # ec2_user_passwd = var.ec2_user_passwd
        hostname_new = "access"
        access_key = ""
        secret_key = ""
        console_user_name = ""
        console_passwd = ""

        guac_tf_file = base64encode(templatefile("guac-config.tf.toupload", { vm_number = var.vm_number, cloudus_user_passwd = var.cloudus_user_passwd} ))
      }
}

resource "aws_instance" "access" {
  count = "${var.access_vm_enabled ? 1 : 0}"

  ami             = "ami-01d21b7be69801c2f"   # eu-west-3 : Ubuntu 22.04 LTS Jammy jellifish -- https://cloud-images.ubuntu.com/locator/ec2/
  instance_type = "t2.medium"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.secgroup.id]
  key_name      = aws_key_pair.tpcs_key.key_name
  user_data     = data.template_file.access[0].rendered

  tags = {
    Name = "access"
    dns_record = "ovh_domain_zone_record.access[*].subdomain"
    other_name = "guacamole"
  }
}

resource "aws_ec2_instance_state" "access" {
  count = "${var.access_vm_enabled ? 1 : 0}"
  instance_id = aws_instance.access[0].id
  state       = "running"
}

output "access" {
    value = [
    {
    "public_ip" = join("", aws_instance.access.*.public_ip)
    # "name" = aws_instance.access[*].tags["Name"]
    "dns" = join("", ovh_domain_zone_record.access.*.subdomain)
    }
  ]
}
