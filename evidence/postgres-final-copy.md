# PostgreSQL-Migration: Datenabgleich, Umschaltung und Abbau

Die Migration wurde am 27.09.2026 abgeschlossen. Der Ablauf umfasst den Datenabgleich
um 16:17 Uhr, den Anwendungstest um 16:26 Uhr und die Entfernung der Quelle um 16:33 Uhr.

## Datenabgleich

Ausgefuehrt am 27.09.2026, 16:17:30-16:17:47 Uhr (Europe/Zurich), nach Wartungs-Merge
`4f0263004d9aa1474db921b1460b09d57236ad6c` (Ops PR 2).

Das Skript `scripts/Sync-StagingPostgres.ps1` hat Folgendes live geprueft:

- Staging-Backend auf 0, keine Backend-Pods, kein Backend-HPA.
- Quelle ohne andere Client-Verbindungen; Managed-Ziel ebenfalls ohne andere Clients.
- Quelle weiterhin die bisherige PostgreSQL im Cluster; Managed-Secret noch nicht
  in der Backend-Konfiguration eingebunden.
- Frischer Custom-Dump: `user-mgmt-staging-20260927-161730.dump`, 9310 Bytes.
  Archiv lesbar, lokale und entfernte SHA256 stimmen ueberein:
  `f46d90d36411804728bb7aea0453937949be703144c4e75073295f2ace0d04df`.
- Bisheriger unbenutzter Zielstand zusaetzlich als
  `managed-before-cutover-20260927-161738.dump` gesichert; Archiv und SHA256 geprueft.
- Restore mit `--clean --if-exists --single-transaction --no-owner --no-acl`
  erfolgreich; privater Managed-PG-Endpunkt, `sslmode=verify-full` mit CA-Datei.
- `pg_stat_ssl`: `t|TLSv1.3`.
- Fuenf Tabellen-/Sequenz-Fingerprints verglichen: Anzahlen und aggregierte Inhalte
  stimmen ueberein. Keine Datenzeilen oder Zugangsdaten im Nachweis ausgegeben.
- Wartungsbedingungen nach dem Vergleich erneut bestaetigt.
- Temporaerer Migrations-Pod und seine NetworkPolicy entfernt.
- Quell-Deployment, Service und PVC waren zu diesem Zeitpunkt noch vorhanden; PVC Bound.

Die Archive und der maschinenlesbare Report liegen ausschliesslich unter dem
ignorierten `tmp/`. Der Datenabgleich fand bei gestoppter Anwendung statt.
Danach wurden `managedDatabase.enabled=true` gesetzt und Backend sowie HPA
wieder aktiviert. Die Quelle blieb bis zum erfolgreichen Anwendungstest erhalten.

## Anwendung nach Umschaltung geprueft

Ops PR 3 wurde als `8ba0fd07b2affd68c536e901f855d8fc609d819d` gemergt.
Nach der Synchronisierung wurde das Backend Ready; Staging und Production melden
Synced/Healthy. Image: `fd1e6343585fdf92ba437e929d23cabe1f894133`.

Am 27.09.2026 um 16:26 Uhr wurde mit dem neuen, ausschliesslich lesenden
`scripts/Test-ManagedPostgresConnection.ps1` die reale Managed-Datenbank geprueft:

```json
{"database":"usermgmt_staging","client_tls":"TLSv1.3","jdbc_connections":10,"all_jdbc_tls":true,"jdbc_tls_versions":["TLSv1.3"]}
```

Das Backend verwendet das Managed-Secret als letzte envFrom-Quelle und mountet die
CA. Die konfigurierte URL nutzt `sslmode=verify-full`. Die SQL-Abfrage verbindet
`pg_stat_activity` mit `pg_stat_ssl` und bestaetigt die Verschluesselung der echten
JDBC-Sessions. Der temporaere Pruef-Client und seine Netzwerkregel wurden entfernt.

Der erneute Live-E2E-Lauf um 16:26-16:27 Uhr bestand Registrierung und Anmeldung
zweier Testbenutzer sowie alle sechs HTTP-Faelle:

```text
PASS assignment: HTTP 204
PASS idempotent repeat: HTTP 204
PASS missing module: HTTP 404
PASS invalid module ID: HTTP 400
PASS unauthenticated: HTTP 403
PASS another user's assignment: HTTP 403
```

Prometheus-Targets fuer Backend und Module-Service sind wieder up. Die Quelle hat
keine anderen Client-Verbindungen. Nur der alte PostgreSQL-Pod verwendet den
Staging-PVC `user-mgmt-postgres-data`; dessen PV hat die ReclaimPolicy `Delete`.
Der lokale Quell-Dump wurde vor Vorbereitung der Entfernung nochmals per SHA256
gegen den erfolgreichen Restore-Report geprueft.

Nach diesen Pruefungen wurde die Entfernung separat ueber `postgres.enabled=false`
vorgenommen. Managed PostgreSQL und die Backups blieben bestehen.

## Quelle und altes Volume entfernt

Ops PR 4 wurde als `0ff90044fe42664403bfa0ae8248cbd34de5fa34` gemergt und von
Argo CD synchronisiert. Am 27.09.2026 um 16:33 Uhr (Europe/Zurich) geprueft:

- Altes Staging-PostgreSQL-Deployment, Service, NetworkPolicy und PVC entfernt.
- Der vorher an `user-mgmt-staging/user-mgmt-postgres-data` gebundene PV
  `pvc-15e25f3b-29a6-45ac-9b37-40134a5a53ab` ist ebenfalls entfernt.
- Die DigitalOcean-API antwortet fuer die vorab gespeicherte exakte Volume-ID
  mit HTTP 404; auch das alte Cloud-Block-Volume ist somit entfernt.
- Staging hat nur noch Backend, Frontend und Module-Service; alle Deployments Ready.
- HPA vorhanden, beide Argo-CD-Anwendungen Synced/Healthy.
- Production-PostgreSQL weiterhin 1/1 Ready; die getrennte Production wurde nicht migriert.

Damit ist der Staging-Migrationsablauf einschliesslich Quell-DB/PVC-Entfernung
abgeschlossen. Der finale Quell-Dump und der gesicherte alte Zielstand bleiben
lokal unter dem ignorierten `tmp/backups/` erhalten.
