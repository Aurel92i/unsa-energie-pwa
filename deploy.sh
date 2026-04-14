#!/bin/bash
# ============================================================
# Script de déploiement — UNSA Énergie PWA → GitHub Pages
# Usage : ./deploy.sh
# Prérequis : git, gh (GitHub CLI) installé et authentifié
# ============================================================

set -e

REPO_NAME="unsa-energie-pwa"
BRANCH="main"

echo "🚀 Déploiement UNSA Énergie PWA sur GitHub Pages"
echo "================================================="

# 1. Vérifier que gh est installé et authentifié
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) n'est pas installé."
    echo "   Installe-le : https://cli.github.com/"
    exit 1
fi

if ! gh auth status &> /dev/null; then
    echo "❌ Tu n'es pas connecté à GitHub CLI."
    echo "   Lance : gh auth login"
    exit 1
fi

GITHUB_USER=$(gh api user --jq '.login')
echo "✅ Connecté en tant que : $GITHUB_USER"

# 2. Initialiser le repo git local
cd "$(dirname "$0")"
echo ""
echo "📁 Dossier : $(pwd)"

if [ ! -d ".git" ]; then
    git init -b main
    echo "✅ Repo git initialisé"
else
    echo "✅ Repo git déjà initialisé"
fi

# 3. Créer le repo GitHub s'il n'existe pas
if gh repo view "$GITHUB_USER/$REPO_NAME" &> /dev/null; then
    echo "✅ Le repo $GITHUB_USER/$REPO_NAME existe déjà"
else
    echo "📦 Création du repo GitHub : $REPO_NAME"
    gh repo create "$REPO_NAME" --public --description "UNSA Énergie — Île et Armor — Progressive Web App" --confirm
    echo "✅ Repo créé"
fi

# 4. Ajouter le remote
REMOTE_URL="https://github.com/$GITHUB_USER/$REPO_NAME.git"
if git remote get-url origin &> /dev/null; then
    git remote set-url origin "$REMOTE_URL"
else
    git remote add origin "$REMOTE_URL"
fi
echo "✅ Remote configuré : $REMOTE_URL"

# 5. Ajouter tous les fichiers (sauf ce script et .git)
git add index.html admin.html manifest.json sw.js logo.png favicon.png icons/
echo "✅ Fichiers ajoutés au staging"

# 6. Commit et push
git commit -m "🚀 Déploiement initial — UNSA Énergie PWA" || echo "ℹ️  Rien de nouveau à committer"
git push -u origin "$BRANCH" --force
echo "✅ Code poussé sur GitHub"

# 7. Activer GitHub Pages
echo ""
echo "🌐 Activation de GitHub Pages..."
gh api -X PUT "repos/$GITHUB_USER/$REPO_NAME/pages" \
    --input - <<EOF 2>/dev/null || \
gh api -X POST "repos/$GITHUB_USER/$REPO_NAME/pages" \
    --input - <<EOF2
{
  "build_type": "legacy",
  "source": {
    "branch": "main",
    "path": "/"
  }
}
EOF
{
  "build_type": "legacy",
  "source": {
    "branch": "main",
    "path": "/"
  }
}
EOF2

echo "✅ GitHub Pages activé"

# 8. Afficher l'URL finale
PAGES_URL="https://$GITHUB_USER.github.io/$REPO_NAME/"
echo ""
echo "================================================="
echo "🎉 Déploiement terminé !"
echo ""
echo "📱 URL du site : $PAGES_URL"
echo ""
echo "⏳ GitHub Pages peut prendre 1-2 minutes pour"
echo "   être disponible après le premier déploiement."
echo "================================================="
