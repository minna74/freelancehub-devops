provider "aws" {
  region = var.region

  # Tags appliqués automatiquement à TOUTES les ressources du projet
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}
