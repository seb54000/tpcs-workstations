# We sometime use double $$ in templates like in $${AZ::-1} - this is only because we are in template_file and theses are note TF vars
# https://discuss.hashicorp.com/t/extra-characters-after-interpolation-expression/29726

locals {
  file_list = var.tp_name == "tpiac" ? var.tpiac_docs_file_list : var.tp_name == "tpkube" ? var.tpkube_docs_file_list : null
}

data "cloudinit_config" "docs" {
  count = "${var.docs_vm_enabled ? 1 : 0}"

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
    filename     = "docs-cloud-init.sh"
    # docs-cloud-init should be in /var/lib/cloud/instance/scripts
    content_type = "text/x-shellscript"

    content = templatefile(
      "cloudinit/user_data_docs.sh",
      {}
    )
  }

  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"

    content = templatefile(
      "cloudinit/cloud-config.yaml.tftpl",
      {
        cloudus_user_passwd = var.cloudus_user_passwd
        hostname_new = "docs"
        key_pub = file("key.pub")
        custom_packages = ["nginx" ,"php8.1-fpm"]
        custom_files = [
          {
            content=base64encode(file("cloudinit/docs_nginx.conf"))
            path="/etc/nginx/sites-enabled/default"
          },
          {
            content=base64encode(templatefile("cloudinit/gdrive.py",{file_list = local.file_list}))
            path="/var/tmp/gdrive.py"
          },
          # {
          #   content=base64encode("<?php phpinfo(); ?>")
          #   path="/var/www/html/info.php"
          # },
          {
            content=(var.token_gdrive)
            path="/var/tmp/token.json"
          },
          {
            content=base64encode(file("cloudinit/user_data_docs.sh"))
            path="/var/tmp/cloud-init.sh"
          },
          {
            content=base64encode(file("cloudinit/vms.php"))
            path="/var/www/html/vms.php"
          },
          {
            content=base64encode(file("cloudinit/quotas.php"))
            path="/var/www/html/quotas.php"
          },
          {
            content=base64encode(file("cloudinit/users.json"))
            path="/var/www/html/json/users.json"
          },
          {
            content=base64encode(templatefile("cloudinit/api_keys.json.tftpl",{access_key = aws_iam_access_key.tpiac, vm_number = var.vm_number}))
            path="/var/www/html/json/api_keys.json"
          },
          {
            content=base64encode(var.tp_name)
            path="/var/www/html/json/tp_name"
          }
          # ,
          # {
          #   content=base64encode(templatefile("cloudinit/check_basics.sh.tftpl",{ssh_key = file("${path.module}/key") , vm_number = var.vm_number}))
          #   path="/usr/bin/check_basics"
          # }
        ]
      }
    )
  }
}

# Cloud-init files on the target VM are in :
# /var/lib/cloud/instances/i-09e5a890172e83898/scripts/hello-script.sh

# output "cloud-init-cruft" {
#   value = "${data.cloudinit_config.docs.rendered}"
# }

resource "aws_instance" "docs" {
  count = "${var.docs_vm_enabled ? 1 : 0}"

  ami             = "ami-01d21b7be69801c2f"   # eu-west-3 : Ubuntu 22.04 LTS Jammy jellifish -- https://cloud-images.ubuntu.com/locator/ec2/
  instance_type = "t2.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.secgroup.id]
  iam_instance_profile = "${aws_iam_instance_profile.docs[0].name}"
  key_name      = aws_key_pair.tpcs_key.key_name
  # user_data     = data.cloudinit_config.docs[0].rendered
  user_data_base64     = base64gzip(data.cloudinit_config.docs[0].rendered)

  tags = {
    Name = "docs"
    dns_record = "ovh_domain_zone_record.docs[*].subdomain"
  }

  lifecycle {
    ignore_changes = [user_data]
  }

}

resource "aws_ec2_instance_state" "docs" {
  count = "${var.docs_vm_enabled ? 1 : 0}"

  instance_id = aws_instance.docs[0].id
  state       = "running"
}

output "docs" {
    value = [
    {
    "public_ip" = join("", aws_instance.docs.*.public_ip)
    # "name" = aws_instance.docs[*].tags["Name"]
    "dns" = join("", ovh_domain_zone_record.docs.*.subdomain)
    }
  ]
}


####################
## IAM role management to allow this instance to call EC2 API (to list VMs)

resource "aws_iam_role" "docs" {
  count = "${var.docs_vm_enabled ? 1 : 0}"
  name = "docs"

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
      name = "docs-tpcs"
  }
}

resource "aws_iam_instance_profile" "docs" {
  count = "${var.docs_vm_enabled ? 1 : 0}"
  name = "docs"
  role = "${aws_iam_role.docs[0].name}"
}

resource "aws_iam_policy" "docs" {
  count = "${var.docs_vm_enabled ? 1 : 0}"
  name = "docs"

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

resource "aws_iam_policy_attachment" "docs" {
  count = "${var.docs_vm_enabled ? 1 : 0}"
  name       = "docs"
  roles      = ["${aws_iam_role.docs[0].name}"]
  policy_arn = "${aws_iam_policy.docs[0].arn}"
}
