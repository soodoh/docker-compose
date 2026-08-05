variable "tailscale_enable_management" {
  type    = bool
  default = false
}


variable "ci_plan_identity_import_id" {
  type        = string
  default     = ""
  description = "Existing CI plan enrollment identity ID used only during adoption."
}

variable "ci_apply_identity_import_id" {
  type        = string
  default     = ""
  description = "Existing CI apply enrollment identity ID used only during adoption."
}

variable "github_owner_id" {
  type        = string
  default     = ""
  description = "Stable numeric GitHub owner ID used by Tailscale trust subjects."

  validation {
    condition     = !var.tailscale_enable_management || can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "github_owner_id must be a numeric GitHub owner ID when Tailscale management is enabled."
  }
}

variable "github_repository_id" {
  type        = string
  default     = ""
  description = "Stable numeric GitHub repository ID used by Tailscale trust subjects."

  validation {
    condition     = !var.tailscale_enable_management || can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "github_repository_id must be a numeric GitHub repository ID when Tailscale management is enabled."
  }
}

locals {
  contract              = yamldecode(file("${path.module}/../../contract/home-lab.yml"))
  tags                  = local.contract.tailscale.tags
  github_subject_prefix = "repo:${local.contract.github.owner}@${var.github_owner_id}/${local.contract.github.repository}@${var.github_repository_id}"

  policy = {
    tagOwners = {
      (local.tags.arch)         = ["autogroup:admin"]
      (local.tags.proxmox)      = ["autogroup:admin"]
      (local.tags.infra_router) = ["autogroup:admin"]
      (local.tags.ci_legacy)    = ["autogroup:admin"]
      (local.tags.ci_plan)      = ["autogroup:admin"]
      (local.tags.ci_apply)     = ["autogroup:admin"]
    }

    autoApprovers = {
      routes = {
        "192.168.0.100/32" = [local.tags.infra_router]
        "192.168.0.123/32" = [local.tags.infra_router]
      }
    }

    grants = [
      {
        src = ["autogroup:admin"]
        dst = [local.tags.infra_router]
        ip  = ["*"]
      },
      {
        src = ["autogroup:admin", local.tags.ci_legacy]
        dst = ["192.168.0.123"]
        ip  = ["tcp:8006"]
      },
      {
        src = ["autogroup:admin", local.tags.ci_legacy]
        dst = ["192.168.0.100"]
        ip  = ["tcp:22"]
      },
      {
        src = ["autogroup:owner", "autogroup:admin", local.tags.ci_legacy, local.tags.ci_plan, local.tags.ci_apply]
        dst = [local.tags.arch]
        ip  = ["tcp:22"]
      },
      {
        src = ["autogroup:owner"]
        dst = ["autogroup:self"]
        ip  = ["tcp:22"]
      },
      {
        src = ["autogroup:owner", "autogroup:admin", local.tags.arch]
        dst = [local.tags.proxmox]
        ip  = ["tcp:22", "tcp:8006"]
      },
      {
        src = [local.tags.ci_plan]
        dst = [local.tags.proxmox]
        ip  = ["tcp:22", "tcp:8006"]
      },
      {
        src = [local.tags.ci_apply]
        dst = [local.tags.proxmox]
        ip  = ["tcp:22", "tcp:8006"]
      },
      {
        src = [local.tags.ci_plan, local.tags.ci_apply]
        dst = [local.tags.arch]
        ip  = ["tcp:8043"]
      },
    ]

    ssh = [
      {
        action = "accept"
        src    = ["autogroup:owner"]
        dst    = [local.tags.arch]
        users  = ["docker"]
      },
      {
        action = "accept"
        src    = ["autogroup:admin", local.tags.ci_legacy]
        dst    = [local.tags.arch]
        users  = ["ansible-deploy"]
      },
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
        users  = ["ansible-plan", "ansible-deploy"]
      },
      {
        action = "accept"
        src    = ["autogroup:owner"]
        dst    = ["autogroup:self"]
        users  = ["pauldiloreto"]
      },
      {
        action = "accept"
        src    = ["autogroup:owner", "autogroup:admin", local.tags.arch]
        dst    = [local.tags.proxmox]
        users  = ["root"]
      },
      {
        action = "accept"
        src    = [local.tags.ci_plan]
        dst    = [local.tags.proxmox]
        users  = ["tofu-plan"]
      },
      {
        action = "accept"
        src    = [local.tags.ci_apply]
        dst    = [local.tags.proxmox]
        users  = ["tofu-apply"]
      },
    ]

    tests = [
      {
        src   = local.tags.ci_plan
        proto = "tcp"
        accept = [
          "${local.tags.arch}:22",
          "${local.tags.arch}:8043",
          "${local.tags.proxmox}:22",
          "${local.tags.proxmox}:8006",
        ]
        deny = ["${local.tags.proxmox}:8007"]
      },
      {
        src   = local.tags.ci_apply
        proto = "tcp"
        accept = [
          "${local.tags.arch}:22",
          "${local.tags.arch}:8043",
          "${local.tags.proxmox}:22",
          "${local.tags.proxmox}:8006",
        ]
        deny = ["${local.tags.proxmox}:8007"]
      },
      {
        src   = local.tags.arch
        proto = "tcp"
        accept = [
          "${local.tags.proxmox}:22",
          "${local.tags.proxmox}:8006",
        ]
        deny = ["${local.tags.proxmox}:8007"]
      },
    ]

    sshTests = [
      {
        src    = local.tags.ci_plan
        dst    = [local.tags.proxmox]
        accept = ["tofu-plan"]
        deny   = ["root", "tofu-apply"]
      },
      {
        src    = local.tags.ci_apply
        dst    = [local.tags.proxmox]
        accept = ["tofu-apply"]
        deny   = ["root", "tofu-plan"]
      },
      {
        src    = local.tags.arch
        dst    = [local.tags.proxmox]
        accept = ["root"]
        deny   = ["tofu-plan", "tofu-apply"]
      },
    ]
  }
}

resource "terraform_data" "tailscale_policy" {
  count = var.tailscale_enable_management ? 1 : 0

  input = {
    policy_json   = jsonencode(local.policy)
    policy_sha256 = sha256(jsonencode(local.policy))
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "tailscale_federated_identity" "ci_plan" {
  count = var.tailscale_enable_management ? 1 : 0

  description = null
  issuer      = "https://token.actions.githubusercontent.com"
  subject     = "${local.github_subject_prefix}:environment:${local.contract.github.environments.plan}"
  scopes      = ["auth_keys"]
  tags        = [local.tags.ci_plan]

  lifecycle {
    prevent_destroy = true
  }
}

resource "tailscale_federated_identity" "ci_apply" {
  count = var.tailscale_enable_management ? 1 : 0

  description = "infrastructure-apply"
  issuer      = "https://token.actions.githubusercontent.com"
  subject     = "${local.github_subject_prefix}:environment:${local.contract.github.environments.apply}"
  scopes      = ["auth_keys"]
  tags        = [local.tags.ci_apply]

  lifecycle {
    prevent_destroy = true
  }
}


import {
  for_each = var.tailscale_enable_management && var.ci_plan_identity_import_id != "" ? toset([var.ci_plan_identity_import_id]) : toset([])
  to       = tailscale_federated_identity.ci_plan[0]
  id       = each.value
}

import {
  for_each = var.tailscale_enable_management && var.ci_apply_identity_import_id != "" ? toset([var.ci_apply_identity_import_id]) : toset([])
  to       = tailscale_federated_identity.ci_apply[0]
  id       = each.value
}

resource "tailscale_federated_identity" "provider_plan" {
  count = var.tailscale_enable_management ? 1 : 0

  description = "home-lab GitHub OpenTofu Tailscale plan provider"
  issuer      = "https://token.actions.githubusercontent.com"
  subject     = "${local.github_subject_prefix}:environment:${local.contract.github.environments.plan}"
  scopes = [
    "devices:core:read",
    "devices:posture_attributes:read",
    "federated_keys:read",
    "policy_file:read",
  ]

  lifecycle {
    prevent_destroy = true
  }
}

resource "tailscale_federated_identity" "provider_apply" {
  count = var.tailscale_enable_management ? 1 : 0

  description = "home-lab GitHub OpenTofu Tailscale apply provider"
  issuer      = "https://token.actions.githubusercontent.com"
  subject     = "${local.github_subject_prefix}:environment:${local.contract.github.environments.apply}"
  scopes = [
    "auth_keys",
    "devices:core:read",
    "devices:posture_attributes",
    "federated_keys",
    "policy_file",
  ]
  tags = [local.tags.ci_plan, local.tags.ci_apply]

  lifecycle {
    prevent_destroy = true
  }
}

output "ci_plan_client_id" {
  value = try(tailscale_federated_identity.ci_plan[0].id, null)
}

output "ci_plan_audience" {
  value = try(tailscale_federated_identity.ci_plan[0].audience, null)
}

output "ci_apply_client_id" {
  value = try(tailscale_federated_identity.ci_apply[0].id, null)
}

output "ci_apply_audience" {
  value = try(tailscale_federated_identity.ci_apply[0].audience, null)
}

output "provider_plan_client_id" {
  value = try(tailscale_federated_identity.provider_plan[0].id, null)
}

output "provider_plan_audience" {
  value = try(tailscale_federated_identity.provider_plan[0].audience, null)
}

output "provider_apply_client_id" {
  value = try(tailscale_federated_identity.provider_apply[0].id, null)
}

output "provider_apply_audience" {
  value = try(tailscale_federated_identity.provider_apply[0].audience, null)
}
