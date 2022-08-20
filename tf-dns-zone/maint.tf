resource "aws_route53_zone" "tpkube" {
  name = "tpkube.multiseb.com"
}

output "tpkube_zone_ns" {
  value = aws_route53_zone.tpkube.name_servers
}