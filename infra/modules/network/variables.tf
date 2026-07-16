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
