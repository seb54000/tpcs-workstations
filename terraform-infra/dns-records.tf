
resource "cloudflare_dns_record" "student_vm" {
  count   = var.vm_number
  zone_id = var.cloudflare_zone_id
  name    = "${format("vm%02s", count.index)}.${var.dns_subdomain}"
  type    = "A"
  ttl     = 60
  content = aws_instance.student_vm[count.index].public_ip
}

locals {
  student_vm_names    = sort(keys(try(jsondecode(var.users_list), {})))
  eks_cluster_indexes = range(var.eks_cluster_count)
  student_eks_wildcard_records = {
    for pair in setproduct(local.student_vm_names, local.eks_cluster_indexes) :
    "${pair[0]}-eks${format("%02d", pair[1])}" => {
      student       = pair[0]
      cluster_index = pair[1]
    }
  }
  eks_cluster_wildcard_records = {
    for cluster_index in local.eks_cluster_indexes :
    format("eks%02d", cluster_index) => {
      cluster_index = cluster_index
    }
  }
}

resource "cloudflare_dns_record" "student_eks_ingress_wildcard" {
  for_each = var.eks_cluster_count > 0 ? local.student_eks_wildcard_records : {}

  zone_id = var.cloudflare_zone_id
  name    = "*.${each.value.student}-svc.eks${format("%02d", each.value.cluster_index)}.${var.dns_subdomain}"
  type    = "A"
  ttl     = 60
  content = aws_eip.eks_ingress_nlb[each.value.cluster_index].public_ip
}

resource "cloudflare_dns_record" "eks_cluster_ingress_wildcard" {
  for_each = var.eks_cluster_count > 0 ? local.eks_cluster_wildcard_records : {}

  zone_id = var.cloudflare_zone_id
  name    = "*.eks${format("%02d", each.value.cluster_index)}.${var.dns_subdomain}"
  type    = "A"
  ttl     = 60
  content = aws_eip.eks_ingress_nlb[each.value.cluster_index].public_ip
}

resource "cloudflare_dns_record" "docs" {
  count   = var.AccessDocs_vm_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "docs.${var.dns_subdomain}"
  type    = "A"
  ttl     = 60
  content = aws_instance.access[0].public_ip
}

resource "cloudflare_dns_record" "www_docs" {
  count   = var.AccessDocs_vm_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "www.docs.${var.dns_subdomain}"
  type    = "A"
  ttl     = 60
  content = aws_instance.access[0].public_ip
}

resource "cloudflare_dns_record" "access" {
  count   = var.AccessDocs_vm_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "access.${var.dns_subdomain}"
  type    = "A"
  ttl     = 60
  content = aws_instance.access[0].public_ip
}

resource "cloudflare_dns_record" "www_access" {
  count   = var.AccessDocs_vm_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "www.access.${var.dns_subdomain}"
  type    = "A"
  ttl     = 60
  content = aws_instance.access[0].public_ip
}

resource "cloudflare_dns_record" "monitoring" {
  count   = var.AccessDocs_vm_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "monitoring.${var.dns_subdomain}"
  type    = "A"
  ttl     = 60
  content = aws_instance.access[0].public_ip
}

resource "cloudflare_dns_record" "www_monitoring" {
  count   = var.AccessDocs_vm_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "www.monitoring.${var.dns_subdomain}"
  type    = "A"
  ttl     = 60
  content = aws_instance.access[0].public_ip
}

resource "cloudflare_dns_record" "prometheus" {
  count   = var.AccessDocs_vm_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "prometheus.${var.dns_subdomain}"
  type    = "A"
  ttl     = 60
  content = aws_instance.access[0].public_ip
}

resource "cloudflare_dns_record" "www_prometheus" {
  count   = var.AccessDocs_vm_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "www.prometheus.${var.dns_subdomain}"
  type    = "A"
  ttl     = 60
  content = aws_instance.access[0].public_ip
}

resource "cloudflare_dns_record" "grafana" {
  count   = var.AccessDocs_vm_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "grafana.${var.dns_subdomain}"
  type    = "A"
  ttl     = 60
  content = aws_instance.access[0].public_ip
}

resource "cloudflare_dns_record" "www_grafana" {
  count   = var.AccessDocs_vm_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "www.grafana.${var.dns_subdomain}"
  type    = "A"
  ttl     = 60
  content = aws_instance.access[0].public_ip
}



# resource "cloudflare_dns_record" "test" {
#   zone_id = var.cloudflare_zone_id
#   name = "test.${var.dns_subdomain}"
#   type = "A"
#   ttl       = 60
#   content    = "8.8.8.8"

#   lifecycle {
#     ignore_changes = [
#       comment,
#       settings,
#       data
#     ]
#   }
# }
