# ADR 0001 — Le garde-fou budgétaire vit hors du cycle éphémère

- **Statut :** accepté
- **Date :** 2026-07-07

## Contexte

Le projet impose deux contraintes qui se percutent :
- infrastructure **éphémère** : on lance `terraform destroy` entre les sessions
  pour ne rien laisser tourner (NAT Gateway, ALB) et tenir le budget de 15 USD ;
- critère de réussite : « tout en code, aucune ressource créée manuellement ».

Si l'alarme de budget était définie dans le Terraform principal, chaque
`terraform destroy` la supprimerait — on se retrouverait sans garde-fou au pire
moment.

## Décision

Le budget AWS est créé **une seule fois**, en dehors du cycle Terraform éphémère,
et n'est **jamais** détruit. Sa définition est versionnée dans `infra/bootstrap/`
(`budget.json` + `notifications.json`) et appliquée via l'AWS CLI (ou, à défaut,
la console). Le backend d'état (tâche 0.3) relève de la même logique « bootstrap ».

## Alternatives envisagées

- **Budget dans le Terraform principal** — rejeté : détruit à chaque `destroy`.
- **Budget dans un second état Terraform jamais détruit** — possible, mais
  complexité disproportionnée pour une ressource unique. La définition JSON
  versionnée + commande CLI reste reproductible sans ce surcoût.

## Conséquences

- Garde-fou permanent, indépendant du cycle de vie de l'infra.
- Entorse assumée et documentée au « 100 % dans le Terraform principal ».
- La reproductibilité est préservée : la définition est dans le dépôt.
