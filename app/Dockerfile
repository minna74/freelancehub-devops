# =============================================================================
#  Étape 1/2 — "builder" : installe les dépendances Python.
#  Cette étape sera jetée à la fin — seuls les paquets installés en survivent.
# =============================================================================
FROM python:3.12-slim AS builder

WORKDIR /app

# Installées séparément du code applicatif : si seul le code change (pas les
# dépendances), Docker réutilise le cache de cette couche -> builds plus rapides.
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# =============================================================================
#  Étape 2/2 — image finale : légère, sans outils de build.
# =============================================================================
FROM python:3.12-slim

WORKDIR /app

# Récupère UNIQUEMENT les paquets déjà installés (pas les caches ni compilateurs
# utilisés pour les installer).
COPY --from=builder /install /usr/local

# Utilisateur non-root dédié à l'application (bonne pratique sécurité).
RUN useradd --create-home --shell /bin/bash appuser
COPY --chown=appuser:appuser . .
USER appuser

EXPOSE 8000

# Pas de --reload : c'est une option de DÉVELOPPEMENT, à bannir en production.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]