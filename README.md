# VSC – Observability und Microservices

Dieses Repository enthält die Infrastruktur und das Deployment für die VSC-Abgabe
vom 27.09.2026. Der [Anwendungscode](https://github.com/xxtimmyplaysxx/user-mgmt-service-kubernetes)
liegt im separaten Application-Repository.

Die Erweiterungen laufen auf dem bestehenden DigitalOcean-Cluster
`vsc-orchestrierung` in Frankfurt, im Namespace `user-mgmt-staging`.
Der Cluster hat zwei Worker. Der User-Service verwendet Managed PostgreSQL,
der Module-Service Managed MySQL. Die frühere Production-Umgebung bleibt separat.

## Aufgaben

| Aufgabe | Umsetzung | Nachweis |
|---|---|---|
| 1 – Observability | Prometheus, Grafana, ServiceMonitors und Alertmanager | [Monitoring](evidence/monitoring-installation.md), [Alarmzustellung](evidence/alert-delivery.md) |
| 2 – Lasttest | k6 mit steigender Last, HPA von einer auf zwei Replikas und zurück | [Messwerte und Diagramm](evidence/loadtest-passed.md) |
| 3 – Terraform | Bestehenden Cluster importiert, Konfiguration bereinigt und parametrisiert | [Terraform](terraform/README.md) |
| 4 – Managed Resources | PostgreSQL migriert, Daten geprüft, alte Staging-Datenbank und PVC entfernt | [Migration](evidence/postgres-final-copy.md) |
| 5 – Policy as Code | Drei Kyverno-Policies, Ablehnung ungültiger Deployments | [Policy-Test](evidence/kyverno-admission.md) |
| 6 – Microservices | Modulzuweisung über REST, Managed MySQL, Timeout/Retry/Circuit Breaker und GitOps | [API-Test](evidence/module-rollout.md), [Ausfalltest](evidence/module-resilience.md) |

Die einzelnen Akzeptanzkriterien sind unter [Aufgaben und Nachweise](evidence/STATUS.md) zugeordnet.

## Verzeichnisse

| Pfad | Inhalt |
|---|---|
| [terraform/](terraform/) | DigitalOcean-Cluster, Datenbanken und Datenbank-Firewalls |
| [charts/user-mgmt/](charts/user-mgmt/) | Helm-Chart mit Werten für Staging und Production |
| [argocd/](argocd/) | Argo-CD-Anwendungen für beide Umgebungen |
| [monitoring/](monitoring/) | Helm-Werte, drei Dashboards und Alert-Empfänger |
| [policy/](policy/) | Kyverno-Werte, Policies und ungültiges Test-Deployment |
| [loadtest/](loadtest/) | k6-Skript und Kubernetes-Job |
| [scripts/](scripts/) | Migration, Tests und Auswertung |
| [evidence/](evidence/) | Testprotokolle, Messwerte und Ergebnisse |

## Deployment

GitHub Actions im Application-Repository testet und baut die drei Images.
Nach einem Push auf `main` werden die Images veröffentlicht und ihre SHA-Tags in
[values-staging.yaml](charts/user-mgmt/values-staging.yaml) eingetragen.
Argo CD synchronisiert den Helm-Chart automatisch. Production verwendet eigene Image-Tags
und [values-prod.yaml](charts/user-mgmt/values-prod.yaml).

Monitoring und Kyverno wurden separat mit Helm installiert. Ihre Werte sind
hier versioniert. Die Befehle stehen in der [Betriebsanleitung](BETRIEB.md).

## Ergebnisse vom 27.09.2026

Der Lasttest erreichte 3282 erfolgreiche Logins bei bis zu 20 virtuellen Benutzern.
Es gab keine HTTP-Fehler; P95 lag bei 1.06 Sekunden. Der HPA skalierte von einer
auf zwei Replikas und danach wieder auf eine. Während des Tests blieb mindestens
eine Backend-Replika verfügbar.

Die sechs API-Testfälle bestanden auch nach der Datenbankmigration.
Beim Ausfalltest lieferte die Modulzuweisung begrenzte 503-Antworten und erholte
sich nach Wiederherstellung der Verbindung. Die Anmeldung blieb erreichbar.

## Konfiguration prüfen

Aus diesem Repository:

```powershell
helm lint charts/user-mgmt -f charts/user-mgmt/values-staging.yaml
helm lint charts/user-mgmt -f charts/user-mgmt/values-prod.yaml
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
```

GitHub Actions prüft zusätzlich die gerenderten Manifeste.
Tokens, Passwörter, Terraform-State, Plan-Dateien und Datenbank-Backups liegen nicht in Git.
