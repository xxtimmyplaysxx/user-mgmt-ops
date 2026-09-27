# Argo CD

Argo CD läuft im Namespace `argocd` auf dem bestehenden DigitalOcean-Cluster.
Beide Anwendungen verwenden den Helm-Chart `charts/user-mgmt` aus dem Branch `main`.

| Anwendung | Namespace | Werte |
|---|---|---|
| [Staging](application-staging.yaml) | `user-mgmt-staging` | `values-staging.yaml` |
| [Production](application-production.yaml) | `user-mgmt-production` | `values-prod.yaml` |

`CreateNamespace` legt bei Bedarf den Ziel-Namespace an.
`selfHeal` korrigiert Abweichungen vom Git-Stand; `prune` entfernt Ressourcen,
die nicht mehr in den gerenderten Manifesten enthalten sind.
Das betrifft auch PVCs, wenn sie aus dem Chart entfernt werden.

Die CI-Pipeline des Application-Repositories aktualisiert nur die Staging-Image-Tags.
Die Production-Tags bleiben in ihrer eigenen Werte-Datei festgelegt.

## Anwendungen und Status

Bei bereits installiertem Argo CD:

```powershell
kubectl --context do-fra1-vsc-orchestrierung apply -f argocd/application-staging.yaml -f argocd/application-production.yaml
kubectl --context do-fra1-vsc-orchestrierung -n argocd get applications
```

Zugriff auf die Oberfläche:

```powershell
kubectl --context do-fra1-vsc-orchestrierung -n argocd port-forward svc/argocd-server 8080:443
```

Danach `https://localhost:8080` im Browser öffnen.
