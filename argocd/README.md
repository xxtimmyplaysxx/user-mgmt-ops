# Argo CD bootstrap

These files are prepared locally and must only be applied after the dedicated
DigitalOcean Kubernetes cluster has been created and its cost has been approved.

1. Create the dedicated namespace:

   `kubectl create namespace argocd`

2. Install the course-approved Argo CD release into `argocd`.
3. Replace all `example.com` hosts with the real DNS names.
4. Make the GitHub Container Registry packages public or configure an image pull secret.
5. Apply `application-staging.yaml` and `application-production.yaml`.
6. Verify both applications with `kubectl get applications -n argocd`.

For a safe local dashboard connection without public exposure:

`kubectl port-forward service/argocd-server -n argocd 8080:443`
