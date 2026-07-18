variable "project" {
  description = "Préfixe de nommage"
  type        = string
}

variable "db_url" {
  description = "URL de connexion PostgreSQL"
  type        = string
  sensitive   = true
}
variable "private_subnet_ids" {
  description = "IDs des subnets privés (pour les tâches ECS)"
  type        = list(string)
}

variable "ecs_security_group_id" {
  description = "ID du Security Group ECS"
  type        = string
}

variable "vpc_id" {
  description = "ID du VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "IDs des subnets publics (pour l'ALB)"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "ID du Security Group ALB"
  type        = string
}