# Monitoring-Installation am 27.09.2026

Kontext: do-fra1-vsc-orchestrierung. Namespace: monitoring.
Verifikation abgeschlossen um 15:13 Uhr Europe/Zurich.

## Timeout und Behebung

Der erste Helm-Installationsversuch brach vor Anlage der Workloads ab.
Zwei CRDs meldeten NamesAccepted=True, aber Established=False (Installing):
servicemonitors.monitoring.coreos.com und thanosrulers.monitoring.coreos.com.
Die uebrigen acht Monitoring-CRDs waren bereits Established=True.
Zu diesem Zeitpunkt existierten weder Monitoring-Pods noch ein Helm-Release.
Die bestehenden Anwendungen blieben Synced/Healthy; /readyz des API-Servers war OK.

Eine Metadaten-Aktualisierung ueber die Annotation vsc-course-reconcile-at stiess
die erneute Verarbeitung an. Eine Anfrage endete mit EOF und wurde wiederholt.
Danach bestaetigte kubectl wait fuer beide CRDs Established=True. Die CRDs wurden
weder geloescht noch ihre Statusfelder manuell veraendert. Die genaue Ursache
der zuvor haengenden Registrierung ist ohne Control-Plane-Logs nicht belegt.

Anschliessend wurde derselbe Helm-Installationsbefehl erneut ausgefuehrt:

```powershell
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack --version 91.7.0 --kube-context do-fra1-vsc-orchestrierung -n monitoring --create-namespace -f monitoring/values.yaml --wait --timeout 10m
```

Ergebnis: STATUS deployed, REVISION 1, DESCRIPTION Install complete.
Helm-Version: v4.2.4. Chart: kube-prometheus-stack-91.7.0.
Operator App-Version: v0.94.1.

## Live-Pruefungen

| Komponente | Ready | Restarts |
|---|---|---|
| Grafana | 3/3 | 0 |
| Prometheus | 2/2 | 0 |
| Alertmanager | 2/2 | 0 |
| Prometheus Operator | 1/1 | 0 |
| kube-state-metrics | 1/1 | 0 |
| Node Exporter, alter Worker | 1/1 | 0 |
| Node Exporter, neuer Worker | 1/1 | 0 |
| Alert-Receiver | 1/1 | 0 |

Prometheus /api/v1/targets: 18 activeTargets, alle health=up.
Die Prometheus-API wurde ueber den authentifizierten Kubernetes-Service-Proxy
abgefragt; es wurde kein oeffentlicher Monitoring-Ingress eingerichtet.

Diese Abfragen lieferten jeweils drei Staging-Container/Pod-Zeitreihen:

```promql
container_memory_working_set_bytes{namespace="user-mgmt-staging",container!="",container!="POD"}
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="user-mgmt-staging",container!="",container!="POD"}[2m]))
```

Grafana /api/health bestaetigte database=ok. Die authentifizierte Such-API lieferte:

- vsc-infrastructure: VSC - Kubernetes CPU, Memory and HPA
- vsc-user-service: VSC - User Service RED
- vsc-module-service: VSC - Module Service RED

Die Zugangsdaten wurden nur im Pod aus vorhandenen Secret-Umgebungsvariablen
gelesen und nicht ausgegeben. Dashboard-ConfigMaps und Alert-Receiver entsprechen
den Dateien unter monitoring/.

## Noch offen

Die neuen Anwendungs-Images und deren ServiceMonitors sind noch nicht ausgerollt.
Daher belegt dieser Nachweis Infrastruktur-Messwerte und Dashboard-Provisionierung,
noch keine User-/Module-RED-Messwerte. Ein ausgeloester und zugestellter Testalarm,
Lasttest und HPA-Skalierung muessen separat nachgewiesen werden.
