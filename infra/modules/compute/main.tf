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
#  Rétention limitée pour maîtriser le coût.
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

  container_definitions = jsonencode([
    {
      name      = "${var.project}-api"
      image     = "${aws_ecr_repository.app.repository_url}:v1"
      essential = true

      portMappings = [{
        containerPort = 8000
        protocol      = "tcp"
      }]

      environment = [
        { name = "DB_URL", value = var.db_url }
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

# ---------------------------------------------------------------------------
#  Service ECS : maintient N copies de la Task Definition en vie en continu,
#  dans les subnets PRIVÉS (jamais exposé directement), avec le SG ecs.
#  Pas encore de load balancer -> ajouté en B.7 (ALB).
# ---------------------------------------------------------------------------
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

  tags = {
    Name = "${var.project}-service"
  }
}

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