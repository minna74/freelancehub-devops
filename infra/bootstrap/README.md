# infra/bootstrap/ — Ressources hors cycle éphémère

Ces ressources sont créées **une seule fois**, en dehors du cycle
`destroy`/`recreate` du Terraform principal. On ne les détruit **jamais** entre
les sessions :

- **Garde-fou budgétaire** (`budget.json` + `notifications.json`) — doit survivre
  à tous les `terraform destroy`, sinon plus de protection sur le coût.
- **Backend d'état Terraform** (bucket S3 + table DynamoDB) — ajouté au Bloc 0
  (tâche 0.3) ; par nature, l'état ne peut pas se gérer lui-même.

Décision associée :
[`../../docs/decisions/0001-budget-hors-cycle-ephemere.md`](../../docs/decisions/0001-budget-hors-cycle-ephemere.md).

## Appliquer le budget (une fois)

Éditer d'abord `notifications.json` pour remplacer l'adresse e-mail, puis :

    cd infra/bootstrap
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    aws budgets create-budget \
      --account-id "$ACCOUNT_ID" \
      --budget file://budget.json \
      --notifications-with-subscribers file://notifications.json

Vérifier ensuite dans la console : Billing and Cost Management → Budgets.
Les budgets AWS sont gratuits (les 2 premiers) ; les alertes e-mail aussi.
