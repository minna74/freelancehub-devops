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
