terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend d'état distant, créé au bootstrap (hors cycle éphémère — ADR 0003)
  backend "s3" {
    bucket       = "freelancehub-tfstate-890615325519"
    key          = "global/terraform.tfstate"
    region       = "eu-west-3"
    use_lockfile = true
    encrypt      = true
  }
}
