import json
import os

base = "/Users/midir/Documents/Codex/2026-10-21/https-github-com-oh-ashen-one/work/relay-manager"

rows = []
for name in ("customuse-wave01.json", "customuse-wave01-more.json"):
    path = os.path.join(base, name)
    if not os.path.exists(path):
        continue
    with open(path) as fh:
        for item in json.load(fh):
            delivery = item.get("delivery", {})
            latest = item.get("latest") or {}
            model_url = ""
            for model in latest.get("models", []):
                model_url = model.get("modelUrl", "")
                break
            rows.append({
                "id": item.get("id"),
                "file": os.path.basename(delivery.get("file", "")),
                "sha256": delivery.get("sha256", ""),
                "url": model_url,
                "bytes": delivery.get("bytes", 0),
                "source": "Customuse",
            })

tripo = os.path.join(base, "tripo-wave01.json")
if os.path.exists(tripo):
    with open(tripo) as fh:
        data = json.load(fh)
    for job in data.get("jobs", []):
        rows.append({
            "id": job.get("request_id"),
            "file": os.path.basename(job.get("file") or job.get("local_file") or ""),
            "sha256": job.get("sha256", ""),
            "url": job.get("download_url") or job.get("model_url") or job.get("view_url", ""),
            "bytes": job.get("bytes", 0),
            "source": "Tripo",
        })

for row in rows:
    print(row["id"], row["file"], row["bytes"], row["sha256"][:12], row["url"][:80], row["source"])
