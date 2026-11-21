
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

data "aws_ami_ids" "student_current" {
  count  = var.ami_source == "packer" && var.vm_number > 0 ? 1 : 0
  owners = ["self"]

  filter {
    name   = "name"
    values = ["tpcs-student-tpiac-current"]
  }
  filter {
    name   = "tag:Repository"
    values = ["tpcs-workstations"]
  }
  filter {
    name   = "tag:TPCSImageProfile"
    values = ["student-tpiac"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

locals {
  standard_student_ami     = "ami-01d21b7be69801c2f" # eu-west-3 : Ubuntu 22.04 LTS Jammy
  student_current_ami_ids  = try(data.aws_ami_ids.student_current[0].ids, [])
  student_custom_ami_found = length(local.student_current_ami_ids) == 1
  student_ami              = var.ami_source == "packer" && local.student_custom_ami_found ? local.student_current_ami_ids[0] : local.standard_student_ami
  student_users            = try(jsondecode(var.users_list), {})
  student_deactivated      = [for i in range(var.vm_number) : try(local.student_users[format("vm%02d", i)].deactivated == true, false)]
}

check "student_current_ami" {
  assert {
    condition     = var.ami_source != "packer" || var.vm_number == 0 || local.student_custom_ami_found
    error_message = "No unique current student Packer AMI was found; student VMs will use the standard Ubuntu image."
  }
}


resource "aws_instance" "student_vm" {
  count                  = var.vm_number
  ami                    = local.student_ami
  instance_type          = var.student_vm_flavor
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.secgroup.id]
  key_name               = aws_key_pair.tpcs_key.key_name
  user_data              = data.cloudinit_config.student[count.index].rendered

  tags = merge(
    {
      Name  = format("vm%02s", count.index)
      Roles = "student"
    },
    local.student_deactivated[count.index] ? { Deactivated = "true" } : {}
  )

  root_block_device {
    volume_size = 32 # was 16 but not enough for tpkube
    volume_type = "gp3"
    encrypted   = false
  }

  lifecycle {
    ignore_changes = [user_data, instance_type, ami]
  }
}

resource "aws_ec2_instance_state" "state_vm" {
  count       = var.vm_number
  instance_id = aws_instance.student_vm[count.index].id
  state       = local.student_deactivated[count.index] ? "stopped" : "running"
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
