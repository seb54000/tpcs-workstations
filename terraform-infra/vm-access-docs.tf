
locals {
  file_list = var.tp_name == "tpiac" ? var.tpiac_docs_file_list : var.tp_name == "tpkube" ? var.tpkube_docs_file_list : null
}

data "cloudinit_config" "access" {
  count = "${var.AccessDocs_vm_enabled ? 1 : 0}"

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
      "cloudinit/user_data_access_docs.sh",
      {
        guac_tf_file = base64encode(templatefile("guac-config.tf.toupload", { vm_number = var.vm_number, cloudus_user_name = "cloudus", cloudus_user_passwd = var.cloudus_user_passwd} ))
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
        custom_packages = ["nginx" ,"php8.1-fpm"]
        custom_snaps = ["certbot --classic"]
        custom_files = [
          {
            content=base64gzip(file("cloudinit/access_docs_nginx.conf"))
            path="/etc/nginx/sites-enabled/default"
          },
          {
            content=base64gzip(templatefile("cloudinit/gdrive.py",{file_list = local.file_list}))
            path="/var/tmp/gdrive.py"
          },
          # {
          #   content=base64gzip("<?php phpinfo(); ?>")
          #   path="/var/www/html/info.php"
          # },
          {
            content=(var.token_gdrive)
            path="/var/tmp/token.json"
          },
          {
            content=base64gzip(file("cloudinit/vms.php"))
            path="/var/www/html/vms.php"
          },
          {
            content=base64gzip(file("cloudinit/quotas.php"))
            path="/var/www/html/quotas.php"
          },
          {
            content=base64gzip(file("cloudinit/users.json"))
            path="/var/www/html/json/users.json"
          },
          {
            content=base64gzip(templatefile("cloudinit/api_keys.json.tftpl",{access_key = aws_iam_access_key.tpiac, vm_number = var.vm_number}))
            path="/var/www/html/json/api_keys.json"
          },
          {
            content=base64gzip(var.tp_name)
            path="/var/www/html/json/tp_name"
          }
          # ,
          # {
          #   content=base64gzip(templatefile("cloudinit/check_basics.sh.tftpl",{ssh_key = file("${path.module}/key") , vm_number = var.vm_number}))
          #   path="/usr/bin/check_basics"
          # }
        ]
      }
    )
  }
}

resource "aws_instance" "access" {
  count = "${var.AccessDocs_vm_enabled ? 1 : 0}"

  ami             = "ami-01d21b7be69801c2f"   # eu-west-3 : Ubuntu 22.04 LTS Jammy jellifish -- https://cloud-images.ubuntu.com/locator/ec2/
  instance_type = "t2.xlarge" # Guacamole needs RAM
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.secgroup.id]
  key_name      = aws_key_pair.tpcs_key.key_name
  user_data     = data.cloudinit_config.access[0].rendered
  iam_instance_profile = "${aws_iam_instance_profile.access[0].name}"

  tags = {
    Name = "access_docs"
    dns_record = "ovh_domain_zone_record.access[*].subdomain"
    other_name = "guacamole"
  }
}

resource "aws_ec2_instance_state" "access" {
  count = "${var.AccessDocs_vm_enabled ? 1 : 0}"
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


####################
## IAM role management to allow this instance to call EC2 API (to list VMs and other php scripts)
# https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_switch-role-ec2.html
resource "aws_iam_role" "access" {
  count = "${var.AccessDocs_vm_enabled ? 1 : 0}"
  name = "access"

  assume_role_policy = jsonencode(
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Action": "sts:AssumeRole",
          "Principal": {
            "Service": "ec2.amazonaws.com"
          },
          "Effect": "Allow",
          "Sid": ""
        }
      ]
    }
  )

  tags = {
      name = "access-tpcs"
  }
}

resource "aws_iam_instance_profile" "access" {
  count = "${var.AccessDocs_vm_enabled ? 1 : 0}"
  name = "access"
  role = "${aws_iam_role.access[0].name}"
}

resource "aws_iam_policy" "access" {
  count = "${var.AccessDocs_vm_enabled ? 1 : 0}"
  name = "access"

  policy = jsonencode(
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": ["ec2:DescribeTags", "ec2:DescribeInstances", "ec2:DescribeRegions", "ec2:DescribeAccountAttributes", "servicequotas:*", "iam:ListGroupsForUser"],
                "Resource": "*"
            }
            # TOOO add authorization to request IAM informations including AK/SK ?
            #,
            # {
            #     "Effect": "Allow",
            #     "Action": "route53:ChangeResourceRecordSets",
            #     "Resource": "arn:aws:route53:::hostedzone/${data.aws_route53_zone.tpkube.zone_id}"
            # }
        ]
    }
  )
}

resource "aws_iam_policy_attachment" "access" {
  count = "${var.AccessDocs_vm_enabled ? 1 : 0}"
  name       = "access"
  roles      = ["${aws_iam_role.access[0].name}"]
  policy_arn = "${aws_iam_policy.access[0].arn}"
}
