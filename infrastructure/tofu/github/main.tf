locals {
  contract   = yamldecode(file("${path.module}/../../contract/home-lab.yml"))
  repository = local.contract.github.repository
  variables = {
    TS_OAUTH_CLIENT_ID               = var.tailscale_oauth_client_id
    TS_AUDIENCE                      = var.tailscale_audience
    AWS_REGION                       = var.aws_region
    AWS_PLAN_ROLE_ARN                = var.aws_plan_role_arn
    AWS_APPLY_ROLE_ARN               = var.aws_apply_role_arn
    ARCH_SSH_HOST                    = local.contract.network.arch.magicdns_name
    ARCH_SSH_HOST_KEY_FINGERPRINT    = var.arch_ssh_host_key_fingerprint
    PROXMOX_API_ENDPOINT             = local.contract.proxmox.api_endpoint
    PROXMOX_SSH_HOST                 = local.contract.network.proxmox.magicdns_name
    PROXMOX_SSH_HOST_KEY_FINGERPRINT = var.proxmox_ssh_host_key_fingerprint
    OMADA_ENDPOINT                   = local.contract.omada.endpoint
    INFRASTRUCTURE_AUTO_PLAN_ENABLED = "true"
    INFRASTRUCTURE_APPLY_ENABLED     = "true"
  }
}

provider "github" {
  owner = var.github_owner
}

resource "github_repository_environment" "plan" {
  count = var.github_enable_management ? 1 : 0

  repository          = local.repository
  environment         = local.contract.github.environments.plan
  can_admins_bypass   = false
  prevent_self_review = true

  deployment_branch_policy {
    protected_branches     = true
    custom_branch_policies = false
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "github_repository_environment" "apply" {
  count = var.github_enable_management ? 1 : 0

  repository          = local.repository
  environment         = local.contract.github.environments.apply
  can_admins_bypass   = false
  prevent_self_review = true

  deployment_branch_policy {
    protected_branches     = true
    custom_branch_policies = false
  }

  reviewers {
    users = var.apply_reviewer_user_ids
    teams = var.apply_reviewer_team_ids
  }

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = length(var.apply_reviewer_user_ids) + length(var.apply_reviewer_team_ids) > 0
      error_message = "The apply environment requires at least one independent reviewer."
    }
  }
}

import {
  for_each = var.github_enable_management ? toset([local.contract.github.environments.plan]) : toset([])
  to       = github_repository_environment.plan[0]
  id       = "${local.repository}:${each.value}"
}

import {
  for_each = var.github_enable_management ? toset([local.contract.github.environments.apply]) : toset([])
  to       = github_repository_environment.apply[0]
  id       = "${local.repository}:${each.value}"
}

resource "github_actions_variable" "infrastructure" {
  for_each = var.github_enable_management ? local.variables : {}

  repository    = local.repository
  variable_name = each.key
  value         = each.value
}

resource "github_repository_ruleset" "main" {
  count = var.github_enable_management ? 1 : 0

  repository  = local.repository
  name        = "protect-main"
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    deletion                = true
    non_fast_forward        = true
    required_linear_history = true

    pull_request {
      allowed_merge_methods             = ["squash", "rebase"]
      dismiss_stale_reviews_on_push     = true
      require_last_push_approval        = true
      required_approving_review_count   = 1
      required_review_thread_resolution = true
    }

    dynamic "required_status_checks" {
      for_each = length(var.required_status_checks) > 0 ? [1] : []
      content {
        strict_required_status_checks_policy = true
        dynamic "required_check" {
          for_each = var.required_status_checks
          content {
            context = required_check.value
          }
        }
      }
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

import {
  for_each = var.github_enable_management && var.ruleset_import_id != "" ? toset([var.ruleset_import_id]) : toset([])
  to       = github_repository_ruleset.main[0]
  id       = "${local.repository}:${each.value}"
}
