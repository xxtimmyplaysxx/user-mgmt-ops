# VSC Observability - Abgabe und Betriebsanleitung

## Aktueller Status: Aufgaben 1-6 live nachgewiesen

Stand **27.09.2026, 17:49 Uhr Europe/Zurich**. Die dokumentierten technischen
Pruefungen sind bestanden. Staging und Production sind in Argo CD Synced/Healthy;
alle drei Staging-Deployments sind Ready. Die Bewertung und muendliche Abnahme
erfolgen durch die Lehrperson.

Die Abgabe besteht aus zwei Repositories:

- [Application: Java, Frontend und Module-Service](https://github.com/xxtimmyplaysxx/user-mgmt-service-kubernetes)
- [Ops: Terraform, Helm, Argo CD, Monitoring, Policies und Nachweise](https://github.com/xxtimmyplaysxx/user-mgmt-ops)

| Aufgabe | Ergebnis | Nachweis |
|---|---|---|
| 1 Observability | Stack, drei Dashboards und zehn Abfragen mit echten Daten; Alarm und Entwarnung zugestellt | [Monitoring](evidence/monitoring-installation.md), [Alert](evidence/alert-delivery.md), [Dashboard-Abfragen](evidence/loadtest-passed.md) |
| 2 Lasttest | 3282/3282 Logins, P95 1.06 s, keine HTTP-Fehler; HPA 1 -> 2 -> 1, keine Backend-Neustarts | [Test, Rohdaten und Kurven](evidence/loadtest-passed.md) |
| 3 IaC | Bestehenden Cluster importiert, Konfiguration bereinigt, Variablen und No-change-Plan | [Terraform](terraform/README.md) |
| 4 Managed PostgreSQL | Backup, Vergleich, TLS, Umschaltung, E2E und Entfernung der alten Staging-DB samt Volume; ANALYZE nachgeholt | [Datenabgleich](evidence/postgres-final-copy.md), [Ablauf](evidence/postgres-cutover-runbook.md) |
| 5 Kyverno | Drei Enforce-Policies und zwoelf Live-Gegenproben bestanden | [Admission](evidence/kyverno-admission.md) |
| 6 Microservices | REST-Zuweisung, Managed MySQL/TLS, CI/GitOps, Metriken, sechs E2E-Faelle und kontrollierter Netzwerkausfall mit Erholung | [Rollout](evidence/module-rollout.md), [Resilienz](evidence/module-resilience.md) |

[Chronologie und Nachweisstatus](evidence/STATUS.md).
Die frueheren Fehler sind nachvollziehbar dokumentiert: [erster Lasttest](evidence/loadtest-first-run.md)
und [fehlende Planerstatistiken nach Restore](evidence/module-resilience.md).
Die Nachweise gelten fuer das angegebene Testprofil und die angegebenen Images;
sie ersetzen keine allgemeine Verfuegbarkeits- oder Kapazitaetsgarantie.

## Vorhandene Umgebung

- Cluster: `vsc-orchestrierung`, Frankfurt, ID `7e46ab36-b79c-4dea-8301-2a2a998822c5`.
- Staging: `user-mgmt-staging`, automatische Argo-CD-Synchronisierung von `main`.
- Production: eigener Namespace und eigene values-prod.yaml, ebenfalls Auto-Sync.
- Zwei Worker mit je 4 GB RAM; beide Ready nach Terraform-Skalierung am 27.09.
- Vor der Erweiterung belegte der einzelne Worker rund 94% seines allocatable RAM.
  Ressourcen und tatsaechlichen Verbrauch nach Installation erneut beobachten.

## Durchgefuehrter Aufbau und Reihenfolge fuer eine neue Umgebung

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
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack --version 91.7.0 --kube-context do-fra1-vsc-orchestrierung -n monitoring --create-namespace -f monitoring/values.yaml --wait --timeout 10m
kubectl --context do-fra1-vsc-orchestrierung apply -f monitoring/alert-receiver.yaml
kubectl --context do-fra1-vsc-orchestrierung apply -f monitoring/vsc-infrastructure.yaml -f monitoring/vsc-user-service.yaml -f monitoring/vsc-module-service.yaml
kubectl --context do-fra1-vsc-orchestrierung -n monitoring port-forward svc/monitoring-grafana 3000:80
```

Live-Installation und Behebung des CRD-Timeouts: [Nachweis](evidence/monitoring-installation.md).
Die drei VSC-Dashboards wurden ueber die Grafana-API nachgewiesen. Das
Infrastruktur-Dashboard hat bereits Messwerte; beide Anwendungs-ServiceMonitors
sind inzwischen aktiv und liefern HTTP-Counter und Histogramme fuer die RED-Dashboards.

Der konfigurierte Benachrichtigungskanal ist ein interner HTTP-Webhook, dessen
Empfang mit `kubectl -n monitoring logs deploy/alert-receiver` nachgewiesen wird.
Dies ist keine E-Mail-/Chat-Benachrichtigung. Falls eine solche verlangt wird,
einen autorisierten Empfaenger ueber ein Secret konfigurieren.
Die erste echte Zustellung ist [waehrend der geplanten Wartung nachgewiesen](evidence/alert-delivery.md).
Die lokalen Receiver-Logs sind nicht dauerhaft: Nachweise nach dem Test sichern.
CPU/Memory-Dashboard sowie separate RED-Dashboards fuer User- und Module-Service.

## Managed-Datenbank-Umschaltung

Die vorbereitenden Skripte wurden am 27.09. erfolgreich ausgefuehrt:

```powershell
.\scripts\Prepare-ManagedDatabaseSecrets.ps1
.\scripts\Test-ManagedPostgresRestore.ps1 -BackupPath '<vollstaendiger Pfad zum geprueften .dump>'
```

Das erste Skript liest Zugangsdaten ueber die DigitalOcean-API in den Speicher und
uebertraegt sie per stdin als Secrets; es schreibt keine Passwortdatei. Das zweite
nutzt einen temporaeren Client-Pod mit begrenztem Netzwerkzugriff und prueft TLS,
Archiv-Pruefsumme sowie Tabellen- und Sequenz-Fingerprints. Es stellt nur in ein
leeres public-Schema wieder her und entfernt anschliessend Pod und Netzwerkregel.
Ein Fehler beim Restore rollt die gesamte Transaktion zurueck.
Quelle: [PostgreSQL pg_restore](https://www.postgresql.org/docs/16/app-pgrestore.html).

**Den Standard-Restore nicht nochmals auf das bereits befuellte Ziel anwenden.**
Fuer die endgueltige Umschaltung zuerst die Staging-Wartung per GitOps aktivieren,
dann `scripts/Sync-StagingPostgres.ps1` ausfuehren. Der neue Ablauf sichert Quelle
und bisherigen Zielstand, prueft Wartung/fehlende Clients, ersetzt den unbenutzten
Teststand transaktional und vergleicht Quelle/Ziel erneut. Siehe Cutover-Anleitung.
Ein frueherer Vergleich belegt nur den Stand zu seinem Testzeitpunkt.
Lokale Reports und Backups liegen unter dem ignorierten Verzeichnis tmp/.

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
Beim ersten Start gegen Managed PostgreSQL bleibt `postgres.enabled=true`, damit
die Quell-Datenbank mit ihrem Volume fuer einen kontrollierten Rueckweg erhalten
bleibt. Nach finalem Backup bei gestoppten Schreibzugriffen, Datenvergleich und
erfolgreicher Anwendungspruefung wird die Quelle separat entfernt.
`postgres.enabled=false` entfernt Deployment, Service und PVC aus dem Chart.
**Argo CD prune kann dann Datenvolumes loeschen: erst Backup und Migration pruefen.**
Production wird separat migriert; gemeinsame Templates bleiben standardmaessig
abwaertskompatibel (postgres an, neue Funktionen aus).

## Policies

```powershell
helm repo add kyverno https://kyverno.github.io/kyverno/
helm upgrade --install kyverno kyverno/kyverno --version 3.9.1 --kube-context do-fra1-vsc-orchestrierung -n policy --create-namespace -f policy/values.yaml --wait --timeout 10m
kubectl --context do-fra1-vsc-orchestrierung apply -f policy/policies.yaml
kubectl --context do-fra1-vsc-orchestrierung label namespace user-mgmt-staging vsc-policies=enforce --overwrite
kubectl --context do-fra1-vsc-orchestrierung apply --dry-run=server -f policy/invalid-deployment.yaml
```

Die letzte Zeile MUSS abgelehnt werden. Drei Policies verlangen Requests/Limits,
Non-root ohne Privilege Escalation und explizite Image-Tags statt latest.
Kyverno erzeugt Controller-Regeln aus den Pod-Regeln. Die Namespace-Selektion
verhindert, dass die Kursregeln Systemkomponenten oder alte Umgebungen blockieren.
Init-Container werden ebenfalls geprueft. Container duerfen den Non-root-Kontext
nicht durch Root-Overrides oder privileged=true umgehen. Reproduzierbare
Server-Dry-Run-Pruefungen: `python scripts/verify-policies.py`.
Installationswarnungen und Hintergrundberichte sind im
[Live-Nachweis](evidence/kyverno-admission.md) erklaert.

## Lasttest und Nachweise

Das Vorbereitungsskript registriert einen separaten synthetischen Testbenutzer,
prueft dessen Login und legt `loadtest-credentials` sowie die Test-ConfigMap an.
Es nutzt Python im bestehenden Grafana-Sidecar fuer den internen API-Zugriff;
Zugangsdaten bleiben im Speicher bzw. Secret. Es startet noch keine Last.
Am 27.09. wurde diese Vorbereitung erfolgreich ausgefuehrt.

```powershell
.\scripts\Prepare-StagingLoadTest.ps1
kubectl --context do-fra1-vsc-orchestrierung apply -f loadtest/job.yaml
kubectl --context do-fra1-vsc-orchestrierung -n user-mgmt-staging wait job/user-mgmt-loadtest "--for=jsonpath={.status.ready}=1" --timeout=120s
kubectl --context do-fra1-vsc-orchestrierung -n user-mgmt-staging logs -f job/user-mgmt-loadtest --pod-running-timeout=120s
# In einem zweiten Terminal die Skalierung beobachten:
kubectl --context do-fra1-vsc-orchestrierung -n user-mgmt-staging get hpa -w
```

Das Skript lastet den Login als echten API-Endpunkt aus: 2 -> 10 -> 20 -> 0 VUs.
Es prueft erfolgreiche Logins, <1% HTTP-Fehler und P95 <3 Sekunden.
Auch erfolgreiche HTTP-Antworten allein muessen P95 <3 Sekunden erreichen;
schnelle Verbindungsfehler sollen die Latenzbewertung nicht verdecken.
HPA-Ausgangswert, Maximum und Rueckgang zeitgestempelt festhalten, ebenso k6-Ergebnis
und Grafana-Zeitraum. Lasthoehe nur anhand der Beobachtung anpassen. Ein vorhandenes
Skript allein belegt noch keine erfolgreiche Skalierung.
Der Job hat keine automatischen Wiederholungen und endet spaetestens nach acht
Minuten. Vor einer Wiederholung zuerst Ergebnis/Logs sichern und den beendeten
Job gezielt entfernen; das Vorbereitungsskript ueberschreibt keinen bestehenden Job.

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
