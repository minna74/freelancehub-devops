output "vpc_id" {
  description = "ID du VPC"
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "IDs des subnets publics"
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs des subnets privés"
  value       = module.network.private_subnet_ids
}

output "ecr_repository_url" {
  value = module.compute.ecr_repository_url
}

output "app_url" {
  value = "http://${module.compute.alb_dns_name}"
}
output "github_actions_role_arn" {
  value = module.compute.github_actions_role_arn
}
output "github_actions_plan_role_arn" {
  value = module.compute.github_actions_plan_role_arn
}