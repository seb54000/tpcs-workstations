
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
    filename     = "common-cloud-init.sh"
    # common-cloud-init should be in /var/lib/cloud/instance/scripts
    content_type = "text/x-shellscript"

    content = templatefile(
      "cloudinit/user_data_common.sh",
      {}
    )
  }

  part {
    filename     = "student-cloud-init.sh"
    # student-cloud-init should be in /var/lib/cloud/instance/scripts
    content_type = "text/x-shellscript"

    content = var.tp_name == "tpiac" ? templatefile(
      "cloudinit/user_data_tpiac.sh",
      {
        access_key = aws_iam_access_key.tpiac[count.index].id
        secret_key = aws_iam_access_key.tpiac[count.index].secret
        console_user_name = aws_iam_user.tpiac[count.index].name
        console_passwd = replace(aws_iam_user_login_profile.tpiac[count.index].password, "$", "\\$")
      }
    ) : var.tp_name == "tpkube" ? templatefile(
      "cloudinit/user_data_tpkube.sh",
      {
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
        cloudus_user_passwd = var.cloudus_user_passwd
        hostname_new = "${format("vm%02s", count.index)}"
        key_pub = file("key.pub")
        ## TODO manage if / else to have different user_data file (or part) for kube and iac and serverinfo ?? 
        # TODO TOBE TESTED if custom packages are needed differently for kube and iac
        # template = var.tp_name == "tpiac" ? file("user_data_tpiac.sh") : var.tp_name == "tpkube" ? file("user_data_tpkube.sh") : null
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


resource "aws_instance" "student_vm" {
  count   = var.vm_number
  ami             = "ami-01d21b7be69801c2f"   # eu-west-3 : Ubuntu 22.04 LTS Jammy jellifish -- https://cloud-images.ubuntu.com/locator/ec2/
  instance_type = "t2.medium"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.secgroup.id]
  key_name      = aws_key_pair.tpcs_key.key_name
  user_data     = data.cloudinit_config.student[count.index].rendered

  tags = {
    Name = format("vm%02s", count.index)
    dns_record = "ovh_domain_zone_record.student_vm[*].subdomain"
  }
}

resource "aws_ec2_instance_state" "state_vm" {
  count   = var.vm_number
  instance_id = aws_instance.student_vm[count.index].id
  state       = "running"
}

output "student_vm" {
    value = [
    {
    "public_ip" = aws_instance.student_vm[*].public_ip
    # "name" = aws_instance.student_vm[*].tags["Name"]
    "dns" = ovh_domain_zone_record.student_vm[*].subdomain
    }
  ]
}
