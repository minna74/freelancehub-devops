output "ecr_repository_url" {
  description = "URL du repository ECR (pour docker push/pull)"
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_repository_name" {
  description = "Nom du repository ECR"
  value       = aws_ecr_repository.app.name
}
output "alb_dns_name" {
  description = "URL publique de l'ALB (HTTP)"
  value       = aws_lb.this.dns_name
}
output "github_actions_role_arn" {
  description = "ARN du rôle IAM assumé par GitHub Actions (OIDC)"
  value       = aws_iam_role.github_actions.arn
}
output "github_actions_plan_role_arn" {
  description = "ARN du rôle IAM en lecture seule pour terraform plan (PR)"
  value       = aws_iam_role.github_actions_plan.arn
}