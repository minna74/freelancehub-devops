# ---------------------------------------------------------------------------
#  Fournisseur OIDC : établit la confiance entre AWS et GitHub Actions.
#  AWS vérifiera les jetons émis par token.actions.githubusercontent.com.
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]

  # Thumbprint du certificat racine de GitHub (valeur standard, documentée par AWS)
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Name = "${var.project}-github-oidc"
  }
}
# ---------------------------------------------------------------------------
#  Rôle IAM endossé par GitHub Actions via OIDC.
#  La trust policy restreint l'accès au SEUL dépôt "minna74/freelancehub-devops",
#  et SEULEMENT depuis la branche main (pas les PR, pas d'autres branches).
# ---------------------------------------------------------------------------
resource "aws_iam_role" "github_actions" {
  name = "${var.project}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:minna74@215708665/freelancehub-devops@1292837014:ref:refs/heads/main"
        }
      }
    }]
  })

  tags = {
    Name = "${var.project}-github-actions-role"
  }
}
# ---------------------------------------------------------------------------
#  Politique de permissions du rôle GitHub Actions : moindre privilège STRICT.
#  Autorise uniquement le cycle applicatif (build/push ECR, déploiement ECS)
#  sur les ressources précises du projet. Ne couvre PAS la gestion du
#  réseau/RDS/IAM via Terraform -> ces changements restent en apply manuel
#  depuis un poste de travail (voir ADR 0006).
# ---------------------------------------------------------------------------
resource "aws_iam_role_policy" "github_actions" {
  name = "${var.project}-github-actions-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuth"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRRepository"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories"
        ]
        Resource = aws_ecr_repository.app.arn
      },
      {
        Sid    = "ECSDeploy"
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
          "ecs:RunTask",
          "ecs:DescribeTasks"
        ]
        Resource = "*"
      },
      {
        Sid      = "PassExecutionRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.ecs_execution.arn
      },
      {
        Sid    = "CloudWatchLogsRead"
        Effect = "Allow"
        Action = [
          "logs:GetLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = aws_cloudwatch_log_group.app.arn
      }
    ]
  })
}
# ---------------------------------------------------------------------------
#  Rôle IAM dédié au `terraform plan` sur pull request.
#  Trust policy plus permissive (toutes branches/PR) car un plan ne modifie
#  jamais rien -> pas de risque même si une PR externe le déclenche.
#  Permissions strictement en LECTURE SEULE (Describe/Get/List).
# ---------------------------------------------------------------------------
resource "aws_iam_role" "github_actions_plan" {
  name = "${var.project}-github-actions-plan-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # Autorise TOUTES les branches et PR de CE dépôt (nécessaire pour
          # que le plan tourne sur n'importe quelle pull request).
          "token.actions.githubusercontent.com:sub" = "repo:minna74@215708665/freelancehub-devops@1292837014:*"
        }
      }
    }]
  })

  tags = {
    Name = "${var.project}-github-actions-plan-role"
  }
}

resource "aws_iam_role_policy" "github_actions_plan" {
  name = "${var.project}-github-actions-plan-policy"
  role = aws_iam_role.github_actions_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadOnlyInfra"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "rds:Describe*",
          "rds:ListTagsForResource",
          "ecs:Describe*",
          "ecs:List*",
          "ecr:Describe*",
          "ecr:List*",
          "ecr:GetAuthorizationToken",
          "elasticloadbalancing:Describe*",
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:GetOpenIDConnectProvider",
          "iam:ListOpenIDConnectProviders",
          "logs:Describe*",
          "logs:ListTagsForResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "TerraformStateRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::freelancehub-tfstate-890615325519",
          "arn:aws:s3:::freelancehub-tfstate-890615325519/*"
        ]
      }
    ]
  })
}

