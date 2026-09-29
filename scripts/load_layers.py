"""Upload the GeoJSON layers to Supabase's private.staging table.

One-time loader used with the temporary public.stage_features RPC.

Usage (PowerShell):
    $env:LOAD_TOKEN = "<token from: select token from private.load_token;>"
    python scripts/load_layers.py

Only the Pavement rows of Roads.geojson are sent; the other rows repeat the
same centerlines for drainage, shoulders, etc. Coordinates are rounded to
6 decimals (~10 cm) and Z values are dropped.
"""

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

SUPABASE_URL = "https://lzyppxkivzwdtsxdquso.supabase.co"
SUPABASE_KEY = "sb_publishable_9881RD-FP11p3UssyK3UFQ_1GrN0j3E"

ROOT = Path(__file__).resolve().parent.parent
LAYERS = [
    ("roads", "Roads.geojson", lambda p: p.get("TYP_FEAT") == "Pavement"),
    ("marina_sites", "Marina_Sites.geojson", None),
    ("school_properties", "Statewide_School_Property.geojson", None),
    ("recreation_areas", "Recreation_Areas.geojson", None),
]
MAX_BATCH_BYTES = 1_000_000  # keeps each call well under the anon statement timeout


def round_coords(c):
    if isinstance(c[0], (int, float)):
        return [round(c[0], 6), round(c[1], 6)]
    return [round_coords(x) for x in c]


def post(token, layer, features):
    body = json.dumps({"p_token": token, "p_layer": layer, "p_features": features}).encode()
    req = urllib.request.Request(
        SUPABASE_URL + "/rest/v1/rpc/stage_features",
        data=body,
        headers={
            "apikey": SUPABASE_KEY,
            "Authorization": "Bearer " + SUPABASE_KEY,
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            return int(resp.read())
    except urllib.error.HTTPError as e:
        sys.exit(f"{layer}: HTTP {e.code} {e.read().decode(errors='replace')}")


def main():
    token = os.environ.get("LOAD_TOKEN")
    if not token:
        sys.exit("Set LOAD_TOKEN first (see the docstring).")

    for layer, filename, keep in LAYERS:
        data = json.loads((ROOT / filename).read_text(encoding="utf-8"))
        features = []
        for f in data["features"]:
            if not f.get("geometry") or (keep and not keep(f["properties"])):
                continue
            geom = f["geometry"]
            features.append({
                "properties": f["properties"],
                "geometry": {"type": geom["type"], "coordinates": round_coords(geom["coordinates"])},
            })

        sent = 0
        batch, size = [], 0
        for f in features + [None]:
            n = len(json.dumps(f)) if f else 0
            if batch and (f is None or size + n > MAX_BATCH_BYTES):
                sent += post(token, layer, batch)
                print(f"{layer}: {sent}/{len(features)}", flush=True)
                batch, size = [], 0
            if f:
                batch.append(f)
                size += n

        if sent != len(features):
            sys.exit(f"{layer}: expected {len(features)} rows, staged {sent}")

    print("Done. Tell Claude the upload finished so it can build the layers.")


if __name__ == "__main__":
    main()
