# Nachweisstatus 27.09.2026

Diese Datei unterscheidet lokale Tests von noch ausstehenden Live-Nachweisen.

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
- Noch keine Managed-Datenbanken vorhanden.

Ausstehend (NICHT als bestanden behauptet):
- Clusterfreigabe, Kapazitaet, Terraform-Generierung/Import/No-change-Plan.
- Managed PostgreSQL/MySQL und gepruefte Datenmigration.
- Monitoring-Installation, Scrape-Targets, Dashboard-Messwerte und Alert-Empfang.
- k6-Lauf, HPA scale-out/scale-in und Verfuegbarkeit.
- Kyverno-Admission-Ablehnung.
- Live-E2E und Fehlerfaelle einschliesslich TLS zu Managed MySQL.
- GitOps-Rollout der neuen Images und Status der CI-Builds.

Nachweise mit Uhrzeit und Commit-SHA ergaenzen. Keine Tokens, Passwoerter,
JWTs, State-Dateien oder Datenbankinhalte in diese Dokumentation kopieren.
