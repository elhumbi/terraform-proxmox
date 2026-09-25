#!/bin/bash
# Authentik 2025.10.2 - Minimales Helm Deployment
# Talos + Cilium + Longhorn

set -e

NAMESPACE="authentik"
RELEASE_NAME="authentik"
CHART_VERSION="2025.10.2"
VALUES_FILE="${1:-$(dirname "$0")/values.yaml}"

echo "=== Authentik 2025.10.2 Deployment ==="

# 1. Namespace
echo "[1/4] Namespace wird erstellt..."
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# 2. Helm Repo
echo "[2/4] Helm Repository wird hinzugefügt..."
helm repo add authentik https://charts.goauthentik.io
helm repo update

# 3. Secrets validieren
echo "[3/4] Values validieren..."
if grep -q "CHANGE_ME" ${VALUES_FILE}; then
    echo "❌ FEHLER: Bitte CHANGE_ME Platzhalter in ${VALUES_FILE} ausfüllen:"
    grep "CHANGE_ME" ${VALUES_FILE}
    exit 1
fi

# 4. Deploy
echo "[4/4] Deploye Authentik..."
helm upgrade --install ${RELEASE_NAME} authentik/authentik \
    --namespace ${NAMESPACE} \
    --version ${CHART_VERSION} \
    --values ${VALUES_FILE} \
    --wait \
    --timeout 5m

echo ""
echo "✅ Deployment erfolgreich!"
echo ""
echo "=== Nächste Schritte ==="
echo ""
echo "1. Port-Forward:"
echo "   kubectl port-forward -n ${NAMESPACE} svc/${RELEASE_NAME} 9000:80"
echo ""
echo "2. Browser öffnen (WICHTIG: Trailing Slash!):"
echo "   http://localhost:9000/if/flow/initial-setup/"
echo ""
echo "3. Admin-UI nach Setup:"
echo "   https://auth.home.local/admin/"
echo ""
echo "=== Pod Status ==="
kubectl get pods -n ${NAMESPACE}