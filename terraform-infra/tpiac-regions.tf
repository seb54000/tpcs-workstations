# IAM is global: creating student users does not enable their exercise regions.
locals {
  tpiac_assigned_regions = toset([
    for i in range(local.tpiac_enabled ? var.vm_number : 0) :
    var.tpiac_regions_list_for_apikey[i % length(var.tpiac_regions_list_for_apikey)]
  ])
}

data "aws_regions" "tpiac_enabled" {
  count       = length(local.tpiac_assigned_regions) > 0 ? 1 : 0
  all_regions = false

  lifecycle {
    postcondition {
      condition = length(setsubtract(local.tpiac_assigned_regions, self.names)) == 0
      error_message = format(
        "TP IaC: regions unavailable in this AWS account: %s. Enable them in AWS Account > AWS Regions with an administrator, wait for activation to finish, then rerun Terraform. Creating IAM users does not enable regions.",
        join(", ", sort(tolist(setsubtract(local.tpiac_assigned_regions, self.names))))
      )
    }
  }
}
