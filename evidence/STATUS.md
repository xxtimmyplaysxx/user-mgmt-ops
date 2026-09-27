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
- Lokale terraform.tfvars: `enable_databases=true` (nicht in Git).
- Quell-Backup mit `scripts/Backup-StagingDatabase.ps1`: Custom-Archiv, 8806 Bytes;
  `pg_restore --list` erfolgreich, SHA256 zwischen Pod und lokaler Kopie identisch.
- Backup liegt ausschliesslich unter dem ignorierten `tmp/backups/`; keine Inhalte
  in Git. Wiederherstellung und Datenvergleich sind noch NICHT erfolgt.

Erfolgreich lokal ausgefuehrt:
- Java Gradle-Tests fuer Module-Client und Controller.
- Python pytest: 3 Tests erfolgreich (SQLite, nicht Managed MySQL).
- Helm lint der bisherigen Staging-Konfiguration.
- Helm template der Managed-Variante und Assertions zu DB/PVC, Security,
  Ressourcen und ServiceMonitors.
- Helm template kube-prometheus-stack 91.7.0 und Kyverno 3.9.1.

Lesend am bestehenden Cluster festgestellt:
- Cluster running; vorhandene Argo-CD-Anwendungen Synced/Healthy.
- Ein Node; rund 94% der allocatable Memory belegt.
- Zu Beginn noch keine Managed-Datenbanken vorhanden; Erstellung siehe oben.

Ausstehend (NICHT als bestanden behauptet):
- Zusaetzliche Clusterkapazitaet fuer die neuen Workloads.
- Gepruefte Datenmigration und Umschaltung auf die erstellten Managed-Datenbanken.
- Monitoring-Installation, Scrape-Targets, Dashboard-Messwerte und Alert-Empfang.
- k6-Lauf, HPA scale-out/scale-in und Verfuegbarkeit.
- Kyverno-Admission-Ablehnung.
- Live-E2E und Fehlerfaelle einschliesslich TLS zu Managed MySQL.
- GitOps-Rollout der neuen Images und Status der CI-Builds.

Nachweise mit Uhrzeit und Commit-SHA ergaenzen. Keine Tokens, Passwoerter,
JWTs, State-Dateien oder Datenbankinhalte in diese Dokumentation kopieren.
