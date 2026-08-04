locals {
  state_keys = [
    "home-lab/aws-foundation/tofu.tfstate",
    "home-lab/proxmox/tofu.tfstate",
    "home-lab/proxmox-legacy/tofu.tfstate",
    "home-lab/omada/tofu.tfstate",
    "home-lab/tailscale/tofu.tfstate",
    "home-lab/github/tofu.tfstate",
  ]
  state_arns = [for key in local.state_keys : "${aws_s3_bucket.state.arn}/${key}"]
  lock_arns  = [for key in local.state_keys : "${aws_s3_bucket.state.arn}/${key}.tflock"]
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}/${var.github_repository}:environment:${var.github_plan_environment}"]
    }
  }
}

data "aws_iam_policy_document" "github_apply_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}/${var.github_repository}:environment:${var.github_apply_environment}"]
    }
  }
}

resource "aws_iam_role" "github_plan" {
  name               = "home-lab-infrastructure-plan"
  assume_role_policy = data.aws_iam_policy_document.github_plan_trust.json
}

resource "aws_iam_role" "github_apply" {
  name               = "home-lab-infrastructure-apply"
  assume_role_policy = data.aws_iam_policy_document.github_apply_trust.json
}

data "aws_iam_policy_document" "state_plan" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = concat(local.state_keys, [for key in local.state_keys : "${key}.tflock"])
    }
  }
  statement {
    actions   = ["s3:GetObject"]
    resources = concat(local.state_arns, local.lock_arns)
  }
  statement {
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = local.lock_arns
  }
  statement {
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [aws_kms_key.opentofu.arn]
  }

  statement {
    actions = [
      "s3:GetBucketLocation",
      "s3:GetBucketOwnershipControls",
      "s3:GetBucketPolicy",
      "s3:GetBucketPublicAccessBlock",
      "s3:GetBucketTagging",
      "s3:GetBucketVersioning",
      "s3:GetEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:ListBucket",
    ]
    resources = [aws_s3_bucket.state.arn, aws_s3_bucket.recovery.arn]
  }
  statement {
    actions = [
      "kms:DescribeKey",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListAliases",
      "kms:ListResourceTags",
    ]
    resources = [aws_kms_key.opentofu.arn]
  }
  statement {
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }
  statement {
    actions = [
      "dynamodb:DescribeContinuousBackups",
      "dynamodb:DescribeTable",
      "dynamodb:DescribeTimeToLive",
      "dynamodb:ListTagsOfResource",
    ]
    resources = [aws_dynamodb_table.mutation_lease.arn]
  }
}

data "aws_iam_policy_document" "state_apply" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = concat(local.state_keys, [for key in local.state_keys : "${key}.tflock"])
    }
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = concat(local.state_arns, local.lock_arns)
  }
  statement {
    actions   = ["s3:DeleteObject"]
    resources = local.lock_arns
  }
  statement {
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [aws_kms_key.opentofu.arn]
  }
  statement {
    actions = [
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
    ]
    resources = [aws_dynamodb_table.mutation_lease.arn]
  }

  statement {
    actions = [
      "s3:GetBucketLocation",
      "s3:GetBucketOwnershipControls",
      "s3:GetBucketPolicy",
      "s3:GetBucketPublicAccessBlock",
      "s3:GetBucketTagging",
      "s3:GetBucketVersioning",
      "s3:GetEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:ListBucket",
      "s3:PutBucketOwnershipControls",
      "s3:PutBucketPolicy",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketTagging",
      "s3:PutBucketVersioning",
      "s3:PutEncryptionConfiguration",
      "s3:PutLifecycleConfiguration",
    ]
    resources = [aws_s3_bucket.state.arn, aws_s3_bucket.recovery.arn]
  }
  statement {
    actions   = ["s3:CreateBucket"]
    resources = ["*"]
  }
  statement {
    actions = [
      "kms:CreateAlias",
      "kms:CreateKey",
      "kms:DescribeKey",
      "kms:EnableKeyRotation",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListResourceTags",
      "kms:ListAliases",
      "kms:PutKeyPolicy",
      "kms:TagResource",
      "kms:UpdateAlias",
    ]
    resources = ["*"]
  }
  statement {
    actions = [
      "iam:AddClientIDToOpenIDConnectProvider",
      "iam:AttachRolePolicy",
      "iam:CreateOpenIDConnectProvider",
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:CreateRole",
      "iam:CreateUser",
      "iam:Get*",
      "iam:List*",
      "iam:PutUserPolicy",
      "iam:TagOpenIDConnectProvider",
      "iam:TagPolicy",
      "iam:TagRole",
      "iam:TagUser",
      "iam:SetDefaultPolicyVersion",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateOpenIDConnectProviderThumbprint",
    ]
    resources = ["*"]
  }
  statement {
    actions = [
      "dynamodb:CreateTable",
      "dynamodb:DescribeContinuousBackups",
      "dynamodb:DescribeTable",
      "dynamodb:DescribeTimeToLive",
      "dynamodb:ListTagsOfResource",
      "dynamodb:TagResource",
      "dynamodb:UpdateContinuousBackups",
      "dynamodb:UpdateTable",
      "dynamodb:UpdateTimeToLive",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "state_plan" {
  name   = "home-lab-opentofu-state-plan"
  policy = data.aws_iam_policy_document.state_plan.json
}

resource "aws_iam_policy" "state_apply" {
  name   = "home-lab-opentofu-state-apply"
  policy = data.aws_iam_policy_document.state_apply.json
}

resource "aws_iam_role_policy_attachment" "github_plan" {
  role       = aws_iam_role.github_plan.name
  policy_arn = aws_iam_policy.state_plan.arn
}

resource "aws_iam_role_policy_attachment" "github_apply" {
  role       = aws_iam_role.github_apply.name
  policy_arn = aws_iam_policy.state_apply.arn
}

resource "aws_iam_user" "recovery" {
  name = "home-lab-recovery"

  lifecycle {
    prevent_destroy = true
  }
}

data "aws_iam_policy_document" "recovery" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.recovery.arn, aws_s3_bucket.state.arn]
  }
  statement {
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
    ]
    resources = [
      "${aws_s3_bucket.recovery.arn}/*",
      "${aws_s3_bucket.state.arn}/*",
    ]
  }
  statement {
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [aws_kms_key.opentofu.arn]
  }
}

resource "aws_iam_user_policy" "recovery" {
  name   = "home-lab-recovery"
  user   = aws_iam_user.recovery.name
  policy = data.aws_iam_policy_document.recovery.json
}
