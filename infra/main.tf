module "network" {
  source = "./modules/network"

  project              = var.project
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  db_name     = var.db_name
  db_username = var.db_username
  db_password = var.db_password

}


module "compute" {
  source = "./modules/compute"

  project               = var.project
  db_url                = "postgresql://${var.db_username}:${var.db_password}@${module.network.rds_endpoint}:5432/${var.db_name}"
  private_subnet_ids    = module.network.private_subnet_ids
  ecs_security_group_id = module.network.ecs_security_group_id
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  alb_security_group_id = module.network.alb_security_group_id
  jwt_secret_key        = var.jwt_secret_key

}
