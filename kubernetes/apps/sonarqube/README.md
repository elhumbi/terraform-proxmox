# SonarQube Community Build

SonarQube `26.9.0.129388-community` mit eigener PostgreSQL 17 auf `talos-worker01`,
erreichbar unter https://sonarqube.home.local (Cilium-Ingress, interne CA).

## Deploy

```bash
cd ~/git/terraform_proxmox && export KUBECONFIG=$PWD/kubeconfig

# 1) Namespace + Secret (SealedSecret, wird bewusst NICHT in der YAML verwaltet)
kubectl apply -f kubernetes/apps/sonarqube/sonarqube.yaml --dry-run=client >/dev/null   # Syntax
kubectl create namespace sonarqube --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f kubernetes/apps/sonarqube/sealed/sonarqube-db.sealed.yaml
# Neues Passwort erzeugen/rotieren: siehe kubernetes/infra/sealed-secrets/README.md

# 2) Alles andere
kubectl apply -f kubernetes/apps/sonarqube/sonarqube.yaml
kubectl -n sonarqube rollout status deploy/sonarqube --timeout=15m
```

`kubectl apply -f kubernetes/apps/sonarqube/sonarqube.yaml` ist jederzeit wiederholbar — es fasst das Secret nicht an.

## Zugriff

- `/etc/hosts`: `192.168.1.180  sonarqube.home.local` (Cilium-Ingress-IP, wie die anderen `*.home.local`)
- Erstlogin **admin / admin** → SonarQube erzwingt sofort ein neues Passwort.
- Health: `https://sonarqube.home.local/api/system/status` → `{"status":"UP"}`

## Betrieb

| Was | Wo |
|---|---|
| Daten (Elasticsearch-Index, DB-Dump nicht) | PVC `sonarqube-data-pvc` (10 Gi, StorageClass `longhorn-single` = 1 Replika) |
| Plugins | PVC `sonarqube-extensions-pvc` (2 Gi) |
| Datenbank | PVC `sonarqube-postgres-pvc` (5 Gi) — **das** ist der Backup-relevante Teil |
| Logs / Temp | emptyDir (bewusst nicht persistent) |

Backup der DB: `kubectl -n sonarqube exec deploy/sonarqube-postgres -- pg_dump -U sonar sonar | gzip > sonar-$(date +%F).sql.gz`

Ressourcen: Request 3 Gi / Limit 5 Gi RAM (Web 1 G + CE 1 G + ES 1 G Heap + Overhead), 0.5–3 CPU.
Erststart dauert 3–6 Minuten (DB-Schema anlegen, ES-Index bauen) — `startupProbe` erlaubt bis 10 min.

## Kernel-Parameter (Elasticsearch)

`vm.max_map_count>=524288` und `fs.file-max>=131072` setzt der privilegierte `sysctl`-initContainer
bei jedem Pod-Start auf dem Node; daher trägt der Namespace `pod-security.kubernetes.io/enforce: privileged`.
Sauberere Alternative, wenn der Talos-Config-Patch sowieso mal ansteht:

```yaml
machine:
  sysctls:
    vm.max_map_count: "524288"
    fs.file-max: "131072"
```

Dann initContainer + PSA-Label entfernen.

## Upgrade

Tag in `sonarqube.yaml` anheben (Docker Hub: `sonarqube:<version>-community`), `kubectl apply`, Rollout abwarten —
SonarQube migriert das DB-Schema beim Start selbst (`/setup` im Browser bestätigen, falls gefragt).
Immer nur ein Major-Sprung pro Upgrade, vorher `pg_dump`.
