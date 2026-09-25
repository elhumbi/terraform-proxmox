# Sealed Secrets

Secrets werden verschlüsselt als `*.sealed.yaml` im Repo versioniert. Nur der
Controller im Cluster besitzt den privaten Schlüssel und legt daraus die echten
`Secret`-Objekte an. Klartext-Secrets gehören **nie** ins Repo.

## Controller installieren

```bash
export KUBECONFIG=$PWD/kubeconfig
# Chart liegt als OCI-Artefakt vor (die alte Helm-Repo-URL ist tot).
# Bei "docker-credential-desktop not found": DOCKER_CONFIG=/tmp/empty voranstellen.
helm upgrade --install sealed-secrets oci://registry-1.docker.io/bitnamicharts/sealed-secrets \
  --version 2.20.0 -n kube-system -f kubernetes/infra/sealed-secrets/values.yaml --wait

# kubeseal CLI (macOS): brew install kubeseal  – oder Binary nach .bin/:
#   https://github.com/bitnami/sealed-secrets/releases (kubeseal-<ver>-darwin-<arch>.tar.gz)
```

Danach das öffentliche Zertifikat holen und einchecken (ist öffentlich, kein Secret):

```bash
kubeseal --controller-name sealed-secrets-controller --controller-namespace kube-system \
  --fetch-cert > kubernetes/infra/sealed-secrets/pub-cert.pem
```

## Secret versiegeln

```bash
CERT=kubernetes/infra/sealed-secrets/pub-cert.pem

# aus Literalen
kubectl create secret generic grafana-admin-secret -n monitoring --dry-run=client -o json \
  --from-literal=admin-user=admin --from-literal=admin-password="$(openssl rand -base64 24)" \
  | kubeseal --cert $CERT --format yaml > kubernetes/monitoring/sealed/grafana-admin-secret.sealed.yaml

# aus einer Datei (z.B. .env)
kubectl create secret generic lightrag-env -n ai-tools --dry-run=client -o json \
  --from-file=.env=./lightrag.env \
  | kubeseal --cert $CERT --format yaml > kubernetes/apps/ai-tools/sealed/lightrag-env.sealed.yaml

# bestehendes Cluster-Secret nachträglich versiegeln
kubectl get secret <name> -n <ns> -o json \
  | kubeseal --cert $CERT --format yaml > <pfad>/<name>.sealed.yaml
```

Die Verschlüsselung ist an **Name + Namespace** gebunden (Scope `strict`). Umbenennen
oder in einen anderen Namespace verschieben heisst neu versiegeln.

## Anwenden

```bash
kubectl apply -f kubernetes/monitoring/sealed/
kubectl get sealedsecrets -A          # SYNCED muss True sein
```

Ein Secret, das schon vorher von Hand existierte, übernimmt der Controller nur mit
der Annotation `sealedsecrets.bitnami.com/managed=true` auf dem alten Secret.

## Konvention

| Ort | Inhalt |
|---|---|
| `kubernetes/**/sealed/<name>.sealed.yaml` | ein SealedSecret pro Datei, Dateiname = Secret-Name |
| `kubernetes/infra/sealed-secrets/pub-cert.pem` | öffentliches Zertifikat des Controllers |
| `.gitignore` | `!*.sealed.yaml` überschreibt die `*secret*`-Regel |

Aktuell versiegelt: `grafana-admin-secret` (monitoring), `litellm-api-keys`,
`litellm-db-secret`, `litellm-prometheus-token`, `open-webui-secret`, `searxng-secret`,
`lightrag-env` (ai-tools), `sonarqube-db` (sonarqube), `newt-cred` (newt),
`ragflow-secrets`, `ragflow-config` (ragflow, nicht deployed).

## Private Key sichern (Pflicht)

Ohne den Key sind alle `*.sealed.yaml` nach einem Cluster-Neuaufbau wertlos.

```bash
kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml \
  > backups/sealed-secrets-key-$(date +%Y%m%d).yaml     # backups/ ist gitignored
```

Backup zusätzlich ausserhalb des Repos ablegen (Passwort-Manager, verschlüsselter USB-Stick).
Restore auf neuem Cluster: Key-Secret **vor** dem Controller-Install anlegen, dann
`kubectl -n kube-system rollout restart deploy/sealed-secrets-controller`.

Der Controller rotiert den Key alle 30 Tage (alte Keys bleiben zum Entschlüsseln erhalten),
daher das Backup nach Rotation wiederholen – das Label erfasst alle Keys.
