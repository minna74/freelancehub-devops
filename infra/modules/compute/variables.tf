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