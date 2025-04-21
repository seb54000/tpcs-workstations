
resource "cloudflare_dns_record" "student_vm" {
  count   = var.vm_number
  zone_id = var.cloudflare_zone_id
  name    = "${format("vm%02s", count.index)}.${var.dns_subdomain}"
  type    = "A"
  ttl     = 60
  content = aws_instance.student_vm[count.index].public_ip
}

resource "cloudflare_dns_record" "kube_node_vm" {
  count   = var.kube_multi_node == true ? var.vm_number : 0
  zone_id = var.cloudflare_zone_id
  name    = "${format("knode%02s", count.index)}.${var.dns_subdomain}"
  type    = "A"
  ttl     = 60
  content = aws_instance.kube_node_vm[count.index].public_ip
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
