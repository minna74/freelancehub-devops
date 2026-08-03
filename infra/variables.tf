variable "project" {
  description = "Préfixe de nommage du projet"
  type        = string
  default     = "freelancehub"
}

variable "region" {
  description = "Région AWS"
  type        = string
  default     = "eu-west-3"
}

variable "vpc_cidr" {
  description = "Plage d'adresses du VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Zones de disponibilité utilisées"
  type        = list(string)
  default     = ["eu-west-3a", "eu-west-3b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR des subnets publics (un par AZ)"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR des subnets privés (un par AZ)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "db_name" {
  type    = string
  default = "freelancehub"
}

variable "db_username" {
  type    = string
  default = "fhadmin"
}

variable "db_password" {
  description = "Mot de passe maître RDS (fourni via TF_VAR_db_password)"
  type        = string
  sensitive   = true
}
variable "jwt_secret_key" {
  description = "Cle secrete JWT (fournie via TF_VAR_jwt_secret_key)"
  type        = string
  sensitive   = true
}
variable "alert_email" {
  description = "Email pour les alertes SNS"
  type        = string
  default     = "adam.asseidsiddick.ensao@ump.ac.ma"
}