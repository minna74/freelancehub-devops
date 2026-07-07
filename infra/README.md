# infra/ — Infrastructure as Code (Terraform)

Contient l'ensemble de l'infrastructure décrite en Terraform : réseau (VPC,
subnets, routing, Security Groups), base RDS PostgreSQL, ECR, ECS Fargate, ALB
et HTTPS.

L'état est stocké dans un backend distant (S3 + verrou DynamoDB) — voir Bloc A.
Rien n'est créé manuellement dans la console AWS.

Le sous-dossier [`bootstrap/`](bootstrap/) regroupe les ressources créées une
seule fois, **hors** du cycle `destroy`/`recreate` (garde-fou budgétaire,
backend d'état).
