output "ecr_repository_url" {
  description = "URL du repository ECR (pour docker push/pull)"
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_repository_name" {
  value = aws_ecr_repository.app.name
}
output "alb_dns_name" {
  description = "URL publique de l'ALB (HTTP)"
  value       = aws_lb.this.dns_name
}