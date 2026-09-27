"""Generate reproducible Grafana ConfigMaps; no cluster access."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def dashboard(uid, title, queries):
    panels = []
    for i, (name, expr, unit) in enumerate(queries):
        panels.append({"id": i + 1, "type": "timeseries", "title": name,
                       "gridPos": {"x": i % 2 * 12, "y": i // 2 * 8, "w": 12, "h": 8},
                       "datasource": {"type": "prometheus", "uid": "prometheus"},
                       "targets": [{"refId": "A", "expr": expr, "legendFormat": "{{pod}} {{route}}"}],
                       "fieldConfig": {"defaults": {"unit": unit}, "overrides": []}})
    doc = {"uid": uid, "title": title, "schemaVersion": 39, "version": 1,
           "refresh": "10s", "time": {"from": "now-30m", "to": "now"},
           "tags": ["VSC"], "panels": panels}
    data = json.dumps(doc, indent=2)
    (ROOT / "monitoring" / f"{uid}.yaml").write_text(
        "apiVersion: v1\nkind: ConfigMap\nmetadata:\n"
        f"  name: {uid}\n  namespace: monitoring\n"
        "  labels:\n    grafana_dashboard: '1'\ndata:\n"
        f"  {uid}.json: |\n" + "\n".join("    " + line for line in data.splitlines()) + "\n",
        encoding="utf-8")


dashboard("vsc-infrastructure", "VSC - Kubernetes CPU, Memory and HPA", [
    ("CPU per pod", 'sum by (namespace,pod) (rate(container_cpu_usage_seconds_total{namespace=~"user-mgmt.*",container!="",container!="POD"}[2m]))', "cores"),
    ("Memory per pod", 'sum by (namespace,pod) (container_memory_working_set_bytes{namespace=~"user-mgmt.*",container!="",container!="POD"})', "bytes"),
    ("Available backend replicas", 'kube_deployment_status_replicas_available{namespace="user-mgmt-staging",deployment="user-mgmt-backend"}', "short"),
    ("HPA desired replicas", 'kube_horizontalpodautoscaler_status_desired_replicas{namespace="user-mgmt-staging"}', "short"),
])
dashboard("vsc-user-service", "VSC - User Service RED", [
    ("Request rate", 'sum(rate(http_server_requests_seconds_count{namespace="user-mgmt-staging",uri!~"/actuator.*"}[2m]))', "reqps"),
    ("P95 response time", 'histogram_quantile(0.95,sum by (le) (rate(http_server_requests_seconds_bucket{namespace="user-mgmt-staging",uri!~"/actuator.*"}[2m])))', "s"),
    ("5xx error ratio", 'sum(rate(http_server_requests_seconds_count{namespace="user-mgmt-staging",status=~"5..",uri!~"/actuator.*"}[2m])) / clamp_min(sum(rate(http_server_requests_seconds_count{namespace="user-mgmt-staging",uri!~"/actuator.*"}[2m])),0.001)', "percentunit"),
])
dashboard("vsc-module-service", "VSC - Module Service RED", [
    ("Request rate", 'sum(rate(module_http_requests_total{namespace="user-mgmt-staging"}[2m]))', "reqps"),
    ("P95 response time", 'histogram_quantile(0.95,sum by (le) (rate(module_http_request_duration_seconds_bucket{namespace="user-mgmt-staging"}[2m])))', "s"),
    ("5xx error ratio", 'sum(rate(module_http_requests_total{namespace="user-mgmt-staging",status=~"5.."}[2m])) / clamp_min(sum(rate(module_http_requests_total{namespace="user-mgmt-staging"}[2m])),0.001)', "percentunit"),
])
