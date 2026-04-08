variable "CLOUDFLARE_GLOBAL_API_TOKEN" {
  description = "Cloudflare Global API key"
  type        = string
  sensitive   = true
}

# manually entered, variable
variable "CLOUDFLARE_EMAIL" {
  description = "Cloudflare Global API email"
  type        = string
  sensitive   = true
}

variable "CLOUDFLARE_ACCOUNT_ID" {
  description = "Cloudflare Account ID"
  type        = string
  sensitive   = true
}

provider "cloudflare" {
  email   = var.CLOUDFLARE_EMAIL
  api_key = var.CLOUDFLARE_GLOBAL_API_TOKEN
}

# # dynamically grabbed, data
# resource "cloudflare_zone" "main_zone" {
#   account = {
#     id = "var.CLOUDFLARE_ACCOUNT_ID"
#   }
#   name = "pranavdumpa.win"
#   type = "full"
# }

variable "cloudflare_zone_id" {
  type = string
  description = "Cloudflare Zone ID for pranavdumpa.win, can be found in Cloudflare dashboard"
  sensitive = true
}

resource "tls_private_key" "origin" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "origin" {
  private_key_pem = tls_private_key.origin.private_key_pem

  subject {
    common_name = "pranavdumpa.win"
  }

  dns_names = [
    "pranavdumpa.win",
    "www.pranavdumpa.win",
  ]
}

resource "cloudflare_origin_ca_certificate" "origin" {
  csr          = tls_cert_request.origin.cert_request_pem
  hostnames    = ["pranavdumpa.win", "www.pranavdumpa.win"]
  request_type = "origin-rsa"
}

resource "cloudflare_dns_record" "cf_to_ec2_A_record" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  content = aws_instance.web.public_ip
  type    = "A"
  ttl     = 1
  proxied = true
}

resource "cloudflare_dns_record" "www_cf_to_main_cname_record" {
  zone_id = var.cloudflare_zone_id
  name    = "www"
  content = "pranavdumpa.win"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}

output "origin_cert_pem" {
  value     = cloudflare_origin_ca_certificate.origin.certificate
  sensitive = true
}

output "origin_key_pem" {
  value     = tls_private_key.origin.private_key_pem
  sensitive = true
}
