"""Render exported Prometheus series as a reproducible submission figure (matplotlib)."""
import argparse
import datetime as dt
import json
from pathlib import Path
from zoneinfo import ZoneInfo

import matplotlib
matplotlib.use('Agg')
import matplotlib.dates as mdates
import matplotlib.pyplot as plt

parser = argparse.ArgumentParser()
parser.add_argument('metrics')
parser.add_argument('output')
args = parser.parse_args()
data = json.loads(Path(args.metrics).read_text(encoding='utf-8'))
zone = ZoneInfo('Europe/Zurich')
to_time = lambda value: dt.datetime.fromtimestamp(value, zone)
window = [dt.datetime.fromisoformat(data[key].replace('Z', '+00:00')) for key in ('start', 'end')]
job_start = dt.datetime.fromisoformat(data['job']['status']['startTime'].replace('Z', '+00:00'))
job_end = dt.datetime.fromisoformat(data['job']['status']['completionTime'].replace('Z', '+00:00'))

plt.rcParams.update({'font.family': 'DejaVu Sans', 'font.size': 10, 'axes.spines.top': False,
                     'axes.spines.right': False, 'axes.titleweight': 'bold'})
fig, axes = plt.subplots(3, 2, figsize=(14, 10), sharex=True)
fig.subplots_adjust(top=.86, bottom=.09, left=.07, right=.97, hspace=.40, wspace=.22)
k6 = data['k6']
fig.suptitle('Staging: Lasttest und automatische Skalierung', x=.07, ha='left', y=.975, fontsize=19, weight='bold')
fig.text(.07, .925, f"{job_start.astimezone(zone):%d.%m.%Y} · {k6['successful_logins']:,}/{k6['requests']:,} erfolgreiche Logins · HTTP-Fehler {k6['http_failed_percent']:g}% · k6 P95 {k6['p95_seconds']:g} s · {k6['max_vus']} VUs", fontsize=12)
fig.text(.07, .89, 'Blaue Fläche: Laufzeit des k6-Jobs. Kurven: Prometheus, 15-s-Abfrage; CPU und HTTP-Raten mit 1-min-Fenster.', fontsize=9, color='#516172')

def draw(axis, key, factor=1, label=None, step=False):
    for series in data['series'][key]['result']:
        points = series['values']
        name = label or series['metric'].get('pod', key)
        if name.startswith('user-mgmt-backend-'):
            name = 'Backend …' + name.rsplit('-', 1)[-1]
        axis.plot([to_time(x[0]) for x in points], [float(x[1]) * factor for x in points],
                  label=name, linewidth=1.8, drawstyle='steps-post' if step else 'default')

for axis in axes.flat:
    axis.axvspan(job_start, job_end, color='#eaf1fb', zorder=0)
    axis.grid(alpha=.20)
    axis.set_xlim(window)
    axis.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M', tz=zone))

draw(axes[0,0], 'desired_replicas', label='HPA Soll', step=True)
draw(axes[0,0], 'available_replicas', label='Backend verfügbar', step=True)
replicas = []
for _, value in data['series']['desired_replicas']['result'][0]['values']:
    value = int(float(value))
    if not replicas or replicas[-1] != value:
        replicas.append(value)
maximum = max(replicas)
axes[0,0].set(title='Replikas: ' + ' → '.join(map(str, replicas)), ylabel='Pods',
              ylim=(0, maximum + .4), yticks=range(maximum + 1))
axes[0,0].legend(loc='lower right', fontsize=9)
draw(axes[0,1], 'cpu_cores')
axes[0,1].set(title='CPU je Backend-Pod', ylabel='CPU-Kerne')
axes[0,1].axhline(.15, color='#8a5a00', linestyle=':', label='HPA-Ziel 0,15 Core')
axes[0,1].legend(fontsize=8, loc='upper right')
draw(axes[1,0], 'memory_bytes', factor=1/1024**2)
axes[1,0].axhline(512, color='#b33c30', linestyle=':', label='Containerlimit 512 MiB')
axes[1,0].set(title='Arbeitsspeicher je Backend-Pod', ylabel='MiB', ylim=(0,560))
axes[1,0].legend(fontsize=8, loc='lower right')
draw(axes[1,1], 'request_rate')
axes[1,1].set(title='API-Anfragen am Backend (ohne Actuator)', ylabel='Anfragen / Sekunde')
draw(axes[2,0], 'request_p95_seconds', label='Server-P95')
axes[2,0].axhline(3, color='#b33c30', linestyle=':', label='k6-Grenze 3 s')
axes[2,0].set(title='Server-P95 (Histogramm-Schätzung)', ylabel='Sekunden')
axes[2,0].legend(fontsize=8)
draw(axes[2,1], 'server_5xx_ratio', factor=100)
axes[2,1].set(title='Serverseitiger 5xx-Anteil der API', ylabel='Prozent', ylim=(-.02,1))
for axis in (axes[0,1], axes[1,1], axes[2,0]):
    axis.set_ylim(bottom=0)
for axis in axes[-1,:]:
    axis.set_xlabel('Uhrzeit Europe/Zurich')
fig.text(.07, .025, 'Der k6-Nachweis misst die HTTP-Erfolgsrate dieses Testlaufs. Er ist keine allgemeine Verfügbarkeitsgarantie.', fontsize=9, color='#516172')
fig.savefig(args.output, dpi=150, facecolor='white')
print(args.output)
