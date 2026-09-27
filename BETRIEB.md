# Betrieb

Alle Befehle werden aus dem Ops-Repository ausgeführt. Der Kubernetes-Kontext
ist `do-fra1-vsc-orchestrierung`. Die Dienste sind bereits installiert;
Installationsbefehle dienen zur Wiederholung mit den versionierten Werten.

## Status prüfen

```powershell
kubectl --context do-fra1-vsc-orchestrierung -n argocd get applications
kubectl --context do-fra1-vsc-orchestrierung -n user-mgmt-staging get deployments,pods,hpa
kubectl --context do-fra1-vsc-orchestrierung -n monitoring get pods
kubectl --context do-fra1-vsc-orchestrierung get clusterpolicies
```

## Monitoring

```powershell
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack --version 91.7.0 --kube-context do-fra1-vsc-orchestrierung -n monitoring --create-namespace -f monitoring/values.yaml --wait --timeout 10m
kubectl --context do-fra1-vsc-orchestrierung apply -f monitoring/alert-receiver.yaml
kubectl --context do-fra1-vsc-orchestrierung apply -f monitoring/vsc-infrastructure.yaml -f monitoring/vsc-user-service.yaml -f monitoring/vsc-module-service.yaml
```

Grafana öffnen:

```powershell
kubectl --context do-fra1-vsc-orchestrierung -n monitoring port-forward svc/monitoring-grafana 3000:80
```

Danach ist Grafana unter `http://localhost:3000` erreichbar. Die Anmeldung verwendet
das Kubernetes Secret `monitoring-grafana`. Das Terminal mit dem Port-Forward bleibt offen.

Die Dashboards heissen **VSC – Kubernetes CPU, Memory and HPA**,
**VSC – User Service RED** und **VSC – Module Service RED**.
Alertmanager sendet an den internen HTTP-Webhook `alert-receiver`.
Die empfangenen Meldungen lassen sich so prüfen:

```powershell
kubectl --context do-fra1-vsc-orchestrierung -n monitoring logs deploy/alert-receiver --since=30m --timestamps
```

Messhistorie und Receiver-Logs sind nicht dauerhaft gespeichert. Die Testauswertung
liegt deshalb mit Rohdaten im Verzeichnis `evidence/`.

## Datenbanken

Terraform verwaltet Managed PostgreSQL und MySQL sowie ihre Firewalls.
Nur der Kubernetes-Cluster ist als Trusted Source eingetragen.

`scripts/Prepare-ManagedDatabaseSecrets.ps1` liest die Verbindungsdaten über die
DigitalOcean-API und überträgt sie als Secrets nach Staging.
Es benötigt eine eingerichtete doctl-Anmeldung. Passwörter werden weder ausgegeben
noch als lokale Datei gespeichert.

| Secret | Verwendung |
|---|---|
| `user-mgmt-managed-postgres` | JDBC-URL, Benutzer, Passwort und CA für das Backend |
| `user-mgmt-module-db` | SQLAlchemy-URL und CA für den Module-Service |

PostgreSQL verwendet `sslmode=verify-full`; MySQL prüft Zertifikat und Hostnamen.
Die privaten Datenbankadressen stehen als /32-Netze in `managedDatabase.cidr`
und `module.databaseCidr`. Bei einer Adressänderung müssen die Netzwerkregeln
angepasst werden.

Die Migration ist abgeschlossen. Der [Migrationsablauf](evidence/postgres-cutover-runbook.md)
und der [Datenvergleich](evidence/postgres-final-copy.md) dokumentieren die Durchführung.
Den Restore nicht erneut auf das bereits verwendete Ziel ausführen.
Eine reine Verbindungsprüfung erfolgt mit:

```powershell
.\scripts\Test-ManagedPostgresConnection.ps1
```

## Kyverno

```powershell
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm upgrade --install kyverno kyverno/kyverno --version 3.9.1 --kube-context do-fra1-vsc-orchestrierung -n policy --create-namespace -f policy/values.yaml --wait --timeout 10m
kubectl --context do-fra1-vsc-orchestrierung apply -f policy/policies.yaml
kubectl --context do-fra1-vsc-orchestrierung label namespace user-mgmt-staging vsc-policies=enforce --overwrite
kubectl --context do-fra1-vsc-orchestrierung apply --dry-run=server -f policy/invalid-deployment.yaml
```

Der letzte Befehl muss durch die Policies abgelehnt werden.
`python scripts/verify-policies.py` führt zwölf Gegenproben als Server-Dry-Run aus.

## Lasttest wiederholen

Das Vorbereitungsskript erstellt einen Testbenutzer sowie Secret und ConfigMap.
Ein bereits vorhandener Job muss erst ausgewertet und danach gezielt entfernt werden.

```powershell
.\scripts\Prepare-StagingLoadTest.ps1
kubectl --context do-fra1-vsc-orchestrierung apply -f loadtest/job.yaml
kubectl --context do-fra1-vsc-orchestrierung -n user-mgmt-staging wait job/user-mgmt-loadtest "--for=jsonpath={.status.ready}=1" --timeout=120s
kubectl --context do-fra1-vsc-orchestrierung -n user-mgmt-staging logs -f job/user-mgmt-loadtest
```

In einem zweiten Terminal:

```powershell
kubectl --context do-fra1-vsc-orchestrierung -n user-mgmt-staging get hpa -w
```

Das Lastprofil dauert fünf Minuten und steigt auf 20 virtuelle Benutzer.
Grenzwerte: mehr als 99 % erfolgreiche Logins, weniger als 1 % HTTP-Fehler,
P95 unter drei Sekunden. Vor dem Start eine stabile Ausgangslage mit einer
Backend-Replika abwarten und nach dem Test auch die Rückskalierung erfassen.
Messwerte und Logs vor Ablauf der Job-TTL sichern.

Der separate [Module-Ausfalltest](evidence/module-resilience.md#wiederholen)
unterbricht vorübergehend die Verbindung zwischen User- und Module-Service.
