variable "project" {
  description = "Préfixe de nommage"
  type        = string
}

variable "vpc_cidr" {
  description = "Plage d'adresses du VPC"
  type        = string
}

variable "azs" {
  description = "Zones de disponibilité"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR des subnets publics (un par AZ)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR des subnets privés (un par AZ)"
  type        = list(string)
}

variable "db_name" {
  description = "Nom de la base de données"
  type        = string
  default     = "freelancehub"
}

variable "db_username" {
  description = "Utilisateur maître RDS"
  type        = string
  default     = "fhadmin"
}

variable "db_password" {
  description = "Mot de passe maître RDS (fourni hors code, jamais commité)"
  type        = string
  sensitive   = true   # ← Terraform masquera cette valeur dans ses sorties
}

