
resource "aws_key_pair" "tpcs_key" {
  key_name   = "tpcs_key"
  public_key = "${file("key.pub")}"
}

# We sometime use double $$ like in $${AZ::-1} - this is only because we are in template_file and theses are note TF vars
# https://discuss.hashicorp.com/t/extra-characters-after-interpolation-expression/29726

data "cloudinit_config" "student" {
  count = var.vm_number

  gzip          = true
  base64_encode = true

  part {
    filename = "common-cloud-init.sh"
    # common-cloud-init should be in /var/lib/cloud/instance/scripts
    content_type = "text/x-shellscript"

    content = templatefile(
      "cloudinit/user_data_common.sh",
      {
        username             = "${format("vm%02s", count.index)}"
        count_number_2digits = "${format("%02s", count.index)}"
      }
    )
  }

  part {
    filename = "student-cloud-init.sh"
    # student-cloud-init should be in /var/lib/cloud/instance/scripts
    content_type = "text/x-shellscript"

    content = var.tp_name == "tpiac" ? templatefile(
      "cloudinit/user_data_tpiac.sh",
      {
        access_key           = aws_iam_access_key.tpiac[count.index].id
        secret_key           = aws_iam_access_key.tpiac[count.index].secret
        console_user_name    = aws_iam_user.tpiac[count.index].name
        console_passwd       = replace(aws_iam_user_login_profile.tpiac[count.index].password, "$", "\\$")
        region_for_apikey    = var.tpiac_regions_list_for_apikey[count.index % length(var.tpiac_regions_list_for_apikey)]
        count_number_2digits = "${format("%02s", count.index)}"
        ami_id               = var.ami_for_template_with_regions_list[count.index % length(var.ami_for_template_with_regions_list)]
      }
      ) : var.tp_name == "tpkube" ? templatefile(
      "cloudinit/user_data_tpkube.sh",
      {
        count_number_2digits = "${format("%02s", count.index)}"
        # access_key = aws_iam_access_key.tpiac[count.index].id
        # secret_key = aws_iam_access_key.tpiac[count.index].secret
        # console_user_name = aws_iam_user.tpiac[count.index].name
        # console_passwd = replace(aws_iam_user_login_profile.tpiac[count.index].password, "$", "\\$")
      }
    ) : var.tp_name == "tpmon" ? templatefile(
      "cloudinit/user_data_tpmon.sh",
      {
        count_number_2digits = "${format("%02s", count.index)}"
        # access_key = aws_iam_access_key.tpiac[count.index].id
        # secret_key = aws_iam_access_key.tpiac[count.index].secret
        # console_user_name = aws_iam_user.tpiac[count.index].name
        # console_passwd = replace(aws_iam_user_login_profile.tpiac[count.index].password, "$", "\\$")
      }
    ) : null
  }

  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"

    content = templatefile(
      "cloudinit/cloud-config.yaml.tftpl",
      {
        hostname_new = "${format("vm%02s", count.index)}"
        key_pub = file("key.pub")
        custom_packages = ["xrdp", "xfce4"]
        custom_snaps    = ["microk8s --classic", "kubectl --classic", "k9s", "postman", "insomnia", "helm --classic", "chromium"]
        custom_files = [
          {
            content = base64gzip(file("cloudinit/student_allow_color"))
            path    = "/etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla"
          }
        ]
      }
    )
  }
}


resource "aws_instance" "student_vm" {
  count   = var.vm_number
  ami             = "ami-01d21b7be69801c2f" # eu-west-3 : Ubuntu 22.04 LTS Jammy jellifish -- https://cloud-images.ubuntu.com/locator/ec2/
  instance_type = var.student_vm_flavor
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.secgroup.id]
  key_name               = aws_key_pair.tpcs_key.key_name
  user_data              = data.cloudinit_config.student[count.index].rendered

  tags = {
    Name = format("vm%02s", count.index)
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

#######################################################
## Additional node for kube

data "cloudinit_config" "kube_node" {
  count = var.kube_multi_node == true ? var.vm_number : 0

  gzip          = true
  base64_encode = true

  part {
    filename = "common-cloud-init.sh"
    # common-cloud-init should be in /var/lib/cloud/instance/scripts
    content_type = "text/x-shellscript"

    content = templatefile(
      "cloudinit/user_data_common.sh",
      {
        username             = "${format("vm%02s", count.index)}"
        count_number_2digits = "${format("%02s", count.index)}"
      }
    )
  }
  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"

    content = templatefile(
      "cloudinit/cloud-config.yaml.tftpl",
      {
        hostname_new = "${format("knode%02s", count.index)}"
        key_pub = file("key.pub")
        custom_packages = []
        custom_snaps    = ["microk8s --classic", "kubectl --classic", "k9s", "helm --classic"]
        custom_files = [
          # {
          #   content=base64gzip(file("cloudinit/student_allow_color"))
          #   path="/etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla"
          # }
        ]
      }
    )
  }

  part {
    filename = "student-cloud-init.sh"
    # student-cloud-init should be in /var/lib/cloud/instance/scripts
    content_type = "text/x-shellscript"

    content = templatefile(
      "cloudinit/user_data_tpkube_addnode.sh",
      {
        count_number_2digits = "${format("%02s", count.index)}"
        # access_key = aws_iam_access_key.tpiac[count.index].id
        # secret_key = aws_iam_access_key.tpiac[count.index].secret
        # console_user_name = aws_iam_user.tpiac[count.index].name
        # console_passwd = replace(aws_iam_user_login_profile.tpiac[count.index].password, "$", "\\$")
      }
    )
  }

  # TODO : simplify cloudinit for kube add node with just microk8s (remove all other stuff like xrdp and so on)

}

resource "aws_instance" "kube_node_vm" {
  count = var.kube_multi_node == true ? var.vm_number : 0
  ami             = "ami-01d21b7be69801c2f" # eu-west-3 : Ubuntu 22.04 LTS Jammy jellifish -- https://cloud-images.ubuntu.com/locator/ec2/
  instance_type = var.kube_node_vm_flavor
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.secgroup.id]
  key_name               = aws_key_pair.tpcs_key.key_name
  user_data              = data.cloudinit_config.kube_node[count.index].rendered

  root_block_device {
    volume_size = 16
    volume_type = "gp3"
    encrypted   = false
  }

  tags = {
    Name = format("knode%02s", count.index)
    # dns_record = ovh_domain_zone_record.kube_node_vm[count.index].subdomain
  }

  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "aws_ec2_instance_state" "kube_node_state_vm" {
  count       = var.kube_multi_node == true ? var.vm_number : 0
  instance_id = aws_instance.kube_node_vm[count.index].id
  state       = "running"
}
