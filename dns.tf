variable "CLOUDFLARE_GLOBAL_API_TOKEN" {
  description = "Cloudflare Global API key"
  type        = string
  sensitive   = true
}

variable "CLOUDFLARE_EMAIL" {
  description = "Cloudflare Global API token"
  type        = string
  sensitive   = true
}

provider "cloudflare" {
  email   = var.CLOUDFLARE_EMAIL
  api_key = var.CLOUDFLARE_GLOBAL_API_TOKEN
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

resource "local_sensitive_file" "origin_cert" {
  filename = "${path.module}/origin.crt"
  content  = cloudflare_origin_ca_certificate.origin.certificate
}

resource "local_sensitive_file" "origin_key" {
  filename = "${path.module}/origin.key"
  content  = tls_private_key.origin.private_key_pem
}


