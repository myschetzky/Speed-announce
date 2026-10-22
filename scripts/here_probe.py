"""Prints HERE Map Attributes API responses around Copenhagen so the client can be
matched to the real format. Reads the key from HERE_API_KEY; the key is never printed."""
import json, math, os, sys, urllib.request, urllib.error

KEY = os.environ.get("HERE_API_KEY", "")
if not KEY:
    print("HERE_API_KEY not set; skipping")
    sys.exit(0)

LAT, LON = 55.6761, 12.5683  # Copenhagen, Rådhuspladsen
BASE = "https://smap.hereapi.com/v8/maps/attributes"

def get(label, url, limit=3000):
    sep = "&" if "?" in url else "?"
    print(f"\n===== {label}\nGET {url}")
    try:
        with urllib.request.urlopen(url + f"{sep}apiKey={KEY}", timeout=30) as r:
            body = r.read().decode("utf-8", "replace")
            print("status", r.status)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        print("status", e.code)
    except Exception as e:
        print("error", type(e).__name__, e)
        return
    print(body.replace(KEY, "***")[:limit])

def tile(level):
    size = 180.0 / (1 << level)
    x = int(math.floor((LON + 180) / size))
    y = int(math.floor((LAT + 90) / size))
    return x, y

for path in ["doc/layers", "doc/layers.json", "doc/maps", "doc/attributes?layer=SPEED_LIMITS_FC5",
             "doc/layer?layer=SPEED_LIMITS_FC5", "doc/layer?layer=APPLICABLE_SPEED_LIMIT_FC5",
             "doc/layer?layer=ROAD_GEOM_FC5"]:
    get(f"doc {path}", f"{BASE}/{path}", 4000)

x, y = tile(13)
candidates = {
    "y*2^(l+1)+x": y * (1 << 14) + x,
    "heretile": None,
}
# HERE tile id with level marker bit (morton-interleaved quadkey), as used by HERE Data SDK.
def here_tile_id(level):
    tx, ty = tile(level)
    morton = 0
    for i in range(level + 1):
        morton |= ((tx >> i) & 1) << (2 * i)
        morton |= ((ty >> i) & 1) << (2 * i + 1)
    return (1 << (2 * level + 2)) | morton
candidates["heretile"] = here_tile_id(13)
print("\nlevel 13 tilex,tiley =", x, y, "candidates", candidates)

for name, tid in candidates.items():
    for layers in ["SPEED_LIMITS_FC5", "APPLICABLE_SPEED_LIMIT_FC5", "ROAD_GEOM_FC5"]:
        get(f"tiles {name} {layers}", f"{BASE}?layers={layers}&in=tile:{tid}", 2500)

get("tiles both layers", f"{BASE}?layers=SPEED_LIMITS_FC5,ROAD_GEOM_FC5&in=tile:{candidates['heretile']}", 1500)
get("level 9 FC1", f"{BASE}?layers=SPEED_LIMITS_FC1&in=tile:{here_tile_id(9)}", 1500)
