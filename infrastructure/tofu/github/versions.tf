terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "= 6.13.0"
    }
  }

  backend "s3" {
    key          = "home-lab/github/tofu.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
