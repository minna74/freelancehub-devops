# .github/workflows/ — Pipelines CI/CD (GitHub Actions)

Workflows d'intégration et de déploiement continus. Authentification à AWS via
OIDC (aucune clé d'accès stockée dans GitHub).

Étapes prévues : build → test → scan (Trivy, Checkov/tfsec) → push ECR →
déploiement ECS. Mise en place au Bloc C.
