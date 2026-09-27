# Aufgabe 5: Kyverno-Admission live nachgewiesen

Geprueft am 27.09.2026, 16:35-16:47 Uhr Europe/Zurich.
Cluster-Kontext: `do-fra1-vsc-orchestrierung`.

- Helm-Release `kyverno`, Namespace `policy`, Revision 1, deployed.
- Chart 3.9.1 / Kyverno v1.19.1; alle vier Controller Ready, keine Restarts.
- Drei ClusterPolicies Ready mit `failureAction: Enforce`:
  `vsc-require-resources`, `vsc-require-nonroot`, `vsc-require-versioned-images`.
- Nur Namespace `user-mgmt-staging` traegt `vsc-policies=enforce`.
  Die drei laufenden Staging-Deployments und ihre Pods melden jeweils 3 PASS/0 FAIL.
- Beide Argo-CD-Anwendungen weiterhin Synced/Healthy.

## Erwartete Ablehnung

```powershell
kubectl --context do-fra1-vsc-orchestrierung apply --dry-run=server -f policy/invalid-deployment.yaml
```

Gekuerzte tatsaechliche Ausgabe (Exitcode 1):

```text
admission webhook "validate.kyverno.svc-fail" denied the request
resource Deployment/user-mgmt-staging/deliberately-invalid was blocked
vsc-require-nonroot: autogen-nonroot
vsc-require-resources: autogen-requests-and-limits
vsc-require-versioned-images: autogen-explicit-version
```

Das Beispiel benutzt nginx:latest, keine Requests/Limits und keinen Non-root-
Sicherheitskontext. Der Server-Dry-Run durchlaeuft die echten Admission-Webhooks,
legt jedoch kein Deployment an. Die Abwesenheit des Test-Deployments wurde geprueft.

## Gegenproben und Grenzen

`python scripts/verify-policies.py` besteht alle zwoelf Live-Admission-Pruefungen:

- Gueltiges Deployment und gueltiger Init-Container werden akzeptiert.
- Fehlende Ressourcen/Sicherheitskontexte und latest-Images werden jeweils fuer
  normale Container und Init-Container abgelehnt (sechs Gegenbeispiele).
- Container duerfen Non-root nicht mit runAsNonRoot=false, runAsUser=0 oder
  privileged=true umgehen (drei Gegenbeispiele).
- Ein Deployment mit latest im unmarkierten Production-Namespace wird im reinen
  Server-Dry-Run akzeptiert; damit ist die Namespace-Begrenzung nachgewiesen.

Zusaetzlich wurden alle drei aktuellen, mit Helm gerenderten Staging-Deployments
und der vorbereitete k6-Job per Server-Dry-Run akzeptiert. Kein Test-Workload wurde
dabei erstellt. Der anschliessende k6-Lauf ist im [Lasttestbericht](loadtest-passed.md) dokumentiert.

Die Hintergrundberichte enthalten auch alte ReplicaSets mit null Replikas und
den bereits abgeschlossenen `load-generator` aus dem frueheren Unterricht.
Deren alte Vorlagen koennen FAIL anzeigen; die aktuell laufenden Anwendungs-Pods
und Deployments sind konform. Admission-Regeln loeschen bestehende Objekte nicht.

Die Kurskonfiguration nutzt eine Admission-Replik und ist nicht hochverfuegbar.
PolicyExceptions bleiben deaktiviert. Kyverno v1.19.1 meldet ClusterPolicy als
deprecated, unterstuetzt sie in dieser gepinnten Version aber noch. Die Aufgabe
verlangt explizit drei ClusterPolicies; vor einem kuenftigen Upgrade ist die
Migration auf die neuen Policy-Typen einzuplanen.
