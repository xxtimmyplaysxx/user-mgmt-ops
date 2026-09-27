"""Generate reproducible Grafana ConfigMaps; no cluster access."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def dashboard(uid, title, queries):
    panels = []
    for i, (name, expr, unit) in enumerate(queries):
        legend = {
            "CPU per pod": "{{namespace}} / {{pod}}",
            "Memory per pod": "{{namespace}} / {{pod}}",
            "Available backend replicas": "{{deployment}}",
            "HPA desired replicas": "{{horizontalpodautoscaler}}",
        }.get(name, title.removeprefix("VSC - ").removesuffix(" RED"))
        panels.append({"id": i + 1, "type": "timeseries", "title": name,
                       "gridPos": {"x": i % 2 * 12, "y": i // 2 * 8, "w": 12, "h": 8},
                       "datasource": {"type": "prometheus", "uid": "prometheus"},
                       "targets": [{"refId": "A", "expr": expr, "legendFormat": legend}],
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


def error_ratio(metric, selector):
    total = f'sum(rate({metric}{{{selector}}}[2m]))'
    errors = f'sum(rate({metric}{{{selector},status=~"5.."}}[2m]))'
    # Zero errors is a valid value even before the first 5xx series exists.
    # Keep no-data when the entire application's request metric is absent.
    return f'({errors} or (0 * {total})) / clamp_min({total},0.001)'


dashboard("vsc-infrastructure", "VSC - Kubernetes CPU, Memory and HPA", [
    ("CPU per pod", 'sum by (namespace,pod) (rate(container_cpu_usage_seconds_total{namespace=~"user-mgmt.*",container!="",container!="POD"}[2m]))', "cores"),
    ("Memory per pod", 'sum by (namespace,pod) (container_memory_working_set_bytes{namespace=~"user-mgmt.*",container!="",container!="POD"})', "bytes"),
    ("Available backend replicas", 'kube_deployment_status_replicas_available{namespace="user-mgmt-staging",deployment="user-mgmt-backend"}', "short"),
    ("HPA desired replicas", 'kube_horizontalpodautoscaler_status_desired_replicas{namespace="user-mgmt-staging"}', "short"),
])
dashboard("vsc-user-service", "VSC - User Service RED", [
    ("Request rate", 'sum(rate(http_server_requests_seconds_count{namespace="user-mgmt-staging",uri!~"/actuator.*"}[2m]))', "reqps"),
    ("P95 response time", 'histogram_quantile(0.95,sum by (le) (rate(http_server_requests_seconds_bucket{namespace="user-mgmt-staging",uri!~"/actuator.*"}[2m])))', "s"),
    ("5xx error ratio", error_ratio('http_server_requests_seconds_count', 'namespace="user-mgmt-staging",uri!~"/actuator.*"'), "percentunit"),
])
dashboard("vsc-module-service", "VSC - Module Service RED", [
    ("Request rate", 'sum(rate(module_http_requests_total{namespace="user-mgmt-staging"}[2m]))', "reqps"),
    ("P95 response time", 'histogram_quantile(0.95,sum by (le) (rate(module_http_request_duration_seconds_bucket{namespace="user-mgmt-staging"}[2m])))', "s"),
    ("5xx error ratio", error_ratio('module_http_requests_total', 'namespace="user-mgmt-staging"'), "percentunit"),
])
