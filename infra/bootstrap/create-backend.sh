#!/usr/bin/env bash
# =============================================================================
#  create-backend.sh — Backend d'état Terraform distant (bootstrap, une seule
#  fois, HORS du cycle destroy/recreate).
#
#  Crée :
#   - un bucket S3 (chiffré + versionné + accès public bloqué) pour les .tfstate
#   - une table DynamoDB pour le verrou d'état (lock)
#
#  Idempotent : relançable sans risque (ignore "déjà existant").
#  Prérequis : AWS CLI configurée (aws sts get-caller-identity doit répondre).
# =============================================================================
set -euo pipefail

# --- Paramètres (le nom du bucket S3 doit être unique au monde) ---------------
REGION="eu-west-3"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="freelancehub-tfstate-${ACCOUNT_ID}"
TABLE="freelancehub-tflock"

echo ">> Compte : ${ACCOUNT_ID} | Région : ${REGION}"
echo ">> Bucket : ${BUCKET}"
echo ">> Table  : ${TABLE}"

# --- 1. Bucket S3 -------------------------------------------------------------
if aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  echo ">> Bucket déjà présent, on continue."
else
  echo ">> Création du bucket..."
  aws s3api create-bucket \
    --bucket "${BUCKET}" \
    --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}"
fi

# Versioning : garder l'historique des états (récupération possible)
aws s3api put-bucket-versioning \
  --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled

# Chiffrement au repos (AES256)
aws s3api put-bucket-encryption \
  --bucket "${BUCKET}" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Bloquer tout accès public (un .tfstate ne doit JAMAIS être exposé)
aws s3api put-public-access-block \
  --bucket "${BUCKET}" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo ">> Bucket S3 configuré (versioning + chiffrement + accès public bloqué)."

# --- 2. Table DynamoDB (verrou) ----------------------------------------------
if aws dynamodb describe-table --table-name "${TABLE}" --region "${REGION}" >/dev/null 2>&1; then
  echo ">> Table DynamoDB déjà présente, on continue."
else
  echo ">> Création de la table de verrou..."
  aws dynamodb create-table \
    --table-name "${TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}"
  aws dynamodb wait table-exists --table-name "${TABLE}" --region "${REGION}"
fi

echo ""
echo ">> Backend prêt. À reporter dans le bloc backend Terraform du Bloc A :"
echo "-----------------------------------------------------------------------"
cat <<TF
  backend "s3" {
    bucket         = "${BUCKET}"
    key            = "global/terraform.tfstate"
    region         = "${REGION}"
    dynamodb_table = "${TABLE}"
    encrypt        = true
  }
TF
echo "-----------------------------------------------------------------------"