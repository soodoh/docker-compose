variable "tailscale_enable_management" {
  type    = bool
  default = false
}

locals {
  contract = yamldecode(file("${path.module}/../../contract/home-lab.yml"))
  tags     = local.contract.tailscale.tags

  policy = {
    tagOwners = {
      (local.tags.arch)     = ["autogroup:admin"]
      (local.tags.proxmox)  = ["autogroup:admin"]
      (local.tags.ci_plan)  = ["autogroup:admin"]
      (local.tags.ci_apply) = ["autogroup:admin"]
    }
    grants = [
      {
        src = [local.tags.ci_plan]
        dst = [local.tags.proxmox]
        ip  = ["tcp:8006"]
      },
      {
        src = [local.tags.ci_plan]
        dst = [local.tags.arch]
        ip  = ["tcp:22", "tcp:8043"]
      },
      {
        src = [local.tags.ci_apply]
        dst = [local.tags.proxmox]
        ip  = ["tcp:22", "tcp:8006"]
      },
      {
        src = [local.tags.ci_apply]
        dst = [local.tags.arch]
        ip  = ["tcp:22", "tcp:8043"]
      },
    ]
    ssh = [
      {
        action = "accept"
        src    = [local.tags.ci_plan]
        dst    = [local.tags.arch]
        users  = ["ansible-plan"]
      },
      {
        action = "accept"
        src    = [local.tags.ci_apply]
        dst    = [local.tags.arch]
        users  = ["ansible-deploy"]
      },
      {
        action = "accept"
        src    = [local.tags.ci_apply]
        dst    = [local.tags.proxmox]
        users  = ["tofu-apply"]
      },
    ]
  }
}

resource "tailscale_acl" "main" {
  count = var.tailscale_enable_management ? 1 : 0

  acl                        = jsonencode(local.policy)
  overwrite_existing_content = false
  reset_acl_on_destroy       = false

  lifecycle {
    prevent_destroy = true
  }
}

import {
  for_each = var.tailscale_enable_management ? toset(["acl"]) : toset([])
  to       = tailscale_acl.main[0]
  id       = each.value
}

resource "tailscale_federated_identity" "ci_plan" {
  count = var.tailscale_enable_management ? 1 : 0

  description = "home-lab GitHub plan runner"
  issuer      = "https://token.actions.githubusercontent.com"
  subject     = "repo:${local.contract.github.owner}/${local.contract.github.repository}:environment:${local.contract.github.environments.plan}"
  scopes      = ["auth_keys"]
  tags        = [local.tags.ci_plan]

  lifecycle {
    prevent_destroy = true
  }
}

resource "tailscale_federated_identity" "ci_apply" {
  count = var.tailscale_enable_management ? 1 : 0

  description = "home-lab GitHub apply runner"
  issuer      = "https://token.actions.githubusercontent.com"
  subject     = "repo:${local.contract.github.owner}/${local.contract.github.repository}:environment:${local.contract.github.environments.apply}"
  scopes      = ["auth_keys"]
  tags        = [local.tags.ci_apply]

  lifecycle {
    prevent_destroy = true
  }
}

output "ci_plan_client_id" {
  value = try(tailscale_federated_identity.ci_plan[0].id, null)
}

output "ci_apply_client_id" {
  value = try(tailscale_federated_identity.ci_apply[0].id, null)
}
