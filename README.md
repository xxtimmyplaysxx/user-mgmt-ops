# VSC Observability - Abgabe und Betriebsanleitung

## Aktueller Status: vorbereitet, noch nicht live abgenommen

Die bestehende Plattform wird fuer die Aufgaben 1-6 erweitert. **Dieser Branch ist
noch keine vollstaendig nachgewiesene Abgabe.** Pruefung 2 ist laut Bestaetigung des
Eigentuemers abgeschlossen. Der bestehende Cluster wurde anschliessend erfolgreich
in Terraform importiert: keine Ressourcen erstellt, geaendert oder geloescht;
abschliessender Plan "No changes". Managed PostgreSQL 16 und MySQL 8.4 sowie die
beiden Datenbanken und Firewalls sind erstellt; der erneute Plan zeigt keine
Aenderungen. Die alte Staging-Datenbank wurde gesichert. Wiederherstellung,
Umschaltung und Anwendungs-Rollout stehen aus.

Die Anwendung einschliesslich des vom Lehrer bereitgestellten Module Service liegt
in https://github.com/xxtimmyplaysxx/user-mgmt-service-kubernetes unter dem
gleichnamigen Branch `codex/observability-microservices`.

| Aufgabe | Vorbereitet | Noch praktisch nachzuweisen |
|---|---|---|
| 1 Observability | Stack-values, 2 ServiceMonitors, 3 Grafana-Dashboards, PrometheusRules, Alertmanager-Webhook | Installation, Scrape-Targets, Daten in Dashboards, zugestellter Alert |
| 2 Lasttest | k6-Skript, Job und Netzwerkregeln | Testlauf, HPA scale-out und scale-in, Verfuegbarkeit und Diagramme |
| 3 IaC | Provider, generierte/bereinigte Konfiguration, Variablen, Import und No-change-Plan erfolgreich | Erledigt; State lokal erhalten |
| 4 Managed PostgreSQL | Managed DB/Firewall erstellt, Quell-Backup geprueft, Helm-Umschaltung vorbereitet | Wiederherstellen, Daten vergleichen, umstellen, alte DB/PVC entfernen |
| 5 Kyverno | Helm-values, 3 Enforce-Policies, ungueltiges Deployment | Installation und dokumentierte Admission-Ablehnung |
| 6 Microservices | REST-Client mit Resilienz, Module-Service-Image, CI, Helm, Metriken, Managed MySQL erstellt | DB-Secrets, GitOps-Rollout, E2E inkl. Fehlerfaellen und Laststabilitaet |

## Vorhandene Umgebung

- Cluster: `vsc-orchestrierung`, Frankfurt, ID `7e46ab36-b79c-4dea-8301-2a2a998822c5`.
- Staging: `user-mgmt-staging`, automatische Argo-CD-Synchronisierung von `main`.
- Production: eigener Namespace und eigene values-prod.yaml, ebenfalls Auto-Sync.
- Ein Worker mit 4 GB RAM, beobachtet am 27.09.: 2842 MiB / 94% des allocatable RAM.
- Vor Monitoring/Policies zusaetzliche Kapazitaet bereitstellen; der aktuelle Node
  hat kaum Reserve. Keine bestehende Anwendung ungeprueft entfernen.

## Reihenfolge nach Freigabe

1. Zustand und Daten sichern; Kapazitaet fuer Monitoring, Policies und Lasttest schaffen.
2. Cluster mit Terraform importieren, dabei zuerst einen reinen Import ohne
   Infrastruktur-Aenderungen erreichen. Details: terraform/README.md.
3. Managed PostgreSQL und MySQL anlegen, nur Cluster als Trusted Source zulassen.
4. Bestehende Staging-PostgreSQL-Daten sichern und migrieren. Verbindungen mit TLS
   testen. Zugangsdaten und CA-Zertifikate nur als Secrets bereitstellen.
5. Monitoring installieren. Grafana bleibt ClusterIP; Zugriff per Port-Forward.
6. Images bauen/publizieren und die Helm-Umschaltung zuerst fuer Staging aktivieren.
7. Erst nach erfolgreichem Datenvergleich und Anwendungscheck alte DB/PVC entfernen.
8. Kyverno installieren; Policies erst fuer migrierte, konforme Namespaces aktivieren.
9. E2E, Lasttest, HPA, Fehlerzustand und Alert-Zustellung nachweisen.
10. Ergebnisse mit Datum, Commit-SHA und Befehlsausgaben in evidence/ dokumentieren.

## Monitoring

```powershell
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack --version 91.7.0 -n monitoring --create-namespace -f monitoring/values.yaml --wait --timeout 10m
kubectl apply -f monitoring/alert-receiver.yaml
kubectl apply -f monitoring/vsc-infrastructure.yaml -f monitoring/vsc-user-service.yaml -f monitoring/vsc-module-service.yaml
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
```

Der konfigurierte Benachrichtigungskanal ist ein interner HTTP-Webhook, dessen
Empfang mit `kubectl -n monitoring logs deploy/alert-receiver` nachgewiesen wird.
Dies ist keine E-Mail-/Chat-Benachrichtigung. Falls eine solche verlangt wird,
einen autorisierten Empfaenger ueber ein Secret konfigurieren.
Die lokalen Receiver-Logs sind nicht dauerhaft: Nachweise nach dem Test sichern.
CPU/Memory-Dashboard sowie separate RED-Dashboards fuer User- und Module-Service.

## Managed-Datenbank-Umschaltung

`managedDatabase.enabled=true` laedt `user-mgmt-managed-postgres` nach dem bisherigen
Secret. Es enthaelt `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`,
`SPRING_DATASOURCE_PASSWORD` und `ca.crt`. Die URL nutzt
`sslmode=verify-full&sslrootcert=/etc/postgres-tls/ca.crt`.
Das Module-Secret `user-mgmt-module-db` enthaelt `DATABASE_URL` und `ca.crt`.
Die SQLAlchemy-URL muss Sonderzeichen im Passwort URL-kodieren.

`managedDatabase.cidr` und `module.databaseCidr` werden mit den privaten DB-IP-/32
gesetzt. Bei einem IP-Wechsel muessen diese Netzwerkregeln aktualisiert werden.
Backend hat nur PostgreSQL-Egress und HTTP zum Module-Service, keinen MySQL-Egress.

Umschaltung in values-staging.yaml erst wenn Datenbanken, Secrets und Images bereit
sind: `managedDatabase.enabled=true`, `module.enabled=true`, `monitoring.enabled=true`.
`postgres.enabled=false` entfernt Deployment, Service und PVC aus dem Chart.
**Argo CD prune kann dann Datenvolumes loeschen: erst Backup und Migration pruefen.**
Production wird separat migriert; gemeinsame Templates bleiben standardmaessig
abwaertskompatibel (postgres an, neue Funktionen aus).

## Policies

```powershell
helm repo add kyverno https://kyverno.github.io/kyverno/
helm upgrade --install kyverno kyverno/kyverno --version 3.9.1 -n policy --create-namespace -f policy/values.yaml --wait --timeout 10m
kubectl apply -f policy/policies.yaml
kubectl label namespace user-mgmt-staging vsc-policies=enforce --overwrite
kubectl apply --dry-run=server -f policy/invalid-deployment.yaml
```

Die letzte Zeile MUSS abgelehnt werden. Drei Policies verlangen Requests/Limits,
Non-root ohne Privilege Escalation und explizite Image-Tags statt latest.
Kyverno erzeugt Controller-Regeln aus den Pod-Regeln. Die Namespace-Selektion
verhindert, dass die Kursregeln Systemkomponenten oder alte Umgebungen blockieren.

## Lasttest und Nachweise

Erst einen separaten Testbenutzer registrieren. Seine Zugangsdaten als
`loadtest-credentials` mit `TEST_EMAIL` und `TEST_PASSWORD` anlegen.

```powershell
kubectl -n user-mgmt-staging create configmap user-mgmt-loadtest --from-file=test.js=loadtest/test.js --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f loadtest/job.yaml
kubectl -n user-mgmt-staging logs -f job/user-mgmt-loadtest
kubectl -n user-mgmt-staging get hpa,pods -w
```

Das Skript lastet den Login als echten API-Endpunkt aus: 2 -> 10 -> 20 -> 0 VUs.
Es prueft erfolgreiche Logins, <1% HTTP-Fehler und P95 <3 Sekunden.
HPA-Ausgangswert, Maximum und Rueckgang zeitgestempelt festhalten, ebenso k6-Ergebnis
und Grafana-Zeitraum. Lasthoehe nur anhand der Beobachtung anpassen. Ein vorhandenes
Skript allein belegt noch keine erfolgreiche Skalierung.

## Lokale Validierung

```powershell
helm lint charts/user-mgmt -f charts/user-mgmt/values-staging.yaml
helm lint charts/user-mgmt -f charts/user-mgmt/values-prod.yaml
terraform -chdir=terraform fmt -check -recursive
```

GitHub Actions prueft zusaetzlich die gerenderte Managed-Variante auf fehlende lokale
DB/PVC, Ressourcenlimits, Sicherheitskontexte und Monitoring-Objekte.
Vollstaendiges `terraform validate` ist nach der Config-Generierung erforderlich.

## Geheimnisse

Keine Tokens, Passwoerter, kubeconfigs, State-Dateien, Plaene oder DB-Dumps committen.
Lokaler State enthaelt Geheimnisse; .gitignore ersetzt keinen Zugriffsschutz.
Die Provider-Lockdatei dagegen gehoert ins Repository.
