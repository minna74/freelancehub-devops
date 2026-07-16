# ---------------------------------------------------------------------------
#  VPC principal
# ---------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr

  # DNS activé : indispensable pour résoudre les endpoints (RDS, ECR, etc.)
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project}-vpc"
  }
}

# ---------------------------------------------------------------------------
#  Subnets PUBLICS (un par AZ)
#  map_public_ip_on_launch = true : ce qui y atterrit (ALB, NAT) est joignable
#  et/ou route vers l'extérieur via l'Internet Gateway (ajouté en A.3).
# ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project}-public-${var.azs[count.index]}"
    Tier = "public"
  }
}

# ---------------------------------------------------------------------------
#  Subnets PRIVÉS (un par AZ)
#  Aucune IP publique, aucune route vers l'IGW. C'est ici que vivront les
#  tâches ECS et RDS. La sortie Internet passera par la NAT (A.4).
# ---------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.project}-private-${var.azs[count.index]}"
    Tier = "private"
  }
}


# ---------------------------------------------------------------------------
#  Internet Gateway : la "porte" entre le VPC et Internet.
#  Sans lui, aucune ressource du VPC ne peut communiquer avec l'extérieur.
# ---------------------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project}-igw"
  }
}

# ---------------------------------------------------------------------------
#  Route table PUBLIQUE : envoie tout le trafic sortant (0.0.0.0/0) vers l'IGW.
#  C'est CETTE route vers l'IGW qui définit un subnet comme "public".
# ---------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"                 # "toute destination"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.project}-public-rt"
  }
}

# ---------------------------------------------------------------------------
#  Association : on rattache la route table publique aux subnets publics.
#  count : une association par subnet public (donc 2, une par AZ).
#  C'est CETTE ligne qui rend concrètement tes subnets publics "publics".
# ---------------------------------------------------------------------------
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}


# ---------------------------------------------------------------------------
#  Elastic IP : une IP publique fixe pour la NAT Gateway.
#  (Une NAT a besoin d'une adresse publique stable pour sortir sur Internet.)
# ---------------------------------------------------------------------------
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project}-nat-eip"
  }
}

# ---------------------------------------------------------------------------
#  NAT Gateway : placée dans UN subnet public (elle a besoin de l'IGW pour
#  sortir). UNE seule NAT partagée par les deux AZ -> choix économique (ADR 0004).
# ---------------------------------------------------------------------------
resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id   # dans le 1er subnet public

  tags = {
    Name = "${var.project}-nat"
  }

  # La NAT dépend de l'IGW : on le rend explicite par prudence.
  depends_on = [aws_internet_gateway.this]
}

# ---------------------------------------------------------------------------
#  Route table PRIVÉE : envoie le trafic sortant (0.0.0.0/0) vers la NAT
#  (et non vers l'IGW). C'est ce qui distingue "privé" de "public".
# ---------------------------------------------------------------------------
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name = "${var.project}-private-rt"
  }
}

# ---------------------------------------------------------------------------
#  Association : on rattache la route table privée aux subnets privés.
# ---------------------------------------------------------------------------
resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}


# ---------------------------------------------------------------------------
#  Security Group de l'ALB : porte d'entrée publique.
#  Entrée : HTTP (80) et HTTPS (443) depuis Internet.
#  Sortie : tout (il relaiera vers les tâches ECS).
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.project}-alb-sg"
  description = "Autorise le trafic web entrant vers ALB"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS depuis Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP depuis Internet (redirige vers HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Tout le trafic sortant"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-alb-sg"
  }
}

# ---------------------------------------------------------------------------
#  Security Group des tâches ECS : jamais exposées directement.
#  Entrée : UNIQUEMENT depuis le SG de l'ALB (pas depuis Internet).
#  Sortie : tout (image ECR, RDS, Secrets Manager, logs...).
# ---------------------------------------------------------------------------
resource "aws_security_group" "ecs" {
  name        = "${var.project}-ecs-sg"
  description = "Trafic vers les taches ECS, uniquement depuis ALB"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Trafic applicatif depuis ALB uniquement"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]  # ← la source est un SG, pas une IP
  }

  egress {
    description = "Tout le trafic sortant"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-ecs-sg"
  }
}

# ---------------------------------------------------------------------------
#  Subnet group RDS : indique à RDS dans quels subnets se placer.
#  -> les 2 subnets PRIVÉS (AZ différentes, exigé par RDS). Jamais en public.
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id   # les 2 subnets privés d'un coup

  tags = {
    Name = "${var.project}-db-subnet-group"
  }
}

# ---------------------------------------------------------------------------
#  Security Group RDS : le plus verrouillé de tous.
#  Entrée : PostgreSQL (5432) UNIQUEMENT depuis le SG des tâches ECS.
#  Pas de règle de sortie explicite nécessaire (la base ne sort pas d'elle-même).
# ---------------------------------------------------------------------------
resource "aws_security_group" "rds" {
  name        = "${var.project}-rds-sg"
  description = "Acces PostgreSQL uniquement depuis les taches ECS"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "PostgreSQL depuis les taches ECS uniquement"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]   # ← source = le SG ECS
  }

  egress {
    description = "Tout le trafic sortant"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-rds-sg"
  }
}

# ---------------------------------------------------------------------------
#  Base RDS PostgreSQL.
#  - dans les subnets privés (via le subnet group), jamais exposée
#  - protégée par le SG rds (5432 depuis ECS uniquement)
#  - instance minimale db.t3.micro (éligible free tier, coût maîtrisé)
# ---------------------------------------------------------------------------
resource "aws_db_instance" "this" {
  identifier     = "${var.project}-db"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t3.micro"

  allocated_storage = 20            # Go (minimum)
  storage_type      = "gp3"
  storage_encrypted = true          # chiffrement au repos

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az            = false       # une seule AZ -> coût minimal (démo)
  publicly_accessible = false       # JAMAIS accessible depuis Internet
  skip_final_snapshot = true        # pas de snapshot au destroy (infra éphémère)

  tags = {
    Name = "${var.project}-db"
  }
}