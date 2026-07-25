 CI/CD — FreelanceHub

## Vue d'ensemble

Le projet utilise **deux workflows GitHub Actions distincts**, chacun avec un rôle IAM dédié, authentifiés via **OIDC** (aucune clé AWS statique stockée dans GitHub).

| Workflow | Fichier | Déclencheur | Rôle IAM utilisé | Peut modifier AWS ? |
|---|---|---|---|---|
| Build & Push to ECR | `.github/workflows/deploy.yml` | Push sur `main` (`app/**`), ou manuel | `freelancehub-github-actions-role` | Oui — ECR + ECS uniquement |
| Terraform Plan (PR) | `.github/workflows/terraform-plan.yml` | Pull request touchant `infra/**` | `freelancehub-github-actions-plan-role` | **Non** — lecture seule |

## Pourquoi deux rôles IAM séparés

C'est le cœur de la posture de sécurité du pipeline, et un choix assumé (voir ADR 0006, à formaliser). Deux exigences contradictoires devaient être conciliées :

- Terraform a besoin de **lire** l'ensemble de l'infrastructure (VPC, RDS, ECS, IAM...) pour produire un `plan` fiable sur une pull request — y compris venant d'une branche quelconque.
- Aucun code exécuté sur une simple pull request ne doit jamais pouvoir **modifier** quoi que ce soit sur AWS, même en cas de bug de workflow ou de PR malveillante.

La solution retenue, conforme aux pratiques standards des équipes DevOps matures : **séparer complètement l'identité "lecture" de l'identité "écriture"**, chacune avec sa propre trust policy OIDC et ses propres permissions IAM.

### `freelancehub-github-actions-role` (déploiement applicatif)

- **Trust policy** : n'autorise que la branche `main` du dépôt (`sub: repo:.../ref:refs/heads/main`)
- **Permissions** : ECR (`PutImage`, `BatchCheckLayerAvailability`...), ECS (`RegisterTaskDefinition`, `UpdateService`, `DescribeServices`...), `iam:PassRole` limité au rôle d'exécution ECS
- **Ce qu'il ne peut PAS faire** : toucher au réseau, à RDS, ou à IAM au sens large — le déploiement applicatif reste strictement borné au cycle build/push/déploiement de conteneur

### `freelancehub-github-actions-plan-role` (audit read-only)

- **Trust policy** : autorise **toutes** les branches et pull requests du dépôt (nécessaire, une PR peut venir de n'importe où)
- **Permissions** : uniquement des actions `Describe*`/`Get*`/`List*` sur EC2, RDS, ECS, ECR, ALB, IAM, CloudWatch, plus un accès **limité et ciblé** au bucket S3 du state (lecture du `.tfstate`, écriture/suppression **uniquement** sur le fichier de verrou `*.tflock` — jamais sur l'état lui-même)
- **Garantie** : même si ce rôle était compromis ou mal utilisé, il ne peut **techniquement rien modifier** sur AWS — la limitation est appliquée par IAM, pas par convention

## Conséquence assumée : l'infra reste en `apply` manuel

Ce choix de moindre privilège strict a une implication directe, documentée ici pour être transparent : **le `terraform apply` du réseau/RDS/IAM n'est jamais automatisé par le pipeline** — il continue à être exécuté manuellement depuis un poste de travail, comme pour les Blocs A et B.

Seul le **cycle applicatif** (build → test → push → déploiement ECS) est intégralement automatisé de bout en bout à chaque push sur `main`. C'est un compromis pragmatique : le réseau et la base de données changent rarement une fois posés, alors que le code applicatif change à chaque itération — c'est donc lui qui bénéficie le plus de l'automatisation.

## Le workflow `deploy.yml` en détail

push sur main (app/**)
│
▼
┌───────────────┐
│ Job: test │ PostgreSQL éphémère + pytest --cov
└───────┬───────┘
│ (needs: test — bloque tout si échec)
▼
┌────────────────────┐
│ Job: build-and-push │
│ 1. Auth OIDC │
│ 2. docker build │
│ 3. docker push │ (tags: SHA du commit + latest)
│ 4. Nouvelle révision│
│ Task Definition │
│ 5. Déploiement ECS │ (attend la stabilité)
└─────────────────────┘


### Job `test`

Lance un conteneur PostgreSQL 16 éphémère (`services:`), isolé et détruit automatiquement en fin de job. Les identifiants (`freelancehub`/`freelancehub_dev`/`freelancehub_test`) sont alignés avec `tests/conftest.py`, qui crée et détruit le schéma complet avant/après chaque test. Les variables `DB_URL`/`SECRET_KEY` sont fournies uniquement pour permettre à l'application de démarrer (validation Pydantic) — elles ne pointent jamais vers l'infrastructure réelle.

### Job `build-and-push`

Ne démarre que si `test` réussit. Deux tags sont poussés vers ECR : le SHA du commit (traçabilité exacte) et `latest` (usage pratique). Le déploiement récupère la Task Definition active, en modifie uniquement le champ `image` via l'action officielle `amazon-ecs-render-task-definition`, puis enregistre une **nouvelle révision** et met à jour le Service ECS — jamais de redéploiement basé sur un tag mutable comme `latest` seul.

## Le workflow `terraform-plan.yml` en détail

Se déclenche sur toute pull request touchant `infra/**`. Poste le résultat du `terraform plan` en commentaire directement sur la PR, permettant une revue de l'impact avant merge, sans jamais pouvoir appliquer quoi que ce soit.

## Secrets et variables GitHub requis

| Nom | Type | Usage |
|---|---|---|
| `DB_PASSWORD` | Secret | Mot de passe RDS, utilisé par `terraform plan` (job lecture seule) |

Aucune clé d'accès AWS (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`) n'est stockée — l'authentification passe exclusivement par OIDC.

## Pièges rencontrés et résolus

Pour la traçabilité et l'apprentissage — ces erreurs ont façonné la policy IAM finale, chacune corrigée précisément à partir du message d'erreur réel plutôt que devinée à l'avance :

- **Format du `sub` claim OIDC** : GitHub insère des identifiants numériques stables (`repo:user@id/repo@id:ref:...`) plutôt que les noms seuls — la trust policy doit matcher ce format exact.
- **Verrouillage d'état natif S3** (`use_lockfile`) : même un `plan` en lecture seule doit pouvoir écrire/supprimer le fichier `.tflock` (mais jamais le `.tfstate` lui-même).
- **`ecr:GetLifecyclePolicy`** : action ECR à part, non couverte par `ecr:Describe*`/`ecr:List*`, à ajouter explicitement.

## Reproduire ce pipeline

1. Créer le fournisseur OIDC et les deux rôles IAM via Terraform (`infra/modules/compute/oidc.tf`)
2. Créer le secret GitHub `DB_PASSWORD`
3. Adapter les ARN de rôles dans les deux fichiers `.github/workflows/*.yml`
4. Pousser sur `main` (déclenche `deploy.yml`) ou ouvrir une PR touchant `infra/` (déclenche `terraform-plan.yml`)
