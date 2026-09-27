# Bestehenden Cluster importieren

Status: generated.tf wurde am 27.09. aus dem realen Cluster erzeugt und lokal
bereinigt. Konfliktierende deaktivierte DRA-Bloecke wurden entfernt, die vom API
gemeldete Worker-Anzahl 1 uebernommen und Werte parametrisiert. Ein
prevent_destroy-Lifecycle schuetzt vor geplanter Cluster-Loeschung. fmt und validate
sind erfolgreich. Nach ausdruecklicher Bestaetigung, dass Pruefung 2 abgeschlossen
ist, wurde der gespeicherte Importplan angewendet: 1 imported, 0 added, 0 changed,
0 destroyed. Der anschliessende Plan endete mit Exitcode 0 und "No changes".
Anschliessend wurden Managed PostgreSQL 16 und MySQL 8.4 angelegt; auch danach
zeigte der Plan "No changes". Die lokale terraform.tfvars haelt nun
enable_databases=true und node_count=2 fest. Die Erweiterung auf zwei Worker wurde
angewendet; beide sind Ready, Kontrollplan erneut "No changes" (Exitcode 0).
Das Staging-Backup wurde erfolgreich mit TLS und Datenvergleich wiederhergestellt.
Die endgueltige Datenbank-Umschaltung der Anwendung steht noch aus.

Der Import muss auf diesem Rechner nicht erneut ausgefuehrt werden. Die folgenden
Schritte dokumentieren den durchgefuehrten Ablauf. Der lokale State gehoert nicht
in Git und muss fuer weitere Arbeiten erhalten bleiben.

Die folgenden Befehle beschreiben die erstmalige Generierung, wenn generated.tf
noch NICHT existiert. Dabei benoetigt der Import-Block `provider = digitalocean`.
Sobald die Ressource existiert, steht diese Zuordnung in der Ressource.
Mit der bereits vorhandenen Datei direkt bei `terraform fmt` weitermachen.

```powershell
terraform init
terraform plan "-generate-config-out=generated.tf"
```

generated.tf analysieren: konfliktierende/default Attribute entfernen, Name,
Region, Kubernetes-Version, VPC und Nodepool-Einstellungen parametrisieren.
Keine automatische Umstellung auf die neueste Kubernetes-Version vornehmen.
`lifecycle { prevent_destroy = true }` fuer den Cluster ergaenzen.

```powershell
terraform fmt
terraform validate
terraform plan "-out=import.tfplan"
```

Der erste Plan soll genau den Import enthalten, keine Loeschung/Neuerstellung
und keine unbeabsichtigte Aenderung. Erst dann `terraform apply import.tfplan`.
Anschliessend muss ein weiterer Plan keine Cluster-Aenderungen zeigen.
Der Provider kann beim Import den Default-Nodepool taggen; deshalb wird selbst
die Import-Generierung erst nach Aufhebung der Clustersperre gestartet.

Danach separat Datenbanken aktivieren:

```powershell
terraform plan -var=enable_databases=true -out=databases.tfplan
```

Die Datenbanken kosten Geld. Plan vor Ausfuehrung pruefen. Nach Anlage
`enable_databases=true` dauerhaft in einer lokalen terraform.tfvars festhalten,
damit spaetere Plaene keine Entfernung vorschlagen. prevent_destroy blockiert
versehentliche Loeschung, ersetzt aber kein Backup.
