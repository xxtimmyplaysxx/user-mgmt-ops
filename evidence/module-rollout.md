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
