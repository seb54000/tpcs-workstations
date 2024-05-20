
resource "ovh_domain_zone_record" "student_vm" {
  count   = var.vm_number
  zone      = "multiseb.com"
  subdomain = "${format("vm%02s.tpcs", count.index)}"
  fieldtype = "A"
  ttl       = 60
  target    = aws_instance.student_vm[count.index].public_ip
}

resource "ovh_domain_zone_record" "kube_node_vm" {
  count = var.kube_multi_node == true ? var.vm_number : 0
  zone      = "multiseb.com"
  subdomain = "${format("knode%02s.tpcs", count.index)}"
  fieldtype = "A"
  ttl       = 60
  target    = aws_instance.kube_node_vm[count.index].public_ip
}

resource "ovh_domain_zone_record" "docs" {
  count = "${var.AccessDocs_vm_enabled ? 1 : 0}"
  zone      = "multiseb.com"
  subdomain = "docs.tpcs"
  fieldtype = "A"
  ttl       = 60
  target    = aws_instance.access[0].public_ip
}

resource "ovh_domain_zone_record" "www_docs" {
  count = "${var.AccessDocs_vm_enabled ? 1 : 0}"
  zone      = "multiseb.com"
  subdomain = "www.docs.tpcs"
  fieldtype = "A"
  ttl       = 60
  target    = aws_instance.access[0].public_ip
}

resource "ovh_domain_zone_record" "access" {
  count = "${var.AccessDocs_vm_enabled ? 1 : 0}"
  zone      = "multiseb.com"
  subdomain = "access.tpcs"
  fieldtype = "A"
  ttl       = 60
  target    = aws_instance.access[0].public_ip
}

resource "ovh_domain_zone_record" "www_access" {
  count = "${var.AccessDocs_vm_enabled ? 1 : 0}"
  zone      = "multiseb.com"
  subdomain = "www.access.tpcs"
  fieldtype = "A"
  ttl       = 60
  target    = aws_instance.access[0].public_ip
}