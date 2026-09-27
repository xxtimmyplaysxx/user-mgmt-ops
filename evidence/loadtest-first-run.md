# Erster k6-Lauf: Heap-Fehler und Korrektur

Der erste Lauf schlug fehl. Nach der unten beschriebenen Korrektur bestand der
[Wiederholungstest](loadtest-passed.md) mit 3282 erfolgreichen Logins.

27.09.2026, Jobstart 16:48:05, k6 ca. 16:48:10-16:53:13 Europe/Zurich.
Namespace `user-mgmt-staging`, Job `user-mgmt-loadtest`, Pod
`user-mgmt-loadtest-7r8fx`, Job-UID `5e1a7b91-a6fc-4952-9ee0-99af8d213c31`.
Application-Image `fd1e6343585fdf92ba437e929d23cabe1f894133`,
Ops-main `0ff90044fe42664403bfa0ae8248cbd34de5fa34`.

## Gemessene Ergebnisse

| Messwert | Ergebnis |
|---|---:|
| Virtuelle Benutzer, Rampen | 2 -> 10 -> 20 -> 0 |
| Abgeschlossene Iterationen / HTTP-Anfragen | 1950 |
| Erfolgreiche Anmeldungen | 472 (24.20%) |
| Fehlgeschlagene Anmeldungen | 1478 (75.79%) |
| Unterbrochene Iterationen | 3 |
| P95 aller HTTP-Anfragen | 1.99 s |
| P95 erfolgreicher HTTP-Antworten | 11.62 s |
| k6-Grenzwerte fuer Erfolgs-/Fehlerrate | NICHT bestanden |

Viele Verbindungsfehler waren sehr schnell. Daher ist der niedrige P95 ueber ALLE
Requests kein Beleg fuer gute Antwortzeiten; der P95 erfolgreicher Antworten
liegt deutlich darueber. Der Wiederholungstest prueft deshalb zusaetzlich den
P95 mit `expected_response:true` gegen dieselben drei Sekunden. Die bisherigen
Erfolgsgrenzen und die Laststufen bleiben bestehen.

## Ursache aus Logs, Events und Metriken

Im vorherigen Container-Log des zweiten Backends steht:

```text
2026-09-27T14:50:38.259Z ERROR ... Failed to complete processing of a request
java.lang.OutOfMemoryError: Java heap space
  at org.bouncycastle.crypto.generators.Argon2BytesGenerator$Block.<init>
```

Die Anwendung prueft Passwoerter mit
`Argon2PasswordEncoder.defaultsForSpringSecurity_v5_8()`. Die Bibliothek benoetigt
pro gleichzeitigem Argon2-Aufruf rund 16 MiB Arbeitsdaten plus Java-Overhead.
[Spring-API](https://docs.spring.io/spring-security/site/docs/current/api/org/springframework/security/crypto/argon2/Argon2PasswordEncoder.html).
Die Ressourcenintensitaet ist Teil des Passwortschutzes; Passwortpruefung und
Hash-Parameter werden fuer den Wiederholungstest nicht abgeschwaecht.

Die gleiche Container-JVM meldet bei `-XX:+PrintFlagsFinal`:

```text
MaxHeapSize = 134217728             # 128 MiB
MaxRAMPercentage = 25.000000
UseSerialGC = true
```

Das Containerlimit von 512 MiB ist nicht gleich dem Java-Heaplimit. Die
[Java-Dokumentation](https://docs.oracle.com/en/java/javase/25/docs/specs/man/java.html)
beschreibt die automatische Heapbemessung und `-Xmx`.

Prometheus fuer 16:46-16:55 Uhr zeigt CPU-Spitzen von ca. 0.5 Cores pro Backend
(jeweiliges Limit), zeitweise fast alle CPU-Quota-Perioden gedrosselt und
0-2 verfuegbare Backend-Replikas. Container-OOM-Zaehler blieben null: Es handelt
sich um erschoepften Java-Heap, nicht um einen nachgewiesenen Kernel-OOM-Kill.
Die Pod-Events belegen Liveness-Timeouts und dadurch ausgeloeste Neustarts.
Nach dem Lauf: erster Backend-Pod zwei Restarts, zweiter ein Restart; beide
anschliessend wieder Ready. Originalausgaben sind lokal unter dem ignorierten
`tmp/loadtest-first/` gesichert (keine Zugangsdaten).

Der HPA stand waehrend des Tests auf zwei Replikas. Ein zweiter Pod wurde bereits
vor Jobstart angefordert; der erste Lauf ist deshalb auch kein sauber isolierter
Nachweis fuer durch k6 ausgeloestes Scale-out und anschliessendes Scale-in.

## Korrektur

In Staging wurden folgende Einstellungen angepasst:

- Heap initial 128 MiB / maximal 256 MiB im weiterhin 512-MiB-Container;
  `ExitOnOutOfMemoryError` beendet einen bei erneutem Heapmangel defekten Prozess.
- Maximal acht Tomcat-Worker (zwei im Leerlauf), damit die speicherintensive
  Passwortpruefung nur begrenzt gleichzeitig laeuft.
- CPU-Request 250m / Limit 1 Core, Memory-Request 384 MiB.
- Liveness-Timeout 5 s mit sechs Fehlversuchen; Readiness-Timeout 3 s.
  Startup-Probe bleibt aktiv. Gesundheitspruefungen werden nicht abgeschaltet.
- HPA weiterhin 1-2 Pods, Ziel 60% von 250m = 150m pro Pod. Der vorherige
  absolute Schwellwert von 20m fuehrte bereits im Leerlauf zu wiederholtem Skalieren.
- CPU-Limit-Quota 5 fuer zwei Replikas, einen Rolling-Update-Pod und k6;
  keine zusaetzlichen Worker oder neuen Cloud-Ressourcen.

Pruefungen vor Rollout: Helm lint fuer beide Umgebungen, bestehende Render-Checks,
semantischer Vergleich aller Production-Manifeste (unveraendert), Server-Dry-Run
von Staging-Deployments/HPA/Quota gegen die aktiven Policies. Die vorhandene
Container-JVM akzeptiert die vorgeschlagenen Flags und meldet 256 MiB MaxHeapSize.

## Korrektur ausgerollt, 17:06-17:08 Uhr

Ops PR 5 wurde gemergt; die Revision lautet
`b8bd1dedc903cec87cbc1ca3e8cb3f7104c1bd9a`. Argo CD hat diese Revision synchronisiert,
`kubectl rollout status` ist erfolgreich. Das neue Backend-ReplicaSet heisst
`user-mgmt-backend-7f5548cc65`. Live-Konfiguration enthaelt die oben genannten
JVM-/Thread-, Ressourcen- und Probe-Einstellungen. Der HPA verwendet 60% von
250m; Prometheus bestaetigt die groessere Heap-Kapazitaet der laufenden Anwendung.

Login des bestehenden Lasttest-Benutzers sowie alle sechs HTTP-E2E-Faelle
(Zuweisung, Wiederholung, fehlendes Modul, ungueltige ID, ohne Anmeldung,
fremder Benutzer) bestehen erneut. Neue Backend-Pods haben keine Restarts.
Der Start verursachte zunaechst ein voruebergehendes Scale-out; vor dem neuen
Lasttest wird deshalb explizit auf einen stabilen einzelnen Pod gewartet.
17:08:49-17:09:37 Uhr: Vier aufeinanderfolgende Messungen bestaetigen genau einen
Ready-Pod, null Restarts und HPA current=desired=1. Argo CD ist Synced/Healthy.
Die Ausgangslage fuer die Wiederholung ist damit dokumentiert.

Der erste fehlgeschlagene Job wurde erst nach Sicherung der vollstaendigen Logs
und Job-Metadaten sowie Pruefung von UID und Failed-Status entfernt. Die ConfigMap
war aktualisiert, das Secret wurde wiederverwendet. Der neue Job wurde vor
seinem Start per Server-Dry-Run geprueft.

Beim ersten Cleanup-Versuch war der Kyverno-Webhook kurz nicht erreichbar.
Der einzelne Admission-Controller hatte nach fehlgeschlagener Lease-Erneuerung
neu gestartet (Exitcode 0, kein OOM). Nach seiner Erholung funktionierten Cleanup
und Admission wieder; alle vier Controller waren Ready. Policies wurden nicht
umgangen. Dies zeigt die bereits dokumentierte Einschraenkung der Kursinstallation
mit nur einer Admission-Replik.

Die Wiederholung lief von 17:10 bis 17:15 Uhr. Alle Grenzwerte bestanden;
der HPA skalierte anschliessend wieder auf eine Replika zurueck.
[Ergebnisse und Messkurven](loadtest-passed.md).
