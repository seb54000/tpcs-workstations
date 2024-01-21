

# We sometime use double $$ like in $${AZ::-1} - this is only because we are in template_file and theses are note TF vars
# https://discuss.hashicorp.com/t/extra-characters-after-interpolation-expression/29726
data "template_file" "docs" {
      count = "${var.docs_vm_enabled ? 1 : 0}"

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

data "cloudinit_config" "docs" {
  count = "${var.docs_vm_enabled ? 1 : 0}"

  gzip          = false
  base64_encode = false

  part {
    filename     = "hello-script.sh"
    # hello-script should be in /var/lib/cloud/instance/scripts
    content_type = "text/x-shellscript"

    content = templatefile(
      "cloudinit/user_data_docs.sh",
      {
        cloudus_user_passwd = var.cloudus_user_passwd
        hostname_new = "docs"
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
        hostname_new = "docs"
        key_pub = file("key.pub")
        custom_packages = ["nginx" ,"php8.1-fpm"]
        custom_files = [
          {
            content=base64encode(file("cloudinit/docs_nginx.conf"))
            path="/etc/nginx/sites-enabled/default"
          },
          {
            content=base64encode(file("cloudinit/gdrive.py"))
            path="/var/tmp/gdrive.py"
          },
          {
            content=base64encode("<?php phpinfo(); ?>")
            path="/var/www/html/info.php"
          },
          {
            content=base64encode("test1")
            path="/var/www/html/test1.html"
          },
          {
            content=base64encode("test2")
            path="/var/www/html/test2.html"
          },
          {
            content=(var.token_gdrive)
            path="/var/tmp/token.json"
          },
          {
            content=base64encode(file("cloudinit/user_data_docs.sh"))
            path="/var/tmp/cloud-init.sh"
          }
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
  user_data     = data.cloudinit_config.docs[0].rendered

  tags = {
    Name = "docs"
    dns_record = "ovh_domain_zone_record.docs[*].subdomain"
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
                "Action": ["ec2:DescribeTags", "ec2:DescribeInstances"],
                "Resource": "*"
            }#,
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
