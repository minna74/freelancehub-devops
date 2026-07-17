# ---------------------------------------------------------------------------
#  Repository ECR : registre privé pour l'image Docker de l'application.
#  - scan_on_push : analyse automatique des vulnérabilités à chaque push
#    (préfigure le scan Trivy du Bloc D, complémentaire).
#  - force_delete : permet à `terraform destroy` de supprimer le repo même
#    s'il contient encore des images (cohérent avec l'infra éphémère).
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "app" {
  name                 = "${var.project}-api"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project}-api-ecr"
  }
}

# ---------------------------------------------------------------------------
#  Politique de cycle de vie : ne garde que les 10 dernières images.
#  Évite l'accumulation indéfinie (et le coût de stockage qui va avec).
# ---------------------------------------------------------------------------
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Garder seulement les 10 dernieres images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}