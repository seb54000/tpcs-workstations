
resource "aws_key_pair" "tpcs_key" {
  key_name   = "tpcs_key"
  public_key = file("key.pub")
}

# We sometime use double $$ like in $${AZ::-1} - this is only because we are in template_file and theses are note TF vars
# https://discuss.hashicorp.com/t/extra-characters-after-interpolation-expression/29726

data "cloudinit_config" "student" {
  count = var.vm_number

  gzip          = true
  base64_encode = true

  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"

    content = templatefile(
      "cloudinit/cloud-config.yaml.tftpl",
      {
        hostname_new = "${format("vm%02s", count.index)}"
        users_list   = ["${format("vm%02s", count.index)}"]
        key_pub      = file("key.pub")
      }
    )
  }
}


resource "aws_instance" "student_vm" {
  count                  = var.vm_number
  ami                    = "ami-01d21b7be69801c2f" # eu-west-3 : Ubuntu 22.04 LTS Jammy jellifish -- https://cloud-images.ubuntu.com/locator/ec2/
  instance_type          = var.student_vm_flavor
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.secgroup.id]
  key_name               = aws_key_pair.tpcs_key.key_name
  user_data              = data.cloudinit_config.student[count.index].rendered

  tags = {
    Name  = format("vm%02s", count.index)
    Roles = "student"
    # dns_record = ovh_domain_zone_record.student_vm[*].subdomain
  }

  root_block_device {
    volume_size = 32 # was 16 but not enough for tpkube
    volume_type = "gp3"
    encrypted   = false
  }

  lifecycle {
    ignore_changes = [user_data, instance_type]
  }
}

resource "aws_ec2_instance_state" "state_vm" {
  count       = var.vm_number
  instance_id = aws_instance.student_vm[count.index].id
  state       = "running"
}

output "student_vm" {
  value = [
    {
      "public_ip" = aws_instance.student_vm[*].public_ip
      # "name" = aws_instance.student_vm[*].tags["Name"]
      "dns" = cloudflare_dns_record.student_vm[*].name
    }
  ]
}
