"""Offline manifest assertions on Helm-rendered application YAML."""
import sys
import yaml

docs = [d for d in yaml.safe_load_all(open(sys.argv[1], encoding="utf-8-sig")) if d]
assert not any(d["kind"] == "PersistentVolumeClaim" for d in docs), "Local database PVC remains"
deployments = {d["metadata"]["name"]: d for d in docs if d["kind"] == "Deployment"}
assert set(deployments) == {"user-mgmt-backend", "user-mgmt-frontend", "user-mgmt-module"}
for d in deployments.values():
    spec = d["spec"]["template"]["spec"]
    assert spec["securityContext"]["runAsNonRoot"]
    for c in spec["containers"] + spec.get("initContainers", []):
        assert not c["securityContext"]["allowPrivilegeEscalation"]
        for key in ("requests", "limits"):
            assert {"cpu", "memory"} <= c["resources"][key].keys()
assert len([d for d in docs if d["kind"] == "ServiceMonitor"]) == 2
assert len([d for d in docs if d["kind"] == "PrometheusRule"]) == 1
backend = deployments["user-mgmt-backend"]["spec"]["template"]["spec"]["containers"][0]
assert backend["envFrom"][-1]["secretRef"]["name"] == "user-mgmt-managed-postgres"
print("Managed DB, monitoring, module deployment and security assertions passed")
