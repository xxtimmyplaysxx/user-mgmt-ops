# Bestehenden Cluster importieren

Status: noch nicht ausgefuehrt. Fuer die Aufgabenstellung darf generated.tf nicht
als angeblich generiert von Hand erfunden werden. Der Import-Block referenziert
den real vorhandenen Cluster. enable_databases bleibt zuerst false.

Nach Freigabe und mit DIGITALOCEAN_TOKEN in der aktuellen Shell:

```powershell
terraform init
terraform plan -generate-config-out=generated.tf
```

generated.tf analysieren: konfliktierende/default Attribute entfernen, Name,
Region, Kubernetes-Version, VPC und Nodepool-Einstellungen parametrisieren.
Keine automatische Umstellung auf die neueste Kubernetes-Version vornehmen.
`lifecycle { prevent_destroy = true }` fuer den Cluster ergaenzen.

```powershell
terraform fmt
terraform validate
terraform plan -out=import.tfplan
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
