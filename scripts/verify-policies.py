"""Live admission checks using server dry-run only; creates no workloads."""
import copy
import json
import subprocess

CONTEXT = "do-fra1-vsc-orchestrierung"
NAMESPACE = "user-mgmt-staging"
container = {
    "name": "example", "image": "registry.k8s.io/pause:3.10",
    "securityContext": {"allowPrivilegeEscalation": False, "capabilities": {"drop": ["ALL"]}},
    "resources": {"requests": {"cpu": "10m", "memory": "16Mi"},
                  "limits": {"cpu": "100m", "memory": "32Mi"}},
}
base = {
    "apiVersion": "apps/v1", "kind": "Deployment",
    "metadata": {"name": "vsc-policy-probe", "namespace": NAMESPACE},
    "spec": {"replicas": 1, "selector": {"matchLabels": {"app": "vsc-policy-probe"}},
             "template": {"metadata": {"labels": {"app": "vsc-policy-probe"}},
                          "spec": {"securityContext": {"runAsNonRoot": True, "runAsUser": 1001,
                                                       "seccompProfile": {"type": "RuntimeDefault"}},
                                   "containers": [container]}}},
}


def check(label, manifest, rejected_by=None):
    result = subprocess.run(
        ["kubectl", "--context", CONTEXT, "apply", "--dry-run=server", "-f", "-"],
        input=json.dumps(manifest), capture_output=True, text=True, timeout=45,
    )
    output = result.stdout + result.stderr
    if rejected_by:
        assert result.returncode != 0 and rejected_by in output and "denied the request" in output, output
        print(f"PASS {label}: rejected by {rejected_by}")
    else:
        assert result.returncode == 0, output
        print(f"PASS {label}: admitted in server dry-run")


check("valid deployment", base)
for field, policy in [("resources", "vsc-require-resources"),
                      ("securityContext", "vsc-require-nonroot"),
                      ("image", "vsc-require-versioned-images")]:
    for init in (False, True):
        manifest = copy.deepcopy(base)
        pod = manifest["spec"]["template"]["spec"]
        if init:
            pod["initContainers"] = [copy.deepcopy(container)]
            pod["initContainers"][0]["name"] = "setup"
        target = pod["initContainers" if init else "containers"][0]
        if field == "image":
            target["image"] = "registry.k8s.io/pause:latest"
        else:
            del target[field]
        check(f"{'init' if init else 'app'} container missing/invalid {field}", manifest, policy)

for key, value in [("runAsNonRoot", False), ("runAsUser", 0), ("privileged", True)]:
    manifest = copy.deepcopy(base)
    security = manifest["spec"]["template"]["spec"]["containers"][0]["securityContext"]
    security[key] = value
    if key == "privileged":
        # Kubernetes rejects privileged=true with escalation=false before admission.
        security["allowPrivilegeEscalation"] = True
    check(f"container override {key}={value}", manifest, "vsc-require-nonroot")

manifest = copy.deepcopy(base)
manifest["spec"]["template"]["spec"]["initContainers"] = [copy.deepcopy(container)]
manifest["spec"]["template"]["spec"]["initContainers"][0]["name"] = "setup"
check("valid init container", manifest)

manifest = copy.deepcopy(base)
manifest["metadata"]["namespace"] = "user-mgmt-production"
manifest["spec"]["template"]["spec"]["containers"][0]["image"] = "registry.k8s.io/pause:latest"
check("unlabelled production namespace outside course-policy scope", manifest)
print("All checks used server dry-run; no Deployment or Pod was created.")
