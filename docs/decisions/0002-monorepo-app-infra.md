# ADR 0002 — Monorepo : l'application et l'infrastructure dans un seul dépôt

- **Statut :** accepté
- **Date :** 2026-07-07

## Contexte

L'application FreelanceHub était déjà développée, testée (93 % de couverture) et
hébergée dans son propre dépôt Git (`freelancehub-api`). Le projet d'infrastructure
devait décider comment s'articuler avec elle : un seul dépôt (monorepo) ou deux
dépôts séparés (app / infra).

Contraintes pesant sur le choix :
- cible = relecteurs techniques : un tiers doit pouvoir comprendre et reproduire
  le projet facilement ;
- délai court (20 jours) et Bloc C (CI/CD + OIDC) déjà identifié comme le plus
  piégeux ;
- l'authentification OIDC GitHub→AWS fait confiance à un dépôt précis (claim
  `sub`), donc le nombre de dépôts impacte directement la configuration.

## Décision

**Monorepo.** L'application est importée dans le dossier `app/` du dépôt
d'infrastructure via `git subtree ... --squash` (historique condensé, dépôt d'app
d'origine conservé intact de son côté). Le dépôt du projet contient désormais :
`app/` (code + `alembic/` + `tests/` + `Dockerfile` + `requirements.txt`),
`infra/` (Terraform), `.github/workflows/` (CI/CD) et `docs/`.

## Alternatives envisagées

- **Deux dépôts séparés (app / infra)** — plus proche d'une séparation
  app/plateforme en production, mais impose au relecteur de consulter deux dépôts
  et de configurer l'OIDC pour deux `sub` distincts (surface d'erreur accrue,
  précisément sur le bloc le plus fragile). Rejeté pour un projet de démonstration
  solo sous contrainte de temps.
- **Sous-module Git** — préserve la séparation mais ajoute une friction connue
  (checkout récursif, commits épinglés) peu justifiée ici. Rejeté.

## Conséquences

- Un seul `git clone` donne toute l'histoire : app + Terraform + pipeline.
- CI/CD simplifié : un seul workflow, un seul rôle OIDC (un seul dépôt de confiance).
- Le contexte de build Docker devient `app/` ; le `Dockerfile` y reste (adaptation
  multi-stage au Bloc B.2).
- Deux `README` (racine = projet infra, `app/README.md` = application réutilisée)
  et deux `docker-compose.yml` coexistent sans collision ; à clarifier dans le
  README racine au Bloc H.
- Vérifié à l'import : aucun secret suivi (`app/.env` absent, seul `.env.example`
  présent).