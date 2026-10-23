"""Times Overpass queries of different weight against public servers (no secrets involved)."""
import time, urllib.parse, urllib.request

ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
]
LAT, LON = 55.6761, 12.5683
d = 0.005  # ~550 m north-south
BBOX = f"{LAT-d},{LON-d*1.8},{LAT+d},{LON+d*1.8}"
QUERIES = {
    "trivial": '[out:json][timeout:10];node(1);out;',
    "bbox maxspeed": f'[out:json][timeout:15];way["highway"]["maxspeed"]({BBOX});out tags geom;',
    "bbox highway": f'[out:json][timeout:15];way["highway"]({BBOX});out tags geom;',
    "around 500 highway": f'[out:json][timeout:15];way(around:500,{LAT},{LON})["highway"];out tags geom;',
}
for name, query in QUERIES.items():
    body = ("data=" + urllib.parse.quote(query, safe="")).encode()
    for url in ENDPOINTS:
        req = urllib.request.Request(url, data=body, headers={
            "User-Agent": "SpeedAnnounce-iOS/1.0 (github.com/myschetzky/Speed-announce)",
            "Content-Type": "application/x-www-form-urlencoded"})
        start = time.time()
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                data = r.read()
                print(f"{name:20} {url}: {r.status} {len(data)} bytes in {time.time()-start:.1f}s", flush=True)
        except Exception as e:
            print(f"{name:20} {url}: {type(e).__name__} {e} after {time.time()-start:.1f}s", flush=True)
