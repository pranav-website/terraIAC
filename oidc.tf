data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# provide the OIDC provider for GitHub Actions to allow it to assume roles in AWS
# otherwise AWS doesn't know who GitHub Actions is and won't allow it to assume roles
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
  client_id_list  = ["sts.amazonaws.com"]
}
