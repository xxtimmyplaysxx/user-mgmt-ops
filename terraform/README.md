# Terraform

Terraform verwaltet den bestehenden DigitalOcean-Kubernetes-Cluster sowie
Managed PostgreSQL und MySQL. Der Cluster wurde importiert und nicht neu erstellt.

## Dateien

| Datei | Inhalt |
|---|---|
| [provider.tf](provider.tf) | Provider `digitalocean/digitalocean`, Token aus der Umgebung |
| [imports.tf](imports.tf) | Import des Clusters `7e46ab36-b79c-4dea-8301-2a2a998822c5` |
| [generated.tf](generated.tf) | Generierte und anschliessend bereinigte Cluster-Konfiguration |
| [variables.tf](variables.tf) | Name, Region, Kubernetes-Version, VPC, Nodepool und Grössen |
| [databases.tf](databases.tf) | PostgreSQL 16, MySQL 8.4, Datenbanken und Firewalls |
| [.terraform.lock.hcl](.terraform.lock.hcl) | Festgelegte Provider-Version |

## Durchgeführter Import

Vor der Erstellung von `generated.tf` wurde der Import-Block angelegt.
Bei dieser ersten Generierung war `provider = digitalocean` im Import-Block
gesetzt; in der fertigen Konfiguration steht die Zuordnung in der Ressource.

```powershell
terraform init
terraform plan "-generate-config-out=generated.tf"
```

Die generierte Datei enthielt widersprüchliche GPU-Optionen und `node_count = 0`,
obwohl ein Worker lief. Die deaktivierten DRA-Blöcke wurden entfernt, die
Worker-Anzahl korrigiert und die wiederverwendbaren Werte durch Variablen ersetzt.
`prevent_destroy` schützt den Cluster vor einer geplanten Löschung.

Nach `terraform fmt` und `terraform validate` wurde ein Importplan erstellt.
Er enthielt genau einen Import, ohne Neuanlage, Änderung oder Löschung.

```text
Apply complete! Resources: 1 imported, 0 added, 0 changed, 0 destroyed.
No changes. Your infrastructure matches the configuration.
```

Danach wurden separat die beiden Managed-Datenbanken angelegt und der Cluster
auf zwei Worker erweitert. Beim ersten Datenbanklauf lehnte die API die
MySQL-Version `8` ab; mit `8.4` war die Anlage erfolgreich.
Die PostgreSQL-Migration ist [abgeschlossen](../evidence/postgres-final-copy.md).

## Aktuelle Konfiguration prüfen

Der Import und die Generierung müssen auf diesem Rechner nicht wiederholt werden.
Der bestehende lokale State wird weiterverwendet. Die lokale `terraform.tfvars` enthält:

```hcl
enable_databases = true
node_count       = 2
```

Diese Werte weichen bewusst von den Startwerten in `variables.tf` ab, die für
den ursprünglichen Import mit einem Worker und ohne Datenbanken vorgesehen waren.

Mit eingerichteter doctl-Anmeldung, aus dem Verzeichnis `terraform/`:

```powershell
$env:DIGITALOCEAN_TOKEN = (doctl auth token).Trim()
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -detailed-exitcode
Remove-Item Env:DIGITALOCEAN_TOKEN
```

Die Abschlusskontrolle am 27.09.2026 um 17:55 Uhr ergab `No changes`, Exitcode 0.
Token, State, Pläne und lokale Variablenwerte sind von Git ausgeschlossen.
Der State enthält sensible Verbindungsdaten und wird lokal aufbewahrt.
