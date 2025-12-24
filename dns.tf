variable "CLOUDFLARE_API_TOKEN" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}

provider "cloudflare" {
  api_token = var.CLOUDFLARE_API_TOKEN
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

output "cf_origin_cert" {
  value     = cloudflare_origin_ca_certificate.origin.certificate
  sensitive = true
}

output "cf_origin_key" {
  value     = tls_private_key.origin.private_key_pem
  sensitive = true
}

