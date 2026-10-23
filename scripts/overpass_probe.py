"""Times the app's Overpass query against public Overpass servers (no secrets involved)."""
import time, urllib.parse, urllib.request

HIGHWAYS = "motorway|motorway_link|trunk|trunk_link|primary|primary_link|secondary|secondary_link|tertiary|tertiary_link|unclassified|residential|living_street|service|road"
ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
]
for radius in (1200, 500):
    query = f'[out:json][timeout:20];way(around:{radius},55.6761,12.5683)["highway"~"^({HIGHWAYS})$"];out tags geom;'
    body = ("data=" + urllib.parse.quote(query, safe="")).encode()
    for url in ENDPOINTS:
        req = urllib.request.Request(url, data=body, headers={
            "User-Agent": "SpeedAnnounce-iOS/1.0",
            "Content-Type": "application/x-www-form-urlencoded"})
        start = time.time()
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                data = r.read()
                print(f"radius {radius} {url}: {r.status} {len(data)} bytes in {time.time()-start:.1f}s")
        except Exception as e:
            print(f"radius {radius} {url}: {type(e).__name__} {e} after {time.time()-start:.1f}s")
