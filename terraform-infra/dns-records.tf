
resource "ovh_domain_zone_record" "student_vm" {
  count   = var.vm_number
  zone      = "multiseb.com"
  subdomain = "${format("vm%02s.tpcs", count.index)}"
  fieldtype = "A"
  ttl       = 60
  target    = aws_instance.student_vm[count.index].public_ip
}

resource "ovh_domain_zone_record" "docs" {
  count = "${var.docs_vm_enabled ? 1 : 0}"
  zone      = "multiseb.com"
  subdomain = "docs.tpcs"
  fieldtype = "A"
  ttl       = 60
  target    = aws_instance.docs[0].public_ip
}

resource "ovh_domain_zone_record" "access" {
  count = "${var.access_vm_enabled ? 1 : 0}"
  zone      = "multiseb.com"
  subdomain = "access.tpcs"
  fieldtype = "A"
  ttl       = 60
  target    = aws_instance.access[0].public_ip
}