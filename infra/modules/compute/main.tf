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

# ---------------------------------------------------------------------------
#  Rôle IAM d'EXÉCUTION : utilisé par ECS lui-même (pas par ton appli) pour
#  tirer l'image depuis ECR et écrire les logs vers CloudWatch.
#  "Execution role" != "Task role" : l'execution role sert l'infra ECS,
#  le task role (à venir) donnera des permissions à TON CODE (ex: Secrets Manager).
# ---------------------------------------------------------------------------
resource "aws_iam_role" "ecs_execution" {
  name = "${var.project}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.project}-ecs-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---------------------------------------------------------------------------
#  Log Group : destination des logs de l'application (stdout/stderr).
#  Rétention limitée pour maîtriser le coût..
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project}-api"
  retention_in_days = 7

  tags = {
    Name = "${var.project}-api-logs"
  }
}

# aws_ecs_task_definition

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  volume {
    name = "tmp"
  }

  container_definitions = jsonencode([
    {
      name      = "${var.project}-api"
      image     = "${aws_ecr_repository.app.repository_url}:latest"
      essential = true

      portMappings = [{
        containerPort = 8000
        protocol      = "tcp"
      }]

      # Les valeurs sensibles ne sont plus en clair : ECS les récupère
      # dynamiquement depuis Secrets Manager au démarrage du conteneur.
      secrets = [
        {
          name      = "DB_URL"
          valueFrom = aws_secretsmanager_secret.db_url.arn
        },
        {
          name      = "SECRET_KEY"
          valueFrom = aws_secretsmanager_secret.jwt_secret.arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = "eu-west-3"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = {
    Name = "${var.project}-api-task"
  }
}

# ---------------------------------------------------------------------------
#  Cluster ECS : regroupement logique des services/tâches.
#  Avec Fargate, pas de serveurs à gérer soi-même (contrairement à EC2).
# ---------------------------------------------------------------------------
resource "aws_ecs_cluster" "this" {
  name = "${var.project}-cluster"

  tags = {
    Name = "${var.project}-cluster"
  }
}

# --------------------------------------------------------------------------


# ---------------------------------------------------------------------------
#  Application Load Balancer : point d'entrée public, dans les subnets PUBLICS.
#  "internal = false" -> Internet-facing (le défaut, explicité pour la clarté).
# ---------------------------------------------------------------------------
resource "aws_lb" "this" {
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids
  drop_invalid_header_fields = true

  tags = {
    Name = "${var.project}-alb"
  }
}
# ---------------------------------------------------------------------------
#  Target Group : la "cible" vers laquelle l'ALB route le trafic.
#  target_type = "ip" -> obligatoire pour Fargate (pas d'instances EC2 fixes).
#  Health check sur /health -> réutilise l'endpoint qu'on a déjà (B.1).
# ---------------------------------------------------------------------------
resource "aws_lb_target_group" "app" {
  name        = "${var.project}-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200"
  }

  tags = {
    Name = "${var.project}-tg"
  }
}
# ---------------------------------------------------------------------------
#  Listener HTTP : écoute sur le port 80, transfère tout vers le target group.
#  HTTPS non activé pour cette démo (ADR 0005) -> "prêt à activer" avec un domaine.
# ---------------------------------------------------------------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}


resource "aws_ecs_service" "app" {
  name            = "${var.project}-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false   # subnet privé -> jamais d'IP publique
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name    = "${var.project}-api"
    container_port    = 8000
  }

  depends_on = [aws_lb_listener.http]

  tags = {
    Name = "${var.project}-service"
  }
}


# ---------------------------------------------------------------------------
#  Secrets Manager : DB_URL et SECRET_KEY, jamais en clair dans le code/state.
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "db_url" {
  name        = "${var.project}/db_url"
  description = "URL de connexion PostgreSQL complete"
  recovery_window_in_days = 0   # suppression immediate, coherent avec l'infra ephemere


  tags = {
    Name = "${var.project}-db-url-secret"
  }
}

resource "aws_secretsmanager_secret_version" "db_url" {
  secret_id     = aws_secretsmanager_secret.db_url.id
  secret_string = var.db_url
}

resource "aws_secretsmanager_secret" "jwt_secret" {
  name        = "${var.project}/jwt_secret"
  description = "Cle secrete pour la signature des tokens JWT"
  recovery_window_in_days = 0   # suppression immediate, coherent avec l'infra ephemere


  tags = {
    Name = "${var.project}-jwt-secret"
  }
}

resource "aws_secretsmanager_secret_version" "jwt_secret" {
  secret_id     = aws_secretsmanager_secret.jwt_secret.id
  secret_string = var.jwt_secret_key
}

# ---------------------------------------------------------------------------
#  Permission pour le role d'execution ECS : lire les deux secrets
#  au demarrage du conteneur (et uniquement ces deux-la).
# ---------------------------------------------------------------------------
resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name = "${var.project}-ecs-execution-secrets-policy"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        aws_secretsmanager_secret.db_url.arn,
        aws_secretsmanager_secret.jwt_secret.arn
      ]
    }]
  })
}

# ---------------------------------------------------------------------------
#  Dashboard CloudWatch : vue d'ensemble CPU, mémoire, requêtes, erreurs.
#  Toutes les métriques utilisées sont natives ECS/ALB (aucun coût
#  supplémentaire, contrairement à des métriques custom).
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "ECS - CPU et Memoire"
          region  = "eu-west-3"
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ServiceName", aws_ecs_service.app.name, "ClusterName", aws_ecs_cluster.this.name],
            ["AWS/ECS", "MemoryUtilization", "ServiceName", aws_ecs_service.app.name, "ClusterName", aws_ecs_cluster.this.name]
          ]
          period = 60
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "ALB - Requetes et Erreurs 5xx"
          region  = "eu-west-3"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.this.arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.this.arn_suffix]
          ]
          period = 60
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "ALB - Temps de reponse"
          region  = "eu-west-3"
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.this.arn_suffix]
          ]
          period = 60
          stat   = "Average"
        }
      }
    ]
  })
}
  
# ---------------------------------------------------------------------------
#  Alarme CloudWatch : déclenchée si l'ALB renvoie 5+ erreurs 5xx en 5 minutes.
#  Seuil calibré pour un trafic faible (démo) - ignore le bruit ponctuel,
#  détecte un vrai incident (crash en boucle, RDS injoignable...).
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "high_5xx" {
  alarm_name          = "${var.project}-high-5xx-errors"
  alarm_description   = "Declenchee si l'ALB renvoie 5 erreurs 5xx ou plus en 5 minutes"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods   = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 5

  dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${var.project}-high-5xx-alarm"
  }
}
# ---------------------------------------------------------------------------
#  Topic SNS : point de diffusion des alertes CloudWatch.
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name = "${var.project}-alerts"

  tags = {
    Name = "${var.project}-alerts-topic"
  }
}

# ---------------------------------------------------------------------------
#  Souscription email : IMPORTANT, AWS envoie un email de confirmation
#  après l'apply -> il faut cliquer sur le lien pour activer la réception.
# ---------------------------------------------------------------------------
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}