
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

locals {
  standard_student_ami = "ami-01d21b7be69801c2f" # eu-west-3 : Ubuntu 22.04 LTS Jammy
  student_ami          = var.student_ami_source == "packer" ? var.student_ami_packer_id : local.standard_student_ami
  student_users        = try(jsondecode(var.users_list), {})
  student_deactivated  = [for i in range(var.vm_number) : try(local.student_users[format("vm%02d", i)].deactivated == true, false)]
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
    ignore_changes = [user_data, instance_type]

    precondition {
      condition     = var.student_ami_source != "packer" || can(regex("^ami-[0-9a-f]{8,17}$", var.student_ami_packer_id))
      error_message = "student_ami_source=packer requires a valid student_ami_packer_id; run ./0-build-image.sh first."
    }
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
