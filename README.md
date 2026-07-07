# FreelanceHub — Déploiement DevOps / Cloud sur AWS

> Déploiement professionnel, reproductible, sécurisé et observable de l'API
> FreelanceHub sur AWS. Infrastructure entièrement en code, pipeline CI/CD sans
> secret stocké, budget maîtrisé (< 15 USD). Région : `eu-west-3` (Paris).

**Statut :** en cours — Bloc 0 (préparation). Ce README sera complété au fil du
projet (rédaction finale au Bloc H).

---

## Contexte & objectif

Projet personnel de démonstration d'un socle DevOps/SRE moderne : IaC,
conteneurisation serverless, CI/CD sécurisé, observabilité et fiabilité.
Cible : relecteurs techniques pour un poste DevOps/SRE junior.

## Architecture

Schéma à venir (Bloc H) — voir [`docs/architecture/`](docs/architecture/).

Vue d'ensemble prévue :
- Réseau : VPC, subnets publics/privés, Internet Gateway, (NAT), Security Groups
- Compute : ECS Fargate derrière un Application Load Balancer (HTTPS)
- Données : RDS PostgreSQL en subnet privé (jamais exposée publiquement)
- CI/CD : GitHub Actions vers AWS via OIDC (aucune clé stockée)
- Sécurité : Secrets Manager, scans Trivy + Checkov/tfsec
- Observabilité : CloudWatch (logs, dashboards, alarmes), SNS, CloudTrail

## Stack technique

| Domaine         | Outils / Services                                 |
|-----------------|---------------------------------------------------|
| IaC             | Terraform (backend distant S3 + DynamoDB)         |
| Conteneurs      | Docker, Amazon ECR                                |
| Orchestration   | Amazon ECS Fargate                                |
| Exposition      | Application Load Balancer + ACM (HTTPS)           |
| Base de données | Amazon RDS PostgreSQL                             |
| CI/CD           | GitHub Actions (OIDC)                             |
| Sécurité        | AWS Secrets Manager, Trivy, Checkov / tfsec       |
| Observabilité   | CloudWatch, SNS, CloudTrail                       |
| Application     | FastAPI, PostgreSQL, JWT (support de déploiement) |

## Prérequis

- Compte AWS avec droits (VPC, ECS, IAM, ECR, RDS…) et alarme de budget active
- Compte GitHub (hébergement du code + exécution des pipelines)
- Terraform, Docker et AWS CLI installés en local

## Déploiement

Principe : infrastructure éphémère — on crée le temps d'une session, on détruit
ensuite pour maîtriser le coût.

    terraform init
    terraform plan
    terraform apply
    # ...
    terraform destroy

_(commandes détaillées à finaliser au fil des blocs)_

## Choix techniques

Les décisions structurantes sont tracées sous forme d'ADR dans
[`docs/decisions/`](docs/decisions/) : garde-fou budgétaire hors cycle éphémère,
NAT Gateway vs alternatives, domaine pour HTTPS, bootstrap du backend d'état.

## FinOps

Budget cible : 15 USD sur toute la durée. Postes de coût continus à surveiller :
NAT Gateway et ALB. Discipline `destroy`/`recreate` entre les sessions + alarme
de budget AWS active avant toute ressource payante (voir `infra/bootstrap/`).

## Fiabilité

Un incident est simulé et documenté de bout en bout (détection → diagnostic →
résolution → post-mortem) : voir [`docs/post-mortem/`](docs/post-mortem/).

## Structure du dépôt

    .
    ├── infra/
    │   └── bootstrap/         # ressources hors cycle : budget, backend d'état
    ├── app/                   # application FreelanceHub + Dockerfile
    ├── .github/workflows/     # pipelines CI/CD (GitHub Actions)
    └── docs/                  # documentation, schémas, décisions, post-mortem
