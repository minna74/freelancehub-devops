#!/usr/bin/env bash
# post-apply-bootstrap.sh — À lancer après chaque `terraform apply` complet.
# Remet l'application en état de marche : image sur ECR + schéma RDS migré.
set -euo pipefail

REGION="eu-west-3"
ACCOUNT_ID="890615325519"
ECR_REPO="freelancehub-api"
CLUSTER="freelancehub-cluster"

echo ">> 1. Authentification ECR"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo ">> 2. Build de l'image"
docker build -t "${ECR_REPO}:latest" ./app

echo ">> 3. Tag et push vers ECR"
docker tag "${ECR_REPO}:latest" "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO}:latest"
docker push "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO}:latest"

echo ">> 4. Récupération des infos réseau (subnets privés, SG ECS)"
PRIVATE_SUBNETS=$(cd infra && terraform output -json private_subnet_ids | jq -r '. | join(",")')
ECS_SG=$(aws ec2 describe-security-groups --region "$REGION" \
  --filters "Name=group-name,Values=freelancehub-ecs-sg" \
  --query "SecurityGroups[0].GroupId" --output text)

echo ">> 5. Lancement de la tâche de migration Alembic"
TASK_ARN=$(aws ecs run-task \
  --cluster "$CLUSTER" \
  --task-definition "$ECR_REPO" \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[${PRIVATE_SUBNETS}],securityGroups=[${ECS_SG}],assignPublicIp=DISABLED}" \
  --overrides '{"containerOverrides":[{"name":"'"$ECR_REPO"'","command":["alembic","upgrade","head"]}]}' \
  --region "$REGION" \
  --query "tasks[0].taskArn" --output text)

echo "Tâche de migration lancée : $TASK_ARN"
echo ">> 6. Attente de la fin de la migration..."
aws ecs wait tasks-stopped --cluster "$CLUSTER" --tasks "$TASK_ARN" --region "$REGION"

EXIT_CODE=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" --region "$REGION" \
  --query "tasks[0].containers[0].exitCode" --output text)

if [ "$EXIT_CODE" != "0" ]; then
  echo "ERREUR : la migration a échoué (exit code $EXIT_CODE). Vérifie les logs CloudWatch."
  exit 1
fi

echo ">> 7. Forcer le redéploiement du Service ECS avec la nouvelle image"
aws ecs update-service --cluster "$CLUSTER" --service freelancehub-service \
  --force-new-deployment --region "$REGION" > /dev/null

echo ">> Terminé. Vérifie l'app via : $(cd infra && terraform output -raw app_url)/health"
