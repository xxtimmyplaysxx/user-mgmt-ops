# Alarmzustellung waehrend der geplanten Staging-Wartung

Am 27.09.2026 wurde das Staging-Backend fuer den finalen PostgreSQL-Datenabgleich
kontrolliert auf 0 skaliert. Dies erzeugte einen echten, geplanten Ausfall der
Staging-API. Es wurde kein synthetischer Alarm direkt in Alertmanager eingespeist.

Die im Helm-Chart definierte PrometheusRule `UserMgmtUnavailable` prueft, ob weniger
als eine Backend-Replica verfuegbar ist, und wartet eine Minute bis zur Ausloesung.
Prometheus meldete um 16:17:32 Uhr (Europe/Zurich) `pending`; um 16:18:32 Uhr ging
der Alarm auf `firing`. Der konfigurierte Alertmanager-Webhook wurde zehn Sekunden
spaeter vom laufenden `alert-receiver` empfangen.

Aus dem JSON-Payload der Receiver-Logs extrahiert (Zeitstempel UTC):

```json
{
  "received_at": "2026-09-27T14:18:42.065322183Z",
  "notification_status": "firing",
  "alert_status": "firing",
  "alert": "UserMgmtUnavailable",
  "namespace": "user-mgmt-staging",
  "deployment": "user-mgmt-backend",
  "starts_at": "2026-09-27T14:18:32.039Z",
  "summary": "Keine verfuegbare User-Service-Replica"
}
```

Damit ist die Kette Metrik -> PrometheusRule -> Alertmanager -> HTTP-Empfaenger
live nachgewiesen. Der Kanal ist ein interner Webhook, keine E-Mail oder externe
Chat-Nachricht. Die `resolved`-Meldung wird nach dem Backend-Neustart separat
geprueft. Die wartungsbedingte Unterbrechung ist kein Nachweis einer fehlgeschlagenen
Verfuegbarkeitsmessung unter Last; der eigentliche k6-Lauf steht noch aus.

```powershell
kubectl --context do-fra1-vsc-orchestrierung -n monitoring logs deploy/alert-receiver --since=10m --timestamps
```

Die Receiver-Logs sind ohne persistentes Log-Backend fluechtig; dieser Auszug haelt
die beobachtete Zustellung fest.

## Entwarnung nach dem Managed-PG-Start

Nach dem erfolgreichen Backend-Start endete der Alarm um 16:25:17 Uhr.
Der Receiver hat auch die `resolved`-Benachrichtigung empfangen:

```json
{
  "received_at": "2026-09-27T14:25:42.108466855Z",
  "status": "resolved",
  "starts_at": "2026-09-27T14:18:32.039Z",
  "ends_at": "2026-09-27T14:25:17.039Z"
}
```

Damit sind Ausloesung, Zustellung und Entwarnung fuer denselben Alarm live belegt.
