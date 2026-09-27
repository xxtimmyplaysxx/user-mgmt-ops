# Nachweisstatus 27.09.2026

Diese Datei unterscheidet lokale Tests von noch ausstehenden Live-Nachweisen.

## Aufgabe 3: Import nach Freigabe erfolgreich

Der Eigentuemer hat bestaetigt, dass Pruefung 2 abgeschlossen ist. generated.tf
wurde aus dem bestehenden Cluster erzeugt und bereinigt (GPU-Konflikte,
Provider-Zuordnung, Parameter, Worker-Anzahl und prevent_destroy).

Pruefungen: terraform fmt -check, terraform validate und der gespeicherte Plan
wurden erfolgreich ausgefuehrt. Der Plan wurde vor apply maschinell auf genau
einen Import der bekannten Cluster-ID und keine Create/Update/Delete-Aktionen
geprueft.

```text
Apply complete! Resources: 1 imported, 0 added, 0 changed, 0 destroyed.
No changes. Your infrastructure matches the configuration.
```

Der abschliessende `terraform plan -detailed-exitcode` lieferte Exitcode 0.
State und Plaene bleiben lokal und sind durch .gitignore ausgeschlossen.
Datenbanken waren bei diesem Import noch deaktiviert (`enable_databases=false`).

## Managed-Datenbanken und Backup

Anschliessend hat der Eigentuemer die Datenbankplaene angewendet. Der erste Lauf
erstellte PostgreSQL, lehnte aber die alte MySQL-Versionsangabe `8` ab. Die API
meldete `8.4` als verfuegbare Version. Nach Korrektur erstellte der zweite Lauf die
fuenf verbleibenden Ressourcen ohne Aenderung/Loeschung vorhandener Ressourcen.

- PostgreSQL 16: `vsc-user-postgres`, Datenbank `usermgmt_staging`.
- MySQL 8.4: `vsc-module-mysql`, Datenbank `modules`.
- Beide Firewalls erlauben den bestehenden Kubernetes-Cluster als Trusted Source.
- Kontrollplan: `No changes`, Exitcode 0.
- Lokale terraform.tfvars: `enable_databases=true`, `node_count=2` (nicht in Git).
- Quell-Backup mit `scripts/Backup-StagingDatabase.ps1`: Custom-Archiv, 8806 Bytes;
  `pg_restore --list` erfolgreich, SHA256 zwischen Pod und lokaler Kopie identisch.
- Backup liegt ausschliesslich unter dem ignorierten `tmp/backups/`; keine Inhalte
  in Git.

## Kapazitaet, Secrets und Wiederherstellung

Live-Restore-Test abgeschlossen am 27.09.2026 um 15:03 Uhr (Europe/Zurich).

- Eigentuemer hat capacity.tfplan angewendet: 0 added, 1 changed, 0 destroyed.
- Beide Worker `pool-3y84frtdj-3mixuj` und `pool-3y84frtdj-3xfmor` sind Ready.
- Kontrollplan danach: `No changes`, Exitcode 0.
- PostgreSQL und MySQL melden ueber die DigitalOcean-API `online`.
- Secrets `user-mgmt-managed-postgres` und `user-mgmt-module-db` in Staging erstellt.
- Backup `user-mgmt-staging-20260927-144952.dump` in zuvor leeres Managed-PG-Schema
  wiederhergestellt, mit `--single-transaction --no-owner --no-acl`.
- Verbindung ueber privaten Endpunkt, `sslmode=verify-full` und DigitalOcean-CA;
  `pg_stat_ssl` bestaetigt `t|TLSv1.3`.
- Fuenf Tabellen/Sequenzen mit Anzahlen und aggregierten Inhalts-Fingerprints
  verglichen: Quelle und Ziel stimmen ueberein. Keine Datensaetze ausgegeben.
- Temporaerer Client-Pod und seine Netzwerkregel anschliessend entfernt.
- Anwendung weiterhin an alter PostgreSQL-Datenbank. Vor der endgueltigen
  Umschaltung Schreibzugriffe stoppen und aktuellen Datenstand erneut uebernehmen.
- Reproduzierbare Skripte: Prepare-ManagedDatabaseSecrets.ps1,
  Test-ManagedPostgresRestore.ps1 und database-fingerprint.sql unter scripts/.

## Monitoring installiert

Geprueft am 27.09.2026 um 15:13 Uhr (Europe/Zurich):

- Helm-Release monitoring, Chart kube-prometheus-stack 91.7.0, Revision 1, deployed.
- Acht Pods im Namespace monitoring sind Ready/Running, keine Restarts.
- Prometheus meldet 18 aktive Scrape-Targets mit health=up.
- CPU-Rate und Memory-Metriken fuer jeweils drei Staging-Container/Pods vorhanden.
- Grafana API health=ok; alle drei VSC-Dashboard-UIDs ueber API gefunden.
- Alert-Receiver Deployment erfolgreich gestartet; Alarmzustellung noch offen.
- Bestehende Argo-CD-Anwendungen weiterhin Synced/Healthy.
- Details und CRD-Timeout-Behebung: monitoring-installation.md.

Nachtrag um 15:19 Uhr: Grafana wurde beim ersten Browserzugriff mit dem alten
256Mi-Limit OOMKilled. Helm-Revision 2 erhoeht den Request auf 512Mi und das Limit
auf 768Mi. Drei parallele Abrufserien der Login-Dateien erfolgreich, neuer Pod
3/3 Ready ohne Restarts, gemessener Verbrauch 428Mi. Dashboards erneut geprueft.
Details und Testumfang in monitoring-installation.md.

## Anwendungs-Images und naechster Staging-Rollout

Aktualisierung 15:55 Uhr: Ops PR 1 ist gemergt; alle vier Staging-Deployments sind
Ready. Module-Service mit Managed MySQL/TLS 1.3 sowie beide Anwendungs-Scrape-Targets
sind verifiziert. Live-E2E hat bei einem fehlenden Modul einen falschen HTTP-Status
aufgedeckt (403 statt 404); Korrektur und Wiederholung stehen aus.
Nachtrag 16:12 Uhr: Application-PR 3 und Main-Pipeline erfolgreich; der komplette
Live-E2E-Test mit Image `fd1e6343585fdf92ba437e929d23cabe1f894133` besteht jetzt
alle sechs HTTP-Testfaelle nach erfolgreicher Registrierung/Anmeldung.
Details: [Module-Rollout](module-rollout.md). Die folgende Chronologie beschreibt
auch fruehere Zwischenstaende.

- Application-PR 1 vom Eigentuemer gemergt; main-Commit
  `6c932b34bb69f1d3af03ca5529b887874d9b6112`.
- GitHub-Run 36322414461: Java/Python-Tests sowie Build/Push aller drei Images
  erfolgreich. Alle drei SHA-Tags anonym aus GHCR abrufbar (Manifest HTTP 200).
- Der Run insgesamt ist fehlgeschlagen: Ops-Checkout meldete Bad credentials.
  Eine automatische Image-Promotion nach Ops-main fand daher NICHT statt.
- Reparatur vorbereitet in Application-PR 2: repo-spezifischer SSH-Deploy-Key statt
  ungueltigem OPS_REPO_TOKEN, explizites Checkout von Ops-main. Lesen und
  Push-Dry-Run ueber den neuen Key erfolgreich; privater Key nur im verschluesselten
  Actions-Secret OPS_DEPLOY_KEY. Lokale Schluesseldateien danach entfernt.
- Die Staging-values dieses Ops-Branches aktivieren Module-Service/MySQL und zwei
  ServiceMonitors, behalten aber lokale PostgreSQL und PVC fuer die spaetere
  kontrollierte Migration. CPU-Limit-Quota 4 fuer HPA, Rolling Updates und k6.
- Helm lint fuer Staging/Production sowie Render-Assertions fuer den ersten
  Rollout und die spaetere Managed-Variante erfolgreich. Noch kein Ops-main-Merge.

Nachtrag: Application-PR 2 wurde vom Eigentuemer gemergt. Der main-Run
[36323051668](https://github.com/xxtimmyplaysxx/user-mgmt-service-kubernetes/actions/runs/36323051668)
fuer `122fe4821c7c0805ee63ac955c2ea41e60d1907c` ist vollstaendig erfolgreich
(1m50s), einschliesslich SSH-Checkout, Image-Promotion und Push nach Ops-main.
Der neue repo-spezifische Deploy-Key ist damit auch im echten CI-Lauf verifiziert.

Erfolgreich lokal ausgefuehrt:
- Java Gradle-Tests fuer Module-Client und Controller.
- Python pytest: 3 Tests erfolgreich (SQLite, nicht Managed MySQL).
- Helm lint der bisherigen Staging-Konfiguration.
- Helm template der Managed-Variante und Assertions zu DB/PVC, Security,
  Ressourcen und ServiceMonitors.
- Helm template kube-prometheus-stack 91.7.0 und Kyverno 3.9.1.

Lesend am bestehenden Cluster festgestellt:
- Cluster running; vorhandene Argo-CD-Anwendungen Synced/Healthy.
- Vor der Kapazitaetserweiterung ein Node mit rund 94% belegtem allocatable Memory;
  inzwischen zwei Ready-Nodes, siehe oben.
- Zu Beginn noch keine Managed-Datenbanken vorhanden; Erstellung siehe oben.

Ausstehend (NICHT als bestanden behauptet):
- Finaler Datenabgleich bei gestoppten Schreibzugriffen und Anwendungs-Umschaltung
  auf die erstellten Managed-Datenbanken.
- RED-Dashboard-Pruefung und tatsaechlicher Alert-Empfang. Anwendungs-Scrape-Targets,
  Request-Counter und Duration-Histogramme sind inzwischen nachgewiesen.
- k6-Lauf, HPA scale-out/scale-in und Verfuegbarkeit.
- Kyverno-Admission-Ablehnung.
- Live-Ausfalltests und erneuter E2E-Lauf nach PostgreSQL-Umschaltung.
  Fehlerstatus-Korrektur, kompletter Live-E2E, TLS zu Managed MySQL und der
  GitOps-Rollout sind nachgewiesen.

Nachweise mit Uhrzeit und Commit-SHA ergaenzen. Keine Tokens, Passwoerter,
JWTs, State-Dateien oder Datenbankinhalte in diese Dokumentation kopieren.
