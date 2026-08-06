# AWS state bootstrap and migration

The AWS foundation root is intentionally local-state first because it creates the remote state bucket, recovery bucket, KMS keys, and GitHub OIDC roles used by later roots. Root operations use native OpenTofu S3 lockfiles rather than a separate DynamoDB lease table.

The migration away from the former global lease is destructive only for that obsolete table. The reviewed AWS-foundation plan first updates the apply policy with temporary `GetItem`, `DescribeTable`, and `DeleteTable` authority scoped to the exact former table; the count-zero tombstone depends on that update. Immediately before exact-plan apply, the reconciler performs a consistent read of only the fixed production lease key and refuses retirement unless the item is absent. Plan policy permits only the exact former name, key schema, billing mode, TTL schema, and deletion address. After a successful delete and no-op proof, use a follow-up reviewed PR to remove the transitional tombstone and temporary DynamoDB authority. A failed deletion is non-authoritative and must be replanned after inspection.

1. Authenticate with a reviewed bootstrap identity and populate protected `TF_VAR_*` values.
2. Ensure the checkout is clean and inspect `scripts/bootstrap-aws-state`.
3. When retaining the existing off-site backup bucket, independently verify its identity and set `AWS_FOUNDATION_RECOVERY_ADOPTION_CONFIRMED=import-existing-recovery-bucket`. The bootstrap then imports only that bucket's existing base, versioning, encryption, ownership, and public-access resources; lifecycle remains a reviewed create when absent.

The foundation and existing off-site bucket intentionally use separate reviewed regions. `TF_VAR_recovery_bucket_region` selects the aliased recovery provider, and the recovery bucket uses a region-local rotating KMS key; never attempt to encrypt it with the state region's KMS key.

If the account already has the GitHub Actions OIDC provider, independently verify its URL and set `AWS_FOUNDATION_GITHUB_OIDC_ADOPTION_CONFIRMED=import-existing-github-oidc-provider`; the bootstrap imports and reconciles it instead of attempting a duplicate.

Resolve the stable numeric GitHub owner and repository IDs and provide `TF_VAR_github_owner_id` and `TF_VAR_github_repository_id`. This repository's GitHub OIDC customization emits canonical subjects containing those IDs; name-only trust conditions will be rejected by AWS even when the environment name matches.
4. Set the exact `AWS_FOUNDATION_BOOTSTRAP_CONFIRMED=create-and-migrate-reviewed-aws-foundation` gate.
5. Run `scripts/bootstrap-aws-state`. It creates a private ignored copy with a local backend, permits only allowlisted creates plus the explicit recovery-bucket imports/updates, applies the saved plan serially, and migrates that state to the encrypted S3 backend.

If apply fails after creating resources, retain the private workspace and state. After correcting the reviewed cause, set `AWS_FOUNDATION_BOOTSTRAP_RESUME_CONFIRMED=resume-reviewed-partial-aws-bootstrap`. Resume is allowed only when the current root and contract match the retained copy; the policy permits remaining creates and explicit imports but no deletes.
6. The script compares the canonical local and remote outputs/resources without printing state, removes transient state from the tracked root, and requires a remote-backend no-op. It tolerates backend-assigned lineage/serial changes only when the complete managed state projection is identical.
7. Retain `.local/aws-foundation-bootstrap` as protected sensitive recovery material until the remote state is independently verified, then securely remove it and revoke the temporary bootstrap access key, attached policy, and IAM identity. Root login is reserved only for creating and deleting that temporary identity and must be logged out afterward.

Do not create empty state objects manually, use `-migrate-state` in CI, or infer bucket/table names. Migration remains blocked until protected backend coordinates and AWS credentials are supplied. The canonical reconciler refuses to treat an unqualified local-state foundation as steady production.