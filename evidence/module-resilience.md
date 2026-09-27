# Module-Service: Ausfall, Circuit Breaker und Erholung

Live geprueft am **27.09.2026, 17:46:50-17:47:16 Europe/Zurich**.
Die maschinenlesbaren, bereinigten Ergebnisse liegen in
[module-resilience.json](module-resilience.json).

- Kontext: `do-fra1-vsc-orchestrierung`, Namespace `user-mgmt-staging`.
- Backend-Image: `ghcr.io/xxtimmyplaysxx/user-mgmt-backend:fd1e6343585fdf92ba437e929d23cabe1f894133`.
- Ops-Revision: `0f81273af28f59f552cd3b3827ec782a9b22e3b6` (PR 6).
- Ein Ready-Backend und ein Ready-Module-Pod, beide ohne Neustarts.
- Ein synthetischer Benutzer wird registriert. Passwort und JWT bleiben nur im
  Speicher des Testprozesses; weder Logs noch Nachweise enthalten Zugangsdaten.

## Ablauf und Ergebnisse

| Pruefung | Beobachtung |
|---|---|
| Drei Zuweisungen vor dem Ausfall | 3 x HTTP 204; 62-151 ms |
| Fuenf parallele Zuweisungen bei blockierter Verbindung | 5 x HTTP 503; 3.470-4.456 s |
| Drei weitere Aufrufe bei offenem Circuit Breaker | 3 x HTTP 503; 34-46 ms |
| Anmeldung waehrend der Stoerung | HTTP 200; 76 ms |
| Readiness von Backend und Module-Service | Beide HTTP 200 |
| Verbindung wiederhergestellt, Breaker noch offen | 3 x HTTP 503; 29-38 ms |
| Downstream-Counter waehrend dieser drei Aufrufe | Unveraendert 117: keine Module-Aufrufe |
| Erholung nach der konfigurierten Wartezeit | 3 x HTTP 204; 75-117 ms |
| Downstream-Counter nach Erholung | 123: je ein GET und PUT pro Zuweisung |
| Pod-Identitaet, Readiness und Neustarts danach | Identisch zum Ausgangszustand, 0 Neustarts |

Das Skript entfernt kurz **nur die Ingress-Erlaubnis vom Backend zum Module-Service**.
Die separate Monitoring-Erlaubnis bleibt bestehen; deshalb kann der Test den
gesunden Module-Service gleichzeitig direkt pruefen. Dieser Test simuliert einen
Netzwerkausfall zwischen Diensten, keinen MySQL-Ausfall und keinen Pod-Absturz.

Damit Argo CD die gezielte Stoerung nicht sofort korrigiert, wird ausschliesslich
die automatische Synchronisierung der Staging-Anwendung kurz ausgesetzt. Die
urspruengliche Netzwerkregel und Argo-Konfiguration werden in `finally` restauriert.
Ein zweiter Rueckstellversuch startet nach 18 Sekunden, falls der Test-Client haengt.
Beide Rueckwege setzen eine erreichbare Kubernetes-API voraus; Restore-Patches
liegen fuer manuelle Wiederherstellung unter dem im Ergebnis genannten `tmp/`-Ordner.
Production, Datenbanken, Deployment-Spezifikationen und Secrets werden nicht umgestellt.

Der erfolgreiche Lauf stellte die Verbindung nach etwa sechs Sekunden wieder her.
Der Test belegt das Verhalten eines offenen Circuit Breakers durch schnelle 503
**auch nach Wiederherstellung** und durch unveraenderte Downstream-Counter. Die
interne Zustandsvariable wird nicht direkt ausgelesen. Die 15 Sekunden sind die
konfigurierte Offenzeit; die erste Erholungsprobe erfolgt 24 Sekunden nach Testbeginn.

Der Client ist auf maximal drei Versuche pro GET/PUT mit 200 ms Abstand begrenzt;
Verbindungsaufbau hat 1 s, die HTTP-Anfrage 2 s Timeout. Der Live-Test zeigt die
begrenzte Gesamtdauer. Die genaue Anzahl von maximal drei Versuchen wird im
Java-Test `ModuleClientTest.temporaryFailuresRetryAndThenOpenCircuit` per Zaehler
geprueft; sie wird aus dem Netzwerk-Ausfall nicht allein abgeleitet.

## Gefundener Migrations-Nachschritt

Die ersten vier Versuche kamen nicht bis zu einem aussagekraeftigen Module-Ausfall:
Fuenf parallele authentifizierte Zuweisungen warteten in PostgreSQL und liefen
nach 10 s in das Client-Timeout. Ein Kontrolllauf **ohne Stoerung** zeigte dasselbe
Verhalten. Ein JVM-Thread-Dump verortete die Arbeit im PostgreSQL-Read des
Benutzer-Lookups, nicht im Module-HTTP-Client.

In allen fuenf migrierten Tabellen waren `last_analyze` und `last_autoanalyze` leer.
Um **17:46:17** wurde ausschliesslich `ANALYZE` auf diesen Tabellen ausgefuehrt.
Der anschliessende Kontrolllauf ohne Stoerung bestand alle fuenf parallelen
Zuweisungen: **0.1149, 0.1627, 0.1989, 0.2507 und 0.2240 s**, jeweils HTTP 204.
Die Anwendung wurde dabei weder geaendert noch neu gestartet. Anschliessend
bestand der oben dokumentierte Ausfalltest. Das Restore-Skript aktualisiert nun
die Statistiken vor der Anwendungsfreigabe.

PostgreSQL 16 exportiert Planerstatistiken nicht im Dump und empfiehlt ANALYZE
nach dem Restore: [offizielle Dokumentation](https://www.postgresql.org/docs/16/app-pgdump.html).
Eine gesonderte Messung des JIT-Anteils wurde nicht vorgenommen.

## Wiederholen

Aus dem Ops-Verzeichnis mit Python 3.10+ und eingerichtetem kubectl:

```powershell
python scripts/verify-module-outage.py
python scripts/verify-module-outage.py --execute
```

Der erste Befehl liest nur den Ausgangszustand. Der zweite erzeugt eine kurze
Staging-Stoerung und einen synthetischen Testbenutzer. Waehrenddessen keine
parallelen Deployments, Lasttests oder Netzwerk-Aenderungen vornehmen. Der Test
verweigert den Start bei aktiven Jobs, laufender Argo-Synchronisierung oder mehr
als einem Backend, damit alle Proben denselben lokalen Circuit Breaker pruefen.

Im Notfall stehen im ausgegebenen Laufordner zwei bereinigte Restore-Dateien:

```powershell
kubectl --context do-fra1-vsc-orchestrierung -n user-mgmt-staging patch networkpolicy user-mgmt-module --type=merge --patch-file <Laufordner>/restore-network.json
kubectl --context do-fra1-vsc-orchestrierung -n argocd patch application user-mgmt-staging --type=merge --patch-file <Laufordner>/restore-argocd.json
```

Die Laufordner der fruehen Egress-Diagnoseversuche beziehen sich stattdessen auf
`user-mgmt-backend`; fuer den reproduzierbaren Test gilt nur die dokumentierte
Ingress-Variante. Alte Diagnose-Patches nicht versehentlich anwenden.
