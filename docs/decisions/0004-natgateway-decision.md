# ADR 0004 — Sortie Internet des tâches ECS via NAT Gateway

- **Statut :** accepté
- **Date :** 2026-07-11

## Contexte

Les tâches ECS Fargate vivent en subnet privé (elles ne doivent jamais être
joignables depuis Internet). Elles ont pourtant besoin d'un accès **sortant** :
tirer l'image depuis ECR, lire des secrets (Secrets Manager), pousser des logs
(CloudWatch). Il faut donc router ce trafic sortant.

## Décision

**NAT Gateway** (option a). Une **NAT unique** est placée dans un subnet public ;
les route tables des subnets privés y envoient le trafic `0.0.0.0/0`. Cela impose
d'écrire à la fois une route table publique (vers l'IGW) et une route table privée
(vers la NAT) — topologie de référence attendue par un relecteur.

## Alternatives envisagées

- **(b) Fargate en subnet public** (`assign_public_ip=true`, pas de NAT) — gratuit,
  mais tâches avec IP publique (moins « pur »). Écarté pour privilégier la
  démonstration de la topologie standard.
- **(c) VPC Endpoints** (ECR, S3, CloudWatch…) — pas de sortie Internet, le plus
  sécurisé, mais alourdit sensiblement le Terraform. Écarté pour la lisibilité.

## Conséquences

- **Coût :** la NAT Gateway est facturée dès qu'elle existe (~1 USD/jour + trafic).
  C'est le **poste de coût n°1** du projet → détruite systématiquement en fin de
  session (discipline d'infra éphémère).
- **NAT unique** (et non une par AZ) : point de défaillance unique **assumé** pour
  une démo ; en production on en mettrait une par AZ.
- Impose route table publique (A.3) + route table privée vers la NAT (A.4).
