


data "cloudinit_config" "access" {
  count = "${var.access_vm_enabled ? 1 : 0}"

  gzip          = true
  base64_encode = true

  part {
    filename     = "common-cloud-init.sh"
    # common-cloud-init should be in /var/lib/cloud/instance/scripts
    content_type = "text/x-shellscript"

    content = templatefile(
      "cloudinit/user_data_common.sh",
      {}
    )
  }

  part {
    filename     = "access-cloud-init.sh"
    # access-cloud-init should be in /var/lib/cloud/instance/scripts
    content_type = "text/x-shellscript"

    content = templatefile(
      "cloudinit/user_data_guacamole.sh",
      {
        guac_tf_file = base64encode(templatefile("guac-config.tf.toupload", { vm_number = var.vm_number, cloudus_user_passwd = var.cloudus_user_passwd} ))
      }
    )
  }

  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"

    content = templatefile(
      "cloudinit/cloud-config.yaml.tftpl",
      {
        cloudus_user_passwd = var.cloudus_user_passwd
        hostname_new = "access"
        key_pub = file("key.pub")
        custom_packages = []
        custom_files = [
          # {
          #   content=base64encode(file("cloudinit/docs_nginx.conf"))
          #   path="/etc/nginx/sites-enabled/default"
          # }
        ]
      }
    )
  }
}

resource "aws_instance" "access" {
  count = "${var.access_vm_enabled ? 1 : 0}"

  ami             = "ami-01d21b7be69801c2f"   # eu-west-3 : Ubuntu 22.04 LTS Jammy jellifish -- https://cloud-images.ubuntu.com/locator/ec2/
  instance_type = "t2.xlarge" # Guacamole needs RAM
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.secgroup.id]
  key_name      = aws_key_pair.tpcs_key.key_name
  user_data     = data.cloudinit_config.access[0].rendered

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
