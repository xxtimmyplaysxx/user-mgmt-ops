# Aufgaben und Nachweise

Die Tests wurden am 27.09.2026 auf `do-fra1-vsc-orchestrierung` im Namespace
`user-mgmt-staging` durchgeführt. Zeitangaben in den Berichten beziehen sich auf
Europe/Zurich, sofern sie nicht ausdrücklich als UTC gekennzeichnet sind.
Die Berichte nennen die jeweils getesteten Image-Tags und Revisionen.

## 1. Observability

| Anforderung | Umsetzung / Nachweis |
|---|---|
| kube-prometheus-stack per Helm im Namespace monitoring | [Helm-Werte](../monitoring/values.yaml), [Installation](monitoring-installation.md) |
| CPU und Memory pro Pod | [Infrastruktur-Dashboard](../monitoring/vsc-infrastructure.yaml) |
| Spring-Metriken, ServiceMonitor, Request Rate / Response Time / Error Rate | [ServiceMonitor](../charts/user-mgmt/templates/monitoring.yaml), [User-Service-Dashboard](../monitoring/vsc-user-service.yaml) |
| Mindestens zwei Grafana-Dashboards | Infrastruktur, User-Service und Module-Service; [Prüfung der zehn Abfragen](loadtest-passed.md#grafana-und-red-metriken) |
| Eigene PrometheusRule und Weiterleitung durch Alertmanager | `UserMgmtUnavailable`: Alarm und Entwarnung beim [HTTP-Empfänger angekommen](alert-delivery.md) |
| Deklarative values.yaml im Ops-Repository | [monitoring/values.yaml](../monitoring/values.yaml) |

Der Benachrichtigungskanal ist ein interner HTTP-Webhook. Die Zustellung von
`firing` und `resolved` ist mit Zeitstempeln dokumentiert.

## 2. Lasttest und Skalierung

| Anforderung | Umsetzung / Nachweis |
|---|---|
| k6 im Cluster, mindestens ein Testskript | [Job](../loadtest/job.yaml), [Testskript](../loadtest/test.js) |
| Steigende Last auf einen relevanten API-Endpunkt | `POST /users/login`, Rampe 2 → 10 → 20 → 0 virtuelle Benutzer |
| Telemetriedaten und Auswirkungen nachvollziehbar | [Auswertung mit Diagramm und Rohdaten](loadtest-passed.md) |
| HPA skaliert hoch und wieder herunter | Eine → zwei → eine Backend-Replika |
| Verfügbarkeit und Verteilung auf Replikas | 3282/3282 Logins erfolgreich, mindestens eine Replika verfügbar; Verteilung über den Kubernetes Service auf bereite Endpoints |

Der Backend-Service verwendet die Standardverteilung ohne Session-Affinität.
Die Messung zeigt keine garantierte Gleichverteilung jeder einzelnen Anfrage.
[Backend-Service und Readiness](../charts/user-mgmt/templates/backend.yaml),
[HPA](../charts/user-mgmt/templates/autoscaling.yaml).
Der erste Lauf mit Heap-Fehler und die anschliessende Korrektur sind im
[Fehlerprotokoll](loadtest-first-run.md) festgehalten.

## 3. Terraform

| Anforderung | Umsetzung / Nachweis |
|---|---|
| DigitalOcean-Provider | [provider.tf](../terraform/provider.tf), festgelegte Version in der Lockdatei |
| Import-Block und Generierung aus dem bestehenden Cluster | [imports.tf](../terraform/imports.tf), [Importablauf und Ergebnis](../terraform/README.md) |
| generated.tf analysiert und bereinigt | [generated.tf](../terraform/generated.tf): GPU-Konflikte entfernt, Worker-Anzahl korrigiert, Löschschutz ergänzt |
| Wiederverwendbare Werte parametrisiert | [variables.tf](../terraform/variables.tf) |
| Token ausserhalb des Repositories | Provider liest `DIGITALOCEAN_TOKEN` aus der Umgebung |
| fmt, validate, Plan ohne unbeabsichtigte Änderungen | Erfolgreich geprüft; Abschlusskontrolle um 17:55 Uhr: `No changes`, Exitcode 0 |

Der Import ergab `1 imported, 0 added, 0 changed, 0 destroyed`.
Erst anschliessend wurden die Datenbanken angelegt und der Cluster auf zwei Worker erweitert.

## 4. Managed PostgreSQL

| Anforderung | Umsetzung / Nachweis |
|---|---|
| Bisherige PostgreSQL durch Managed PostgreSQL ersetzen | [Datenabgleich und Umschaltung](postgres-final-copy.md) |
| User-Service verwendet die Managed-Verbindung | Zehn JDBC-Verbindungen mit TLS 1.3 geprüft |
| Verbindungsdaten über Kubernetes Secret | `user-mgmt-managed-postgres`, eingebunden im [Backend-Deployment](../charts/user-mgmt/templates/backend.yaml) |
| Alten Pod, Service und PVC entfernen | Entfernung einschliesslich PV und Cloud-Volume um 16:33 Uhr geprüft |
| Managed-Datenbank mit Terraform provisionieren | [databases.tf](../terraform/databases.tf) |

Fünf Tabellen-/Sequenz-Fingerprints stimmten nach dem Restore überein.
Die [Migrationsanleitung](postgres-cutover-runbook.md) beschreibt Backup, Wartung,
Restore, ANALYZE und Umschaltung. Backups werden lokal aufbewahrt.

## 5. Kyverno

| Anforderung | Umsetzung / Nachweis |
|---|---|
| Helm-Installation im Namespace policy | [Helm-Werte](../policy/values.yaml), Chart 3.9.1 |
| Mindestens drei ClusterPolicies | Ressourcen, Non-root-Betrieb und versionierte Images in [policies.yaml](../policy/policies.yaml) |
| Ungültiges Deployment wird abgelehnt | [Testmanifest](../policy/invalid-deployment.yaml), [Ablehnung und zwölf Gegenproben](kyverno-admission.md) |
| Policies deklarativ im Ops-Repository | Enforce-Regeln für den mit `vsc-policies=enforce` markierten Staging-Namespace |

## 6. Microservices

| Anforderung | Umsetzung / Nachweis |
|---|---|
| Neuer Endpoint für Modulzuweisungen | [User-Service-API](https://github.com/xxtimmyplaysxx/user-mgmt-service-kubernetes/blob/main/OBSERVABILITY.md) |
| Existenzprüfung des Moduls über seine API | GET auf das Modul vor der PUT-Zuweisung |
| Synchroner REST-Client über Kubernetes Service, Timeout / Retry / Circuit Breaker | [Implementierung](https://github.com/xxtimmyplaysxx/user-mgmt-service-kubernetes/blob/main/src/main/java/com/example/jwt/domain/module/ModuleClient.java), [Ausfall und Erholung](module-resilience.md) |
| Kein direkter MySQL-Zugriff aus dem User-Service | MySQL-Secret nur im Module-Deployment; getrennte [Netzwerkregeln](../charts/user-mgmt/templates/networkpolicy.yaml) |
| End-to-End und passende HTTP-Statuscodes | [Sechs API-Testfälle](module-rollout.md), nach PostgreSQL-Umschaltung erneut geprüft |
| Module-Metriken per ServiceMonitor, zusätzliches RED-Dashboard | [ServiceMonitor](../charts/user-mgmt/templates/monitoring.yaml), [Dashboard](../monitoring/vsc-module-service.yaml) |
| CPU-/Memory-Limits und stabiler Betrieb | Module-Service: Request 100m/128Mi, Limit 500m/256Mi; fünf parallele Zuweisungen nach ANALYZE in 0.115–0.251 s, keine Neustarts im [Ausfalltest](module-resilience.md) |
| Module-Service erfüllt ClusterPolicies | Drei Policies bestanden; [Admission-Prüfung](kyverno-admission.md) |
| Image-Build, Versionierung, Veröffentlichung und GitOps | [Pipeline](https://github.com/xxtimmyplaysxx/user-mgmt-service-kubernetes/blob/main/.github/workflows/build-and-promote.yml), SHA-Tags und Argo-CD-Synchronisierung |
| DigitalOcean Managed MySQL | [Terraform](../terraform/databases.tf), [TLS-Verbindung und Initialisierung](module-rollout.md) |

Der Module-Service stammt aus der [Unterrichtsvorlage](https://github.com/yagan93/module_service).
Die Anpassungen sind im [Application-Repository](https://github.com/xxtimmyplaysxx/user-mgmt-service-kubernetes/blob/main/module-service/UPSTREAM.md) dokumentiert.
Der k6-Test belastet die Anmeldung. Die parallelen Modulzuweisungen und der
Netzwerkausfall wurden separat getestet.
