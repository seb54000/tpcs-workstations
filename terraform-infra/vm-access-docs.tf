
locals {
  file_list = var.tp_name == "tpiac" ? var.tpiac_docs_file_list : var.tp_name == "tpkube" ? var.tpkube_docs_file_list : var.tp_name == "tpmon" ? var.tpmon_docs_file_list : null
}

data "cloudinit_config" "access" {
  count = var.AccessDocs_vm_enabled ? 1 : 0

  gzip          = true
  base64_encode = true

  part {
    filename = "common-cloud-init.sh"
    # common-cloud-init should be in /var/lib/cloud/instance/scripts
    content_type = "text/x-shellscript"

    content = templatefile(
      "cloudinit/user_data_common.sh",
      { username = "access" }
    )
  }

  part {
    filename = "access-cloud-init.sh"
    # access-cloud-init should be in /var/lib/cloud/instance/scripts
    content_type = "text/x-shellscript"

    content = templatefile(
      "cloudinit/user_data_access_docs.sh",
      {
        guac_tf_file = base64encode(templatefile(
          "guac-config.tf.toupload",
          { vm_number = var.vm_number, dns_subdomain = var.dns_subdomain }
        )),
        username           = "access",
        tpcsws_branch_name = var.tpcsws_branch_name,
        tpcsws_git_repo = var.tpcsws_git_repo,
        acme_certificates_enable = var.acme_certificates_enable,
        copy_from_gdrive = var.copy_from_gdrive, dns_subdomain = var.dns_subdomain
      }
    )
  }

  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"

    content = templatefile(
      "cloudinit/cloud-config.yaml.tftpl",
      {
        hostname_new = "access"
        key_pub = file("key.pub")
        custom_packages = ["nginx" ,"php8.1-fpm"]
        custom_snaps = ["certbot --classic"]
        custom_files = [
          {
            content=base64gzip(templatefile("cloudinit/access_docs_nginx.conf.tpl", {dns_subdomain = var.dns_subdomain}))
            path="/etc/nginx/sites-enabled/default"
          },
          {
            content = base64gzip(templatefile("cloudinit/gdrive.py", { file_list = local.file_list }))
            path    = "/var/tmp/gdrive.py"
          },
          # {
          #   content=base64gzip("<?php phpinfo(); ?>")
          #   path="/var/www/html/info.php"
          # },
          {
            # Token var content is already in base64 and gzip format
            content=(var.token_gdrive)
            path="/var/tmp/token.json"
          },
          # vms.php too big and will be upload through git clone (or through access to raw file)
          # {
          #   content=base64gzip(file("cloudinit/vms.php"))
          #   path="/root/vms.php"
          # },
          {
            content=base64gzip(templatefile("cloudinit/prometheus_config.tftpl",{vm_number = var.vm_number, dns_subdomain = var.dns_subdomain}))
            path="/var/tmp/prometheus.yml"
          },
          {
            content = base64gzip(templatefile("cloudinit/monitoring_docker_compose.yml", { monitoring_user = var.monitoring_user }))
            path    = "/var/tmp/monitoring_docker_compose.yml"
          },
          {
            content = base64gzip(file("cloudinit/monitoring_grafana_prom_ds.yml"))
            path    = "/var/tmp/grafana-provisioning/datasources/monitoring_grafana_prom_ds.yml"
          },
          {
            content = base64gzip(file("cloudinit/monitoring_grafana_dashboards_conf.yml"))
            path    = "/var/tmp/grafana-provisioning/dashboards/monitoring_grafana_dashboards_conf.yml"
          },
          # Grafana dashboards are too big and will be upload through git clone (or through access to raw file)
          # {
          #   content=base64gzip(file("cloudinit/monitoring_grafana_node_dashboard.json"))
          #   path="/var/tmp/grafana/dashboards/monitoring_grafana_node_dashboard.json"
          # },
          # {
          #   content=base64gzip(file("cloudinit/monitoring_grafana_node_full_dashboard.json"))
          #   path="/var/tmp/grafana/dashboards/monitoring_grafana_node_full_dashboard.json"
          # },
          {
            content = base64gzip(templatefile("cloudinit/users.json.tftpl", { users_list = var.users_list }))
            path    = "/var/www/html/json/users.json"
          },
          {
            content = var.tp_name == "tpiac" ? base64gzip(templatefile("cloudinit/api_keys.json.tftpl",{access_key = aws_iam_access_key.tpiac, vm_number = var.vm_number})) : base64gzip("fakecontentwhentp_nameis nottpiac")
            path = "/var/www/html/json/api_keys.json"
          },
          {
            content = base64gzip(var.tp_name)
            path    = "/var/www/html/json/tp_name"
          },
          {
            content = base64gzip(var.dns_subdomain)
            path    = "/var/www/html/json/dns_subdomain"
          }
          # {
          #   content=base64gzip(file("cloudinit/quotas.php"))
          #   path="/var/www/html/quotas.php"
          # },
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
  count = var.AccessDocs_vm_enabled ? 1 : 0

  ami             = "ami-01d21b7be69801c2f"   # eu-west-3 : Ubuntu 22.04 LTS Jammy jellifish -- https://cloud-images.ubuntu.com/locator/ec2/
  instance_type = var.access_docs_flavor
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.secgroup.id]
  key_name               = aws_key_pair.tpcs_key.key_name
  user_data              = data.cloudinit_config.access[0].rendered
  iam_instance_profile   = aws_iam_instance_profile.access[0].name

  root_block_device {
    volume_size = 50
  }

  tags = {
    Name       = "access"
    dns_record = "cloudflare_dns_record.access[*].name"
    other_name = "guacamole"
    roles      = "access;docs;monitoring"
  }

  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "aws_ec2_instance_state" "access" {
  count       = var.AccessDocs_vm_enabled ? 1 : 0
  instance_id = aws_instance.access[0].id
  state       = "running"
}

output "access" {
  value = [
    {
      "public_ip" = join("", aws_instance.access.*.public_ip)
      # "name" = aws_instance.access[*].tags["Name"]
      "dns" = join("", cloudflare_dns_record.access.*.name)
    }
  ]
}


####################
## IAM role management to allow this instance to call EC2 API (to list VMs and other php scripts)
# https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_switch-role-ec2.html
resource "aws_iam_role" "access" {
  count = var.AccessDocs_vm_enabled ? 1 : 0
  name  = "access"

  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Action" : "sts:AssumeRole",
          "Principal" : {
            "Service" : "ec2.amazonaws.com"
          },
          "Effect" : "Allow",
          "Sid" : ""
        }
      ]
    }
  )

  tags = {
    name = "access-tpcs"
  }
}

resource "aws_iam_instance_profile" "access" {
  count = var.AccessDocs_vm_enabled ? 1 : 0
  name  = "access"
  role  = aws_iam_role.access[0].name
}

resource "aws_iam_policy" "access" {
  count = var.AccessDocs_vm_enabled ? 1 : 0
  name  = "access"

  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Action" : ["ec2:DescribeTags", "ec2:DescribeInstances", "ec2:DescribeRegions", "ec2:DescribeAccountAttributes", "servicequotas:*", "iam:ListGroupsForUser",
          "ec2:DescribeVpcs",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeAddresses"],
          "Resource" : "*"
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
  count      = var.AccessDocs_vm_enabled ? 1 : 0
  name       = "access"
  roles      = ["${aws_iam_role.access[0].name}"]
  policy_arn = aws_iam_policy.access[0].arn
}
