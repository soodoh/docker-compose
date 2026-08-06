data "terraform_remote_state" "tailscale" {
  count   = var.github_enable_management ? 1 : 0
  backend = "s3"

  config = {
    bucket       = var.state_bucket_name
    key          = "home-lab/tailscale/tofu.tfstate"
    region       = var.aws_region
    encrypt      = true
    use_lockfile = true
  }
}

locals {
  contract          = yamldecode(file("${path.module}/../../contract/home-lab.yml"))
  repository        = local.contract.github.repository
  tailscale_outputs = try(data.terraform_remote_state.tailscale[0].outputs, {})

  variables = {
    AWS_REGION                       = var.aws_region
    AWS_RECOVERY_REGION              = local.contract.aws.recovery_region
    AWS_PLAN_ROLE_ARN                = var.aws_plan_role_arn
    AWS_APPLY_ROLE_ARN               = var.aws_apply_role_arn
    ARCH_SSH_HOST                    = local.contract.network.arch.magicdns_name
    ARCH_SSH_HOST_KEY_FINGERPRINT    = var.arch_ssh_host_key_fingerprint
    PROXMOX_API_ENDPOINT             = local.contract.proxmox.api_endpoint
    PROXMOX_SSH_HOST                 = local.contract.network.proxmox.magicdns_name
    PROXMOX_SSH_HOST_KEY_FINGERPRINT = var.proxmox_ssh_host_key_fingerprint
    OMADA_ENDPOINT                   = local.contract.omada.endpoint
    PLAN_ARTIFACT_AGE_RECIPIENT      = var.plan_artifact_age_recipient
    INFRASTRUCTURE_AUTO_PLAN_ENABLED = "true"
    INFRASTRUCTURE_APPLY_ENABLED     = "true"
  }

  managed_repository_variables = var.github_repository_variables_adopt_existing ? {
    for name, value in local.variables : name => value
    if contains(var.github_repository_variable_names_adopt_existing, name)
  } : local.variables

  tailscale_plan_variables = {
    TS_OAUTH_CLIENT_ID         = try(local.tailscale_outputs.ci_plan_client_id, "")
    TS_AUDIENCE                = try(local.tailscale_outputs.ci_plan_audience, "")
    TS_PROVIDER_PLAN_CLIENT_ID = try(local.tailscale_outputs.provider_plan_client_id, "")
    TS_PROVIDER_PLAN_AUDIENCE  = try(local.tailscale_outputs.provider_plan_audience, "")
  }

  tailscale_apply_variables = {
    TS_OAUTH_CLIENT_ID          = try(local.tailscale_outputs.ci_apply_client_id, "")
    TS_AUDIENCE                 = try(local.tailscale_outputs.ci_apply_audience, "")
    TS_PROVIDER_APPLY_CLIENT_ID = try(local.tailscale_outputs.provider_apply_client_id, "")
    TS_PROVIDER_APPLY_AUDIENCE  = try(local.tailscale_outputs.provider_apply_audience, "")
  }
}

provider "github" {
  owner = var.github_owner
}

resource "github_repository_environment" "plan" {
  count = var.github_enable_management ? 1 : 0

  repository        = local.repository
  environment       = local.contract.github.environments.plan
  can_admins_bypass = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "github_repository_environment" "apply" {
  count = var.github_enable_management ? 1 : 0

  repository        = local.repository
  environment       = local.contract.github.environments.apply
  can_admins_bypass = false

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "github_repository_environment_deployment_policy" "apply" {
  for_each = var.github_enable_management ? var.apply_deployment_branches : toset([])

  repository     = local.repository
  environment    = github_repository_environment.apply[0].environment
  branch_pattern = each.value
}

import {
  for_each = var.github_enable_management ? {
    for branch, id in var.apply_deployment_policy_import_ids : branch => id
    if contains(var.apply_deployment_branches, branch)
  } : {}
  to = github_repository_environment_deployment_policy.apply[each.key]
  id = "${local.repository}:${local.contract.github.environments.apply}:${each.value}"
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
  for_each = var.github_enable_management ? local.managed_repository_variables : {}

  repository    = local.repository
  variable_name = each.key
  value         = each.value
}

import {
  for_each = var.github_enable_management && var.github_repository_variables_adopt_existing ? local.managed_repository_variables : {}
  to       = github_actions_variable.infrastructure[each.key]
  id       = "${local.repository}:${each.key}"
}


resource "github_actions_environment_variable" "tailscale_plan" {
  for_each = var.github_enable_management ? local.tailscale_plan_variables : {}

  repository    = local.repository
  environment   = github_repository_environment.plan[0].environment
  variable_name = each.key
  value         = each.value

  lifecycle {
    precondition {
      condition     = each.value != ""
      error_message = "The managed Tailscale plan identities must exist before GitHub environment adoption."
    }
  }
}

resource "github_actions_environment_variable" "tailscale_apply" {
  for_each = var.github_enable_management ? local.tailscale_apply_variables : {}

  repository    = local.repository
  environment   = github_repository_environment.apply[0].environment
  variable_name = each.key
  value         = each.value

  lifecycle {
    precondition {
      condition     = each.value != ""
      error_message = "The managed Tailscale apply identities must exist before GitHub environment adoption."
    }
  }
}


import {
  for_each = var.github_enable_management && var.tailscale_environment_variables_adopt_existing ? local.tailscale_plan_variables : {}
  to       = github_actions_environment_variable.tailscale_plan[each.key]
  id       = "${local.repository}:${local.contract.github.environments.plan}:${each.key}"
}

import {
  for_each = var.github_enable_management && var.tailscale_environment_variables_adopt_existing ? local.tailscale_apply_variables : {}
  to       = github_actions_environment_variable.tailscale_apply[each.key]
  id       = "${local.repository}:${local.contract.github.environments.apply}:${each.key}"
}

resource "github_repository_ruleset" "main" {
  count = var.github_enable_management ? 1 : 0

  repository  = local.repository
  name        = "Default"
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    deletion         = true
    non_fast_forward = true

    pull_request {
      allowed_merge_methods             = ["merge", "squash", "rebase"]
      dismiss_stale_reviews_on_push     = false
      require_last_push_approval        = false
      required_approving_review_count   = 0
      required_review_thread_resolution = false
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
