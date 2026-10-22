"""Prints HERE API responses around Copenhagen so the client can be matched to the
real format. Reads the key from HERE_API_KEY; the key is never printed."""
import os, sys, time, urllib.request, urllib.error

KEY = os.environ.get("HERE_API_KEY", "")
if not KEY:
    print("HERE_API_KEY not set; skipping")
    sys.exit(0)

def get(label, url, limit=6000):
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
    time.sleep(2)

# Rådhuspladsen -> H.C. Andersens Boulevard, ~600 m.
get("routing speed limits",
    "https://router.hereapi.com/v8/routes?transportMode=car"
    "&origin=55.6761,12.5683;course=150&destination=55.6720,12.5745"
    "&return=polyline&spans=speedLimit,names,length")
get("map attributes single tile",
    "https://smap.hereapi.com/v8/maps/attributes?layers=SPEED_LIMITS_FC1&in=tile:1476269", 1500)
