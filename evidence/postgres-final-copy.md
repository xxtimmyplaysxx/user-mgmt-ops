# Frischer Datenabgleich vor Managed-PG-Umschaltung

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
- Quell-Deployment, Service und PVC bleiben vorhanden; PVC ist Bound.

Die Archive und der maschinenlesbare Report liegen ausschliesslich unter dem
ignorierten `tmp/`. Dies belegt die aktuelle Datenkopie bei gestoppter Anwendung.
Der Anwendungsstart gegen Managed PostgreSQL und sein E2E-Test stehen noch aus.

Naechster GitOps-Schritt: `managedDatabase.enabled=true`, Backend/HPA wieder
aktivieren, Quelle zunaechst behalten. Nach Schreibzugriffen auf das Ziel keinen
Rueckwechsel zur alten Quelle ohne erneuten Datenabgleich vornehmen.
