# Synthèse réseau & RDS (Bloc A)

Ce document décrit l'infrastructure réseau du projet FreelanceHub, définie
entièrement en Terraform dans le module `infra/modules/network/`. Il complète les
décisions tracées en ADR (0004 pour la NAT).

## Vue d'ensemble

Un VPC unique héberge l'ensemble, réparti sur **deux zones de disponibilité**
(eu-west-3a / eu-west-3b) pour la tolérance de panne. Chaque AZ contient un subnet
public et un subnet privé.

```
Internet
   │
[Internet Gateway]
   │
┌──────────────────────── VPC 10.0.0.0/16 ─────────────────────────┐
│                                                                  │
│  Subnets PUBLICS (2 AZ)          Subnets PRIVÉS (2 AZ)           │
│  - ALB (à venir, Bloc B)         - Tâches ECS (à venir, Bloc B)  │
│  - NAT Gateway                   - RDS PostgreSQL                │
│         │                                 ▲                      │
│         └── route 0.0.0.0/0 ──► IGW       │ route 0.0.0.0/0 ─► NAT│
└──────────────────────────────────────────────────────────────────┘
```

## Plan d'adressage

| Subnet     | AZ           | CIDR          | Rôle                         |
|------------|--------------|---------------|------------------------------|
| public-a   | eu-west-3a   | 10.0.0.0/24   | ALB, NAT Gateway             |
| public-b   | eu-west-3b   | 10.0.1.0/24   | ALB (haute dispo)            |
| private-a  | eu-west-3a   | 10.0.10.0/24  | Tâches ECS, RDS              |
| private-b  | eu-west-3b   | 10.0.11.0/24  | Tâches ECS, RDS (2e AZ)      |

VPC : `10.0.0.0/16`. DNS activé (`enable_dns_hostnames`) — requis pour résoudre
les endpoints RDS et ECR.

## Routage

- **Route table publique** : route `0.0.0.0/0` → Internet Gateway. Associée aux
  deux subnets publics. C'est cette route vers l'IGW qui définit un subnet comme
  public.
- **Route table privée** : route `0.0.0.0/0` → NAT Gateway. Associée aux deux
  subnets privés. Permet la sortie Internet (ECR, Secrets Manager, logs) sans
  exposer les ressources.
- **NAT Gateway** : unique (une seule, partagée par les deux AZ) — choix de coût
  documenté dans l'ADR 0004. Placée dans un subnet public, avec une Elastic IP.

## Sécurité réseau — chaîne de confiance

Trois Security Groups appliquant le moindre privilège, chacun n'ouvrant que vers
le maillon suivant :

| Security Group | Entrée autorisée                         | Source          |
|----------------|------------------------------------------|-----------------|
| `alb-sg`       | HTTP (80), HTTPS (443)                    | Internet        |
| `ecs-sg`       | Trafic applicatif (8000)                 | **SG de l'ALB** |
| `rds-sg`       | PostgreSQL (5432)                        | **SG des ECS**  |

Chaîne : `Internet → ALB (443) → Tâches ECS (8000) → RDS (5432)`, et rien d'autre.
Les sources sont des **Security Groups**, pas des plages d'IP — ce qui garantit
que seul le maillon précédent peut atteindre le suivant.

## Base de données (RDS)

- PostgreSQL 16, instance `db.t3.micro`, stockage `gp3` 20 Go **chiffré au repos**.
- Placée dans les **subnets privés** via un subnet group (≥ 2 AZ, exigé par RDS).
- `publicly_accessible = false` — jamais joignable depuis Internet.
- `skip_final_snapshot = true` — cohérent avec l'infra éphémère.
- Mot de passe maître fourni hors code (variable `TF_VAR_db_password`), migré vers
  Secrets Manager au Bloc D (D.4/D.5). Le provider gère le mot de passe en
  write-only : il n'apparaît pas dans le fichier d'état.

## Cycle de vie (infra éphémère)

`terraform apply` crée les 19 ressources ; `terraform destroy` les supprime en
fin de session. Seules NAT Gateway et RDS ont un coût continu (~1 USD/jour
chacune si laissées 24 h) — d'où la discipline destroy/recreate. Le backend d'état
(S3 + verrou) et le budget restent hors de ce cycle.