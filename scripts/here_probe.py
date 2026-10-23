"""Asks the HERE Routing API which route attributes ('spans') it offers, to find
advisory (blue sign) speeds. Reads the key from HERE_API_KEY; it is never printed."""
import os, sys, time, urllib.request, urllib.error

KEY = os.environ.get("HERE_API_KEY", "")
if not KEY:
    print("HERE_API_KEY not set; skipping")
    sys.exit(0)

def get(label, url, limit=6000):
    print(f"\n===== {label}\nGET {url}")
    try:
        with urllib.request.urlopen(url + f"&apiKey={KEY}", timeout=30) as r:
            body = r.read().decode("utf-8", "replace")
            print("status", r.status)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        print("status", e.code)
    print(body.replace(KEY, "***")[:limit])
    time.sleep(2)

BASE = ("https://router.hereapi.com/v8/routes?transportMode=car"
        "&origin=55.6761,12.5683&destination=55.6720,12.5745&return=polyline")
# Guessed names for advisory (blue sign) speeds; HERE answers 400 for unknown span types.
for name in ["advisorySpeed", "recommendedSpeed", "speedAdvisory", "advisorySpeedLimit", "carAttributes"]:
    get(name, BASE + f"&spans={name}", 600)
