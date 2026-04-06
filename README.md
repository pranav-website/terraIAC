# terraIAC

Infrastructure-as-code for the current `pranavdumpa.win` origin stack.

This repo was originally motivated by Logan Marchione's "best DevOps project for a beginner" post, but the code here has evolved into a small personal hosting stack built around:

- Terraform for AWS infrastructure and some Cloudflare resources
- GitHub Actions for CI/CD orchestration
- Terraform Cloud for remote state
- Ansible for post-provision host configuration
- Nginx as the reverse proxy in front of an app expected on `localhost:3000`

## What This Repo Actually Manages Today

At a high level, this repo provisions a single EC2 instance in AWS and prepares it to sit behind Cloudflare.

```text
                   GitHub Actions (main branch only)
                               |
                               | OIDC
                               v
                    AWS IAM role: github-terraform
                               |
                               v
Terraform code  --->  AWS us-west-1 default VPC/default subnet
                               |
                               v
                     EC2 t4g.nano ("web-server")
                               |
                    user_data installs nginx
                               |
                               v
                    Nginx terminates origin TLS
                               |
                               v
                     proxy_pass http://localhost:3000
```

The TLS story is intended to look like this:

```text
Browser
  |
  v
Cloudflare edge
  |
  | HTTPS to origin using Cloudflare Origin CA cert
  v
EC2 / nginx
  |
  v
App on localhost:3000
```

Important: the repo does **not** currently deploy the application listening on port `3000`. It only prepares the host and proxy layer around that application.

## Current Architecture by File

- [`vps.tf`](./vps.tf) configures:
  - Terraform Cloud workspace `pranav-personal/vps`
  - AWS provider in `us-west-1`
  - A security group for SSH and HTTP
  - An Amazon Linux 2023 ARM AMI lookup
  - One EC2 instance of type `t4g.nano`
  - A GitHub OIDC-backed IAM role with `AdministratorAccess`
- [`oidc.tf`](./oidc.tf) creates the AWS OIDC provider for GitHub Actions.
- [`dns.tf`](./dns.tf) does **not** manage DNS records right now. It uses Cloudflare only to mint an Origin CA certificate and private key, then writes them to local files.
- [`site.yml`](./site.yml) copies the origin cert/key to the host and pushes an nginx config.
- [`nginx.conf.j2`](./nginx.conf.j2) configures nginx to:
  - listen on `80` and `443`
  - redirect HTTP to HTTPS
  - proxy traffic to `http://localhost:3000`
- [`.github/workflows/terraform.yml`](./.github/workflows/terraform.yml) is the intended automation entrypoint:
  - runs on pushes and PRs to `main`
  - authenticates to AWS via GitHub OIDC
  - authenticates to Terraform Cloud via `TF_API_TOKEN`
  - runs `terraform init/validate/plan/apply`
  - installs the SSH key from GitHub secrets
  - runs the Ansible playbook to copy certs and reload nginx

## Current Deployment Flow

This is the deployment flow implied by the code today:

1. Push to `main`.
2. GitHub Actions assumes the `github-terraform` IAM role in AWS via OIDC.
3. Terraform applies infrastructure changes against the `vps` Terraform Cloud workspace.
4. Terraform generates a Cloudflare Origin CA keypair and certificate.
5. Those files are expected to exist as local files named `origin.crt` and `origin.key`.
6. GitHub Actions writes the EC2 SSH private key from secrets to `~/.ssh/id_rsa`.
7. The workflow SSHes to the server and runs Ansible.
8. Ansible copies the cert/key to `/etc/nginx/ssl` and deploys the nginx reverse-proxy config.

## Secrets, Credentials, and State

### Where state lives

- Terraform state is intended to live in Terraform Cloud, in organization `pranav-personal`, workspace `vps`.
- That is good for the "work from anywhere" goal because the state is not tied to one laptop.

### Where secrets live today

- AWS access from CI is handled through GitHub OIDC, which is good because there are no long-lived AWS keys in the repo.
- Cloudflare credentials are expected as GitHub Actions secrets:
  - `CLOUDFLARE_GLOBAL_API_TOKEN`
  - `CLOUDFLARE_EMAIL`
- Terraform Cloud access is expected as the GitHub Actions secret `TF_API_TOKEN`.
- SSH access is expected as the GitHub Actions secret `EC2_SSH_KEY`.
  Store `EC2_SSH_KEY` as the base64-encoded contents of the EC2 private key file so CI does not depend on pasted multi-line key formatting.

### Sensitive files generated or expected locally

- `origin.key` is a private key and must never be committed.
- `origin.crt` is not secret in the same way as the private key, but it still should not be treated as a casually committed artifact.
- `vpsKey.pem` is an SSH private key and must never be committed.

### Current secret-handling concerns

- The Cloudflare provider is using `email + api_key`, which means the workflow is effectively expecting the legacy Global API key model, not a narrowly scoped API token.
- `origin.key` and `origin.crt` are written directly into the repo root by Terraform via `local_sensitive_file`.
- [`.gitignore`](./.gitignore) ignores `*.pem`, but it does **not** ignore `origin.key` or `origin.crt`.
  - That means `origin.key` is easy to accidentally commit.
- The EC2 key pair is not created by Terraform. The instance expects an existing AWS key pair named `vpsKey`, and the matching private key has to exist outside Terraform.

## What Is Codified vs. Still Manual

Codified in this repo:

- AWS instance creation
- AWS security group creation
- GitHub OIDC provider and IAM role
- Cloudflare Origin CA certificate generation
- Nginx reverse-proxy config deployment

Still external or manual:

- The actual web app on port `3000`
- Cloudflare DNS records for the site
- The AWS EC2 key pair named `vpsKey`
- The Terraform Cloud workspace settings themselves
- GitHub repository secrets
- Any bootstrap or deployment process for the app behind nginx

## Design Decisions That Currently Work Against "Clone It Anywhere and Operate It"

The repo is partway there, but a few choices still make it environment-dependent:

1. Hard-coded IPv4 address assumptions
   - [`inventory.ini`](./inventory.ini) hard-codes `204.236.176.6`.
   - The GitHub Actions workflow also hard-codes that same IP in the `ssh-keyscan` step.
   - Because the EC2 instance uses its normal public IP output and not an Elastic IP, this address can change if the instance is replaced or stopped and started.

2. Manual SSH key-pair dependency
   - Terraform references `key_name = "vpsKey"` but does not create that key pair.
   - Anyone operating this repo from a new machine also needs the matching private key and the GitHub secret to stay in sync with AWS.

3. Mixed local and remote execution assumptions
   - Terraform is configured to use Terraform Cloud.
   - The workflow later expects `origin.crt` and `origin.key` to exist on the GitHub runner so Ansible can copy them.
   - That only works cleanly if the Terraform execution mode for workspace `vps` is local/CLI-driven. If that workspace is set to remote execution, the local file resources would be created on the remote worker instead of on the GitHub runner.

4. The app itself is not part of the IaC story yet
   - The repo assumes something is already listening on `localhost:3000`.
   - Pulling this repo onto a new machine is not enough to recreate the full service end-to-end.

5. The branch and automation assumptions are narrow
   - The workflow is wired to `main`.
   - This checkout was on branch `initial` when this README was updated, so changes on non-`main` branches will not automatically run the deployment workflow.

## Current Gaps or Mismatches in the Architecture

These are the biggest things to be aware of if you pick this project back up:

- The security group opens `22` and `80`, but **not `443`**, while nginx is configured to serve TLS on `443`.
  - If Cloudflare is meant to connect to the origin over HTTPS, `443` needs to be reachable from Cloudflare.
- The nginx config is copied to `/etc/nginx/sites-available/default`, which is a Debian/Ubuntu-style path.
  - The EC2 instance is Amazon Linux 2023, so this path likely is not part of the stock nginx include structure unless additional manual setup happened on the server.
- The workflow contains debug steps that print `TF_VAR_*` environment variables.
  - GitHub will mask stored secret values, but the step is still unnecessary noise in CI logs.
- `dns.tf` generates an origin certificate, but it does not currently manage the actual `A`/`AAAA`/CNAME records in Cloudflare.

## Brief Note on Moving from Public IPv4 to IPv6

If the goal is to avoid the cost of a public IPv4 address, this repo will need a small architecture shift because the current automation assumes direct SSH to a hard-coded public IPv4.

At a high level, the change would look like this:

1. Attach an IPv6 CIDR block to the VPC and use a subnet that assigns IPv6 addresses.
2. Launch the EC2 instance with an IPv6 address.
3. Update the security group to allow the required IPv6 ingress and egress rules using `::/0` where appropriate.
4. Publish a Cloudflare `AAAA` record for the origin instead of depending on an IPv4 address.
5. Replace the hard-coded IPv4 in Ansible inventory and CI with a hostname or generated inventory value.
6. Decide how SSH should work:
   - direct over IPv6
   - AWS SSM Session Manager
   - another private access path such as Tailscale, WireGuard, or Cloudflare Tunnel

If you want a truly "operate from anywhere" setup, SSH over a fixed public IPv4 is probably not the end state. Terraform Cloud + GitHub Actions + SSM or another identity-based access path would travel much better.

## Recommended Next Steps

Short term:

- Ignore `origin.key` and `origin.crt` in Git so they cannot be committed by accident.
- Replace the hard-coded IP address in [`inventory.ini`](./inventory.ini) and the workflow with something derived from Terraform output or DNS.
- Decide whether Terraform Cloud should run in local execution mode or whether cert handling should move out of `local_sensitive_file`.
- Fix the mismatch between Amazon Linux nginx paths and the Ansible destination path.
- Open `443` in the security group if Cloudflare is expected to talk HTTPS to the origin.

Medium term:

- Move from Cloudflare Global API key usage to a scoped API token model.
- Manage Cloudflare DNS records in Terraform so the repo defines the whole edge-to-origin path.
- Manage the app deployment itself, not just nginx in front of it.
- Reduce IAM permissions from `AdministratorAccess` to a least-privilege policy for this repo.

Longer term:

- Move away from direct public-IPv4 SSH assumptions.
- Adopt IPv6-first or IPv6-only origin networking if the cost goal is to eliminate the public IPv4.
- Prefer identity-based access and generated inventory so the repo can be cloned and operated from anywhere with the right platform credentials.

## Quick Reality Check

Right now, this repo is best described as:

> a partial but promising personal hosting stack

It already has a good backbone for portable infrastructure management because state is in Terraform Cloud and AWS auth can be done through GitHub OIDC. The parts that still keep it from being fully portable are mostly secret/material handling, manual SSH assumptions, hard-coded addressing, and the fact that the actual app deployment is still outside the repo.
