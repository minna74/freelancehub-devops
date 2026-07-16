# ADR 0003 — Backend d'état créé par script CLI (bootstrap)

- **Statut :** accepté
- **Date :** 2026-07-07

## Contexte

Terraform doit stocker son état (`.tfstate`) dans un backend distant (S3 +
verrou DynamoDB), conformément aux bonnes pratiques et au cahier des charges.

Se pose le **paradoxe de l'œuf et de la poule** : on ne peut pas créer avec
Terraform, dans l'état principal distant, le bucket qui héberge précisément cet
état. La chaîne IaC doit être amorcée par une étape de bootstrap.

## Décision

Le backend d'état est créé par un **script AWS CLI versionné**
(`infra/bootstrap/create-backend.sh`), lancé une seule fois, hors du cycle
`destroy`/`recreate`. Le script est idempotent et applique d'emblée les
garde-fous : versioning, chiffrement au repos (AES256), blocage de tout accès
public sur le bucket ; table DynamoDB en facturation à la demande pour le verrou.

## Alternatives envisagées

- **Terraform dédié à état local** — plus « pur » (tout en Terraform), très
  répandu. Écarté ici pour rester simple et rapide ; le script CLI est tout aussi
  reproductible dès lors qu'il est versionné.
- **Terragrunt (gestion auto du backend)** — pratique à grande échelle, mais
  ajoute une couche entière hors périmètre du projet (« complexité
  disproportionnée »).

## Conséquences

- Le bootstrap est reproductible (script dans le dépôt) sans être dans l'état
  Terraform principal.
- Ces ressources ne sont jamais détruites par `terraform destroy` : elles vivent
  dans `infra/bootstrap/`, comme le garde-fou budgétaire (ADR 0001).
- Le bloc `backend "s3"` du Bloc A pointera vers ce bucket et cette table.
- Sécurité : état chiffré, versionné, jamais exposé publiquement.