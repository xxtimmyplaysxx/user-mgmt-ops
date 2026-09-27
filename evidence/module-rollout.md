# Module-Service-Rollout am 27.09.2026

Geprueft um 15:51-15:55 Uhr (Europe/Zurich).

- Ops PR 1 gemergt: `922031eb071225176caa1b68ee889875f7b18492`.
- Drei Anwendungs-Images: `122fe4821c7c0805ee63ac955c2ea41e60d1907c`.
- Argo CD meldet Staging und Production Synced/Healthy.
- Staging: Backend, Frontend, Module-Service und bisherige PostgreSQL Ready.
- Module-Service-Init erfolgreich; vier Module in Managed MySQL vorhanden.
- MySQL-Verbindung aus dem Module-Service: TLSv1.3, TLS_AES_256_GCM_SHA384.
  `ssl_verify_cert=true` und `ssl_verify_identity=true` zur selben Verbindung
  konfiguriert; CA aus dem Kubernetes-Secret, keine Zugangsdaten ausgegeben.
- Prometheus: `user-mgmt-backend` und `user-mgmt-module` health=up,
  `lastError` leer. Request-Counter und Duration-Histogramme beider Dienste vorhanden.
- Live-Test `app/scripts/e2e.py` ueber internes HTTP aus dem Monitoring-Namespace:
  Registrierung/Login zweier ausdruecklicher Testbenutzer erfolgreich;
  Modulzuweisung HTTP 204 und idempotente Wiederholung HTTP 204.
- Der Test ist insgesamt **fehlgeschlagen**: fehlendes Modul liefert 403 statt 404.
  Die folgenden Testfaelle wurden durch diesen Abbruch noch nicht ausgefuehrt.
  Ursache und HTTP-Regressionskorrektur werden im Application-Repository behandelt.

Die Requests erreichten das echte Backend, den Module-Service und Managed MySQL.
PostgreSQL fuer Benutzerdaten ist weiterhin die bisherige Datenbank im Cluster.
Dieser Lauf prueft weder den Browser/Ingress noch die spaetere PostgreSQL-Umschaltung.

Reproduzierbare Lesepruefungen:

```powershell
kubectl --context do-fra1-vsc-orchestrierung -n argocd get applications
kubectl --context do-fra1-vsc-orchestrierung -n user-mgmt-staging get deployments,pods,servicemonitors
kubectl --context do-fra1-vsc-orchestrierung get --raw '/api/v1/namespaces/monitoring/services/http:monitoring-kube-prometheus-prometheus:9090/proxy/api/v1/targets'
```

Ein frischer Live-E2E-Lauf mit dem korrigierten Image ist noch erforderlich.

## Wiederholung mit korrigiertem Image erfolgreich

Am 27.09.2026 um 16:12 Uhr (Europe/Zurich) wurde der Test nach erneutem Rollout
wiederholt. Application-PR 3 ist gemergt, Main-Commit
`fd1e6343585fdf92ba437e929d23cabe1f894133`. Der Main-Run
[36324599795](https://github.com/xxtimmyplaysxx/user-mgmt-service-kubernetes/actions/runs/36324599795)
hat Tests, drei Image-Publikationen und die Ops-Promotion erfolgreich abgeschlossen.
Ops-Revision `db1a9adc342bc7b5c88b31f5087c43624b4a921b` wurde synchronisiert.

```text
PASS assignment: HTTP 204
PASS idempotent repeat: HTTP 204
PASS missing module: HTTP 404
PASS invalid module ID: HTTP 400
PASS unauthenticated: HTTP 403
PASS another user's assignment: HTTP 403
```

Auch Registrierung und Anmeldung zweier neuer Testbenutzer wurden vom Skript
erfolgreich geprueft. Alle sechs anschliessenden HTTP-Testfaelle bestanden.
Der falsche Fehlerstatus ist damit auch im echten Cluster behoben. Die fruehere
fehlgeschlagene Messung bleibt oben als Fehlernachweis erhalten.

Offen bleiben Ausfall-/Lasttests, Alarmzustellung, Policies und die endgueltige
PostgreSQL-Migration. Nach der Umschaltung ist dieser E2E-Test nochmals erforderlich.
