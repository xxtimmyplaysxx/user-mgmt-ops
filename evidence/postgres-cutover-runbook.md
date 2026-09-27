# Kontrollierte PostgreSQL-Umschaltung

Nur `user-mgmt-staging` auf `do-fra1-vsc-orchestrierung`.
Production wird in diesem Ablauf nicht umgestellt.

## 1. Wartungszustand ueber GitOps

Die Staging-values setzen voruebergehend `replicas.backend=0` und
`autoscaling.enabled=false`. Argo CD entfernt den HPA und beendet alle
Staging-Backend-Pods. Waehrenddessen ist die Staging-API nicht verfuegbar.
Die alte PostgreSQL und ihr PVC bleiben erhalten. Die Monitoring-Regel
`UserMgmtUnavailable` kann in dieser geplanten Wartung ausloesen.

## 2. Frische Daten kopieren

Erst nach erfolgreichem Wartungs-Rollout, aus dem Ops-Verzeichnis:

```powershell
.\scripts\Sync-StagingPostgres.ps1
```

Das Skript verweigert den Lauf, wenn Backend-Pods oder HPA existieren, die Quelle
noch andere Client-Verbindungen hat oder die Anwendung bereits das Managed-Secret
verwendet. Es erstellt einen frischen Quell-Dump, prueft Archiv und SHA256 und
sichert zusaetzlich den bisherigen Teststand im Managed-Ziel lokal unter `tmp/`.
Auch das Ziel darf keine anderen Client-Verbindungen haben.

Der Restore ersetzt ausschliesslich den zuvor geprueften, noch unbenutzten
Teststand in `usermgmt_staging` auf der bekannten Managed-PG-Instanz.
`pg_restore --clean --if-exists --single-transaction --no-owner --no-acl`
fasst Loeschungen und Restore in eine Transaktion; ein Restore-Fehler rollt diese
zurueck. Anschliessend werden Tabellen-/Sequenz-Fingerprints zwischen Quelle und
Ziel verglichen. Die Wartungsbedingungen werden nochmals geprueft. Quelle und PVC
werden durch kein Migrationsskript geloescht.

Der bisherige Standardmodus von `Test-ManagedPostgresRestore.ps1` bleibt auf ein
leeres Ziel beschraenkt. Nur der explizite Schalter `-RefreshTrialRestore` aktiviert
den beschriebenen, geschuetzten Austausch des Teststands.

Live-Ausfuehrung am 27.09.2026 um 16:17 Uhr erfolgreich: beide Archive und
Pruefsummen verifiziert, transaktionaler Restore mit TLS 1.3 abgeschlossen,
alle fuenf Tabellen-/Sequenz-Fingerprints stimmen ueberein.
Details: [Finaler Datenabgleich](postgres-final-copy.md).

## 3. Anwendung gegen Managed PostgreSQL starten

Erst nach erfolgreichem aktuellen Datenvergleich werden in einem separaten
reviewten GitOps-Schritt `managedDatabase.enabled=true`, `replicas.backend=1`
und `autoscaling.enabled=true` gesetzt. `postgres.enabled=true` bleibt zunaechst
erhalten. Danach TLS, Readiness, Anmeldung, Modulzuweisung und Metriken pruefen.

Vor der Umschaltung kann die Wartung durch Zuruecksetzen der beiden
Wartungs-values beendet werden; die Quelle ist weiterhin unveraendert nutzbar.
Nach Schreibzugriffen auf Managed PostgreSQL ist ein Rueckwechsel ohne erneuten
Datenabgleich nicht sicher. Alte Quell-Datenbank und PVC erst nach erfolgreicher
Abnahme separat entfernen.

Quelle: [PostgreSQL 16 pg_restore](https://www.postgresql.org/docs/16/app-pgrestore.html).
