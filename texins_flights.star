"""
Applet: Texins Flights
Summary: Tracks Texins Flying Club aircraft out of McKinney (KTKI)
Description: Displays live flight telemetry (route, departure/arrival times, speed in knots, altitude, nearest city, and custom aircraft silhouettes) for the Texins Flying Club fleet (N121DB, N3QZ, N4135W, N6833C) using FlightAware AeroAPI v4. Prioritizes actively airborne aircraft and shows a compact 4-plane status board when all aircraft are parked.
Author: Houston
"""

load("render.star", "render")
load("http.star", "http")
load("encoding/base64.star", "base64")
load("encoding/json.star", "json")
load("cache.star", "cache")
load("math.star", "math")
load("time.star", "time")
load("schema.star", "schema")

AEROAPI_BASE = "https://aeroapi.flightaware.com/aeroapi"
REVERSE_GEOCODE_URL = "https://api.bigdatacloud.net/data/reverse-geocode-client"

FLIGHT_CACHE_TTL = 300       # 5 minutes for flight list per tail number
TRACK_CACHE_TTL = 60         # 1 minute for active flight position/track
GEOCODE_CACHE_TTL = 3600     # 1 hour for rounded lat/lon reverse geocode
DEFAULT_TIMEZONE = "America/Chicago"

# ---------------------------------------------------------------------------
# Custom Pixel-Art Aircraft Silhouettes (Base64 PNGs)
#   *_LG: 16x8 side-profile icons for Airborne Detail View
#   *_SM: 10x6 mini side-profile icons for 4-Plane Parked Status Board
# ---------------------------------------------------------------------------

# N121DB - Piper Arrow II (Low-wing, retractable gear, sleek swept tail, Sky Blue livery)
ICON_ARROW_LG = base64.decode("iVBORw0KGgoAAAANSUhEUgAAABAAAAAICAYAAADwdn+XAAAARElEQVR42mNgAAL/w9//gzADuQCk+cOXH2CMTR4mh08NAy4FMDHNbd/AGKsh6DYQizfsO/ofxRvImGQD0MMEH2YYVAAATRLEUcX6WTQAAAAASUVORK5CYII=")
ICON_ARROW_SM = base64.decode("iVBORw0KGgoAAAANSUhEUgAAAAoAAAAGCAYAAAD68A/GAAAAN0lEQVR42mPwP/z9PwMx4MOXH/9BGJ2PLIYhAcOa276h8DfsOwrRBLIehLFpwjAZWQMyZiAVAAD9NWeI4wdUnQAAAABJRU5ErkJggg==")

# N3QZ - Cessna 182 (High-wing, wing strut, stepped windshield, tricycle gear, Amber Gold livery)
ICON_C182_LG = base64.decode("iVBORw0KGgoAAAANSUhEUgAAABAAAAAICAYAAADwdn+XAAAAXUlEQVR42mNgAIL/V/3/gzADEoCJ4cMoij98+QHGyIZMWLLuPwhrbvsGlwfxGbABmAKYIcgaQAYgGwLCG/Yd/Y9VMykYxRBi/IzV/7gANr/i9D82EJJX9Z8YMYoBAJbf1AtoIphOAAAAAElFTkSuQmCC")
ICON_C182_SM = base64.decode("iVBORw0KGgoAAAANSUhEUgAAAAoAAAAGCAYAAAD68A/GAAAAPUlEQVR42mP4f9X/PwMUgNjYMFjyw5cf/0EYpnjCknX/Nbd9QxFDUYgPb9h39D9eK5GdhQFC8qr+Y2MTDQBWI2d+MzY9KAAAAABJRU5ErkJggg==")

# N4135W - Piper Archer IV (Low-wing tapered, fixed tricycle gear with fairings, Mint Green livery)
ICON_ARCHER_LG = base64.decode("iVBORw0KGgoAAAANSUhEUgAAABAAAAAICAYAAADwdn+XAAAAT0lEQVR42mNgAILG4y3/QZiBXADS/OHLDzDGJg+Tw6eGAZcCmJjmtm9gDONv2Hf0P04biMUohsDCAYZJNgA9TPBhogOWFHEMEJJX9Z8YcQB1Gs383yTlUwAAAABJRU5ErkJggg==")
ICON_ARCHER_SM = base64.decode("iVBORw0KGgoAAAANSUhEUgAAAAoAAAAGCAYAAAD68A/GAAAAPElEQVR42mNoPN7yn4EY8OHLj/8gjM5HFsOQgGHNbd9Q+Bv2HYVoAlkPwtg0YZiMrAEZ43RzSF7Vf2x8AIiRahag9YDgAAAAAElFTkSuQmCC")

# N6833C - Piper Cherokee (Classic PA-28 low-wing, squared tail, fixed gear, Coral Orange livery)
ICON_CHEROKEE_LG = base64.decode("iVBORw0KGgoAAAANSUhEUgAAABAAAAAICAYAAADwdn+XAAAAVUlEQVR42mNgAIL/Xan/YZiBHADS+OHLDzBGl4OJI2OshmBTAONrbvsGFgPRMLEN+47+x2sLMRjFEORwIMsA9DDBhYkO2AlL1v0nRRwDhORV/SdGHAD4/NTv8DFJ2AAAAABJRU5ErkJggg==")
ICON_CHEROKEE_SM = base64.decode("iVBORw0KGgoAAAANSUhEUgAAAAoAAAAGCAYAAAD68A/GAAAAPElEQVR42mP435X6H4QZCIEPX378B2F0Pro4hgQIa277hsLfsO8oRAPMemyaUEyFAZgGotwdklf1HxsfALtLbwGbIB8lAAAAAElFTkSuQmCC")

FLEET = [
    {
        "ident": "N121DB",
        "type": "Piper Arrow II",
        "short_type": "ARROW",
        "color": "#4fc3f7",
        "icon_lg": ICON_ARROW_LG,
        "icon_sm": ICON_ARROW_SM,
    },
    {
        "ident": "N3QZ",
        "type": "Cessna 182",
        "short_type": "C182",
        "color": "#ffd54f",
        "icon_lg": ICON_C182_LG,
        "icon_sm": ICON_C182_SM,
    },
    {
        "ident": "N4135W",
        "type": "Piper Archer IV",
        "short_type": "ARCHR",
        "color": "#81c784",
        "icon_lg": ICON_ARCHER_LG,
        "icon_sm": ICON_ARCHER_SM,
    },
    {
        "ident": "N6833C",
        "type": "Piper Cherokee",
        "short_type": "CHRK",
        "color": "#ff8a65",
        "icon_lg": ICON_CHEROKEE_LG,
        "icon_sm": ICON_CHEROKEE_SM,
    },
]

# Offline Haversine fallback database of North Texas & regional cities/airports
REGIONAL_CITIES = [
    {"name": "McKinney, TX", "lat": 33.1779, "lon": -96.5905},
    {"name": "Allen, TX", "lat": 33.1032, "lon": -96.6706},
    {"name": "Frisco, TX", "lat": 33.1507, "lon": -96.8236},
    {"name": "Plano, TX", "lat": 33.0198, "lon": -96.6989},
    {"name": "Prosper, TX", "lat": 33.2362, "lon": -96.8011},
    {"name": "Celina, TX", "lat": 33.3246, "lon": -96.7844},
    {"name": "Melissa, TX", "lat": 33.2859, "lon": -96.5728},
    {"name": "Anna, TX", "lat": 33.3490, "lon": -96.5486},
    {"name": "Van Alstyne, TX", "lat": 33.4215, "lon": -96.5772},
    {"name": "Sherman, TX", "lat": 33.6357, "lon": -96.6089},
    {"name": "Denison, TX", "lat": 33.7557, "lon": -96.5367},
    {"name": "Bonham, TX", "lat": 33.5773, "lon": -96.1783},
    {"name": "Greenville, TX", "lat": 33.1384, "lon": -96.1108},
    {"name": "Rockwall, TX", "lat": 32.9312, "lon": -96.4597},
    {"name": "Garland, TX", "lat": 32.9126, "lon": -96.6389},
    {"name": "Addison, TX", "lat": 32.9686, "lon": -96.8364},
    {"name": "Dallas, TX", "lat": 32.7767, "lon": -96.7970},
    {"name": "Denton, TX", "lat": 33.2148, "lon": -97.1331},
    {"name": "Gainesville, TX", "lat": 33.6259, "lon": -97.1333},
    {"name": "Decatur, TX", "lat": 33.2343, "lon": -97.5861},
    {"name": "Fort Worth, TX", "lat": 32.7555, "lon": -97.3308},
    {"name": "Arlington, TX", "lat": 32.7357, "lon": -97.1081},
    {"name": "Terrell, TX", "lat": 32.7359, "lon": -96.2753},
    {"name": "Sulphur Spgs, TX", "lat": 33.1385, "lon": -95.6011},
    {"name": "Paris, TX", "lat": 33.6609, "lon": -95.5555},
    {"name": "Tyler, TX", "lat": 32.3513, "lon": -95.3011},
    {"name": "Longview, TX", "lat": 32.5007, "lon": -94.7405},
    {"name": "Corsicana, TX", "lat": 32.0954, "lon": -96.4689},
    {"name": "Waco, TX", "lat": 31.5493, "lon": -97.1467},
    {"name": "Temple, TX", "lat": 31.0982, "lon": -97.3428},
    {"name": "Austin, TX", "lat": 30.2672, "lon": -97.7431},
    {"name": "College Sta, TX", "lat": 30.6280, "lon": -96.3344},
    {"name": "Houston, TX", "lat": 29.7604, "lon": -95.3698},
    {"name": "San Antonio, TX", "lat": 29.4241, "lon": -98.4936},
    {"name": "Wichita Falls, TX", "lat": 33.9137, "lon": -98.4934},
    {"name": "Abilene, TX", "lat": 32.4487, "lon": -99.7331},
    {"name": "Lubbock, TX", "lat": 33.5779, "lon": -101.8552},
    {"name": "Amarillo, TX", "lat": 35.2220, "lon": -101.8313},
    {"name": "Carlsbad, NM", "lat": 32.4207, "lon": -104.2288},
    {"name": "Durant, OK", "lat": 33.9925, "lon": -96.3708},
    {"name": "Ardmore, OK", "lat": 34.1743, "lon": -97.1436},
    {"name": "Oklahoma City, OK", "lat": 35.4676, "lon": -97.5164},
]

# ---------------------------------------------------------------------------
# Main Entrypoint
# ---------------------------------------------------------------------------

def main(config):
    api_key = config.get("api_key", "")
    mode = config.get("mode", "auto")

    if mode == "demo":
        fleet_status = get_demo_fleet_status()
    elif api_key == "":
        return render_missing_key()
    else:
        fleet_status = fetch_fleet_status(api_key)

    airborne_planes = [p for p in fleet_status if p["is_airborne"]]

    # Mode selection:
    # 1. "auto" (default): Prioritize actively airborne planes; if none flying, show compact 4-plane status board
    # 2. "board": Always show compact 4-plane status board
    # 3. "cycle": Cycle full detail cards for all 4 planes
    if mode == "board":
        return render_parked_board(fleet_status)

    if mode == "cycle":
        return render_plane_cards(fleet_status)

    if len(airborne_planes) > 0:
        return render_plane_cards(airborne_planes)

    return render_parked_board(fleet_status)

# ---------------------------------------------------------------------------
# Data Fetching & Processing
# ---------------------------------------------------------------------------

def json_decode_safe(raw):
    if hasattr(json, "decode"):
        return json.decode(raw)
    return json.loads(raw)

def json_encode_safe(val):
    if hasattr(json, "encode"):
        return json.encode(val)
    return json.dumps(val)

def fetch_fleet_status(api_key):
    results = []
    for plane in FLEET:
        ident = plane["ident"]
        flight = fetch_latest_flight(ident, api_key)
        parsed = build_plane_state(plane, flight, api_key)
        results.append(parsed)
    return results

def fetch_latest_flight(ident, api_key):
    cache_key = "fa_flights_" + ident
    cached = cache.get(cache_key)
    data = None

    if cached != None:
        data = json_decode_safe(cached)
    else:
        url = "%s/flights/%s?max_pages=1" % (AEROAPI_BASE, ident)
        resp = http.get(url, headers = {"x-apikey": api_key})
        if resp.status_code == 200:
            body = resp.body()
            cache.set(cache_key, body, ttl_seconds = FLIGHT_CACHE_TTL)
            data = json_decode_safe(body)

    if data == None or "flights" not in data:
        return None

    flights = data["flights"]
    if not flights or len(flights) == 0:
        return None

    # 1. Prioritize any currently active / en-route flight
    for f in flights:
        if is_flight_airborne(f):
            return f

    # 2. Otherwise pick the most recent flight that has actually departed or arrived
    for f in flights:
        if f.get("actual_off") != None or f.get("actual_on") != None:
            return f

    # 3. Fallback to first flight entry (e.g. scheduled)
    return flights[0]

def is_flight_airborne(flight):
    if flight == None:
        return False
    if flight.get("cancelled") == True:
        return False
    status = flight.get("status") or ""
    if "En Route" in status or "Taxiing" in status:
        return True
    actual_off = flight.get("actual_off")
    actual_on = flight.get("actual_on")
    if actual_off != None and actual_on == None:
        return True
    prog = flight.get("progress_percent")
    if prog != None and prog > 0 and prog < 100 and actual_on == None:
        return True
    return False

def fetch_latest_position(fa_flight_id, api_key):
    if not fa_flight_id:
        return None
    cache_key = "fa_track_" + fa_flight_id
    cached = cache.get(cache_key)
    data = None

    if cached != None:
        data = json_decode_safe(cached)
    else:
        url = "%s/flights/%s/track" % (AEROAPI_BASE, fa_flight_id)
        resp = http.get(url, headers = {"x-apikey": api_key})
        if resp.status_code == 200:
            body = resp.body()
            cache.set(cache_key, body, ttl_seconds = TRACK_CACHE_TTL)
            data = json_decode_safe(body)

    if data == None or "positions" not in data:
        return None

    positions = data["positions"]
    if not positions or len(positions) == 0:
        return None

    return positions[len(positions) - 1]

def build_plane_state(plane, flight, api_key):
    state = {
        "ident": plane["ident"],
        "type": plane["type"],
        "short_type": plane["short_type"],
        "color": plane["color"],
        "icon_lg": plane["icon_lg"],
        "icon_sm": plane["icon_sm"],
        "is_airborne": False,
        "status": "Parked",
        "from_code": "TKI",
        "to_code": "---",
        "dep_time": "--:--",
        "arr_time": "--:--",
        "groundspeed": 0,
        "altitude_ft": 0,
        "heading_str": "",
        "nearest_city": "McKinney, TX",
    }

    if flight == None:
        return state

    airborne = is_flight_airborne(flight)
    state["is_airborne"] = airborne
    state["status"] = flight.get("status") or ("En Route" if airborne else "Arrived")

    origin = flight.get("origin")
    dest = flight.get("destination")

    state["from_code"] = format_airport_code(origin, "TKI")
    state["to_code"] = format_airport_code(dest, "LCL")

    dep_raw = flight.get("actual_off") or flight.get("estimated_off") or flight.get("scheduled_off") or flight.get("actual_out") or flight.get("scheduled_out")
    arr_raw = flight.get("actual_on") or flight.get("estimated_on") or flight.get("scheduled_on") or flight.get("actual_in") or flight.get("scheduled_in")

    state["dep_time"] = format_local_time(dep_raw)
    state["arr_time"] = format_local_time(arr_raw)

    # Determine parked city from destination (or origin)
    if dest != None:
        state["nearest_city"] = format_airport_city(dest)
    elif origin != None:
        state["nearest_city"] = format_airport_city(origin)

    # Fetch live telemetry & nearest city if airborne
    if airborne:
        pos = flight.get("last_position")
        if pos == None:
            pos = fetch_latest_position(flight.get("fa_flight_id"), api_key)
        if pos != None:
            gs = pos.get("groundspeed")
            alt = pos.get("altitude")
            hdg = pos.get("heading")
            lat = pos.get("latitude")
            lon = pos.get("longitude")

            if gs != None:
                state["groundspeed"] = int(gs)
            if alt != None:
                state["altitude_ft"] = int(alt) * 100
            if hdg != None:
                state["heading_str"] = heading_to_compass(int(hdg))
            if lat != None and lon != None:
                state["nearest_city"] = resolve_nearest_city(float(lat), float(lon))

    return state

def format_airport_code(airport_obj, fallback):
    if airport_obj == None:
        return fallback
    iata = airport_obj.get("code_iata")
    if iata and len(iata) > 0:
        return iata
    lid = airport_obj.get("code_lid")
    if lid and len(lid) > 0:
        return lid
    code = airport_obj.get("code") or airport_obj.get("code_icao") or ""
    if len(code) == 4 and code.startswith("K"):
        return code[1:]
    if len(code) > 0:
        return code
    return fallback

def format_airport_city(airport_obj):
    if airport_obj == None:
        return "McKinney, TX"
    code = airport_obj.get("code") or ""
    name = airport_obj.get("name") or ""
    if code == "KTKI" or code == "TKI" or "McKinney" in name:
        return "McKinney, TX"
    if code == "KADS" or code == "ADS" or "Addison" in name:
        return "Addison, TX"
    city = airport_obj.get("city")
    if city and len(city) > 0:
        return city
    if len(name) > 0:
        return name
    return code

def format_local_time(iso_str):
    if not iso_str:
        return "--:--"
    t = time.parse_time(iso_str)
    if t == None:
        return "--:--"
    local_t = t.in_location(DEFAULT_TIMEZONE)
    formatted = local_t.format("3:04p")
    # Shorten "am"/"pm" to "a"/"p"
    if formatted.endswith("m"):
        formatted = formatted[:-1]
    return formatted

def heading_to_compass(deg):
    dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    idx = int((deg + 22) / 45) % 8
    return dirs[idx]

def resolve_nearest_city(lat, lon):
    # Grid key (~5km resolution) to maximize cache hits
    lat_key = str(int(lat * 20))
    lon_key = str(int(lon * 20))
    cache_key = "fa_geo_%s_%s" % (lat_key, lon_key)
    cached = cache.get(cache_key)
    if cached != None and len(cached) > 0:
        return cached

    # 1. Try BigDataCloud free reverse geocode API
    url = "%s?latitude=%s&longitude=%s&localityLanguage=en" % (REVERSE_GEOCODE_URL, str(lat), str(lon))
    resp = http.get(url)
    if resp.status_code == 200:
        data = json_decode_safe(resp.body())
        city = data.get("city") or data.get("locality") or ""
        state_code = data.get("principalSubdivisionCode") or ""
        if "-" in state_code:
            state_code = state_code.split("-")[1]
        if len(city) > 0:
            label = "%s, %s" % (city, state_code) if len(state_code) > 0 else city
            cache.set(cache_key, label, ttl_seconds = GEOCODE_CACHE_TTL)
            return label

    # 2. Fallback to Haversine lookup table
    fallback = nearest_city_haversine(lat, lon)
    cache.set(cache_key, fallback, ttl_seconds = GEOCODE_CACHE_TTL)
    return fallback

def nearest_city_haversine(lat, lon):
    best_name = "McKinney, TX"
    best_dist = 999999.0
    for c in REGIONAL_CITIES:
        d = haversine_km(lat, lon, c["lat"], c["lon"])
        if d < best_dist:
            best_dist = d
            best_name = c["name"]
    return best_name

def haversine_km(lat1, lon1, lat2, lon2):
    r = 6371.0
    p1 = math.radians(lat1)
    p2 = math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2.0) * math.sin(dp / 2.0) + math.cos(p1) * math.cos(p2) * math.sin(dl / 2.0) * math.sin(dl / 2.0)
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))
    return r * c

# ---------------------------------------------------------------------------
# Rendering: Airborne Full-Screen Detail Cards (64x32)
# ---------------------------------------------------------------------------

def render_plane_cards(planes):
    if len(planes) == 1:
        return render.Root(
            delay = 75,
            child = render_single_plane_card(planes[0]),
        )

    # When multiple planes are airborne, hold each plane card for ~50 frames (3.75s at 75ms/frame)
    frames = []
    for p in planes:
        card = render_single_plane_card(p)
        for _ in range(50):
            frames.append(card)

    return render.Root(
        delay = 75,
        child = render.Animation(children = frames),
    )

def render_single_plane_card(p):
    status_dot_color = "#00e676" if p["is_airborne"] else "#78909c"
    speed_text = "%dKT" % p["groundspeed"] if p["is_airborne"] else "0KT"
    if p["heading_str"] != "":
        speed_text = "%s %s" % (speed_text, p["heading_str"])

    alt_text = "%dFT" % p["altitude_ft"] if (p["is_airborne"] and p["altitude_ft"] > 0) else ("AIRBORNE" if p["is_airborne"] else "PARKED")

    route_str = "%s->%s %s-%s" % (p["from_code"], p["to_code"], p["dep_time"], p["arr_time"])
    city_label = "NEAR: %s" % p["nearest_city"] if p["is_airborne"] else "AT: %s" % p["nearest_city"]

    return render.Box(
        width = 64,
        height = 32,
        color = "#080c14",
        child = render.Column(
            expanded = True,
            main_align = "start",
            cross_align = "start",
            children = [
                # Row 1 (9px): Aircraft Silhouette + Tail Number + Type/Live Dot
                render.Box(
                    width = 64,
                    height = 9,
                    color = "#101b2d",
                    child = render.Row(
                        expanded = True,
                        main_align = "space_between",
                        cross_align = "center",
                        children = [
                            render.Row(
                                cross_align = "center",
                                children = [
                                    render.Image(src = p["icon_lg"]),
                                    render.Box(width = 1, height = 1),
                                    render.Text(
                                        content = p["ident"],
                                        font = "tom-thumb",
                                        color = p["color"],
                                    ),
                                ],
                            ),
                            render.Row(
                                cross_align = "center",
                                children = [
                                    render.Box(width = 2, height = 2, color = status_dot_color),
                                    render.Box(width = 1, height = 1),
                                    render.Text(
                                        content = p["short_type"],
                                        font = "CG-pixel-3x5-mono",
                                        color = "#b0bec5",
                                    ),
                                ],
                            ),
                        ],
                    ),
                ),

                # Row 2 (8px): 3-Letter Route (FROM->TO) + Dep/Arr Times
                render.Box(
                    width = 64,
                    height = 8,
                    child = render.Padding(
                        pad = (1, 1, 1, 0),
                        child = render.Marquee(
                            width = 62,
                            offset_start = 0,
                            offset_end = 0,
                            child = render.Row(
                                children = [
                                    render.Text(
                                        content = "%s->%s" % (p["from_code"], p["to_code"]),
                                        font = "tom-thumb",
                                        color = "#ffffff",
                                    ),
                                    render.Text(
                                        content = " %s-%s" % (p["dep_time"], p["arr_time"]),
                                        font = "tom-thumb",
                                        color = "#80cbc4",
                                    ),
                                ],
                            ),
                        ),
                    ),
                ),

                # Row 3 (7px): Speed in Knots + Altitude
                render.Box(
                    width = 64,
                    height = 7,
                    child = render.Padding(
                        pad = (1, 1, 1, 0),
                        child = render.Row(
                            expanded = True,
                            main_align = "space_between",
                            cross_align = "center",
                            children = [
                                render.Text(
                                    content = speed_text,
                                    font = "tom-thumb",
                                    color = "#00e676" if p["is_airborne"] else "#90a4ae",
                                ),
                                render.Text(
                                    content = alt_text,
                                    font = "tom-thumb",
                                    color = "#ffd54f" if p["is_airborne"] else "#78909c",
                                ),
                            ],
                        ),
                    ),
                ),

                # Row 4 (8px): Nearest City
                render.Box(
                    width = 64,
                    height = 8,
                    color = "#0d1522",
                    child = render.Padding(
                        pad = (1, 1, 1, 0),
                        child = render.Marquee(
                            width = 62,
                            offset_start = 0,
                            offset_end = 0,
                            child = render.Text(
                                content = city_label,
                                font = "tom-thumb",
                                color = "#fff59d",
                            ),
                        ),
                    ),
                ),
            ],
        ),
    )

# ---------------------------------------------------------------------------
# Rendering: Compact 4-Plane Parked Status Board (64x32 = 4 rows x 8px)
# ---------------------------------------------------------------------------

def render_parked_board(fleet_status):
    rows = []
    for idx in range(len(fleet_status)):
        p = fleet_status[idx]
        bg_color = "#090e17" if idx % 2 == 0 else "#111a29"

        # Compact summary for right side: 3-letter FROM->TO + last Arr/Dep time + city
        info_text = "%s>%s %s-%s %s" % (
            p["from_code"],
            p["to_code"],
            p["dep_time"],
            p["arr_time"],
            p["nearest_city"],
        )

        row_widget = render.Box(
            width = 64,
            height = 8,
            color = bg_color,
            child = render.Padding(
                pad = (1, 1, 1, 0),
                child = render.Row(
                    expanded = True,
                    main_align = "space_between",
                    cross_align = "center",
                    children = [
                        # Left: Mini Plane Silhouette (10x6) + Tail Number (24px, left-aligned)
                        render.Row(
                            cross_align = "center",
                            children = [
                                render.Image(src = p["icon_sm"]),
                                render.Box(width = 2, height = 1),
                                render.Box(
                                    width = 24,
                                    height = 6,
                                    child = render.Row(
                                        expanded = True,
                                        main_align = "start",
                                        children = [
                                            render.Text(
                                                content = p["ident"],
                                                font = "tom-thumb",
                                                color = p["color"],
                                            ),
                                        ],
                                    ),
                                ),
                            ],
                        ),
                        # Right: Scrolling 24px Marquee with Route & Times
                        render.Marquee(
                            width = 24,
                            offset_start = 0,
                            offset_end = 0,
                            child = render.Text(
                                content = info_text,
                                font = "tom-thumb",
                                color = "#cfd8dc",
                            ),
                        ),
                    ],
                ),
            ),
        )
        rows.append(row_widget)

    return render.Root(
        delay = 85,
        child = render.Column(
            expanded = True,
            main_align = "start",
            children = rows,
        ),
    )

def render_missing_key():
    return render.Root(
        child = render.Box(
            width = 64,
            height = 32,
            color = "#101824",
            child = render.Column(
                expanded = True,
                main_align = "space_evenly",
                cross_align = "center",
                children = [
                    render.Row(
                        cross_align = "center",
                        children = [
                            render.Image(src = ICON_ARROW_LG),
                            render.Box(width = 2, height = 1),
                            render.Text("TEXINS", font = "tom-thumb", color = "#4fc3f7"),
                        ],
                    ),
                    render.Text("SET AEROAPI KEY", font = "tom-thumb", color = "#ffd54f"),
                    render.Text("IN APP SETTINGS", font = "CG-pixel-3x5-mono", color = "#90a4ae"),
                ],
            ),
        ),
    )

# ---------------------------------------------------------------------------
# Simulated Demo Data (for testing Airborne View when fleet is parked)
# ---------------------------------------------------------------------------

def get_demo_fleet_status():
    return [
        {
            "ident": "N121DB",
            "type": "Piper Arrow II",
            "short_type": "ARROW",
            "color": "#4fc3f7",
            "icon_lg": ICON_ARROW_LG,
            "icon_sm": ICON_ARROW_SM,
            "is_airborne": True,
            "status": "En Route",
            "from_code": "TKI",
            "to_code": "ADS",
            "dep_time": "11:45a",
            "arr_time": "12:20p",
            "groundspeed": 134,
            "altitude_ft": 4500,
            "heading_str": "SW",
            "nearest_city": "McKinney, TX",
        },
        {
            "ident": "N3QZ",
            "type": "Cessna 182",
            "short_type": "C182",
            "color": "#ffd54f",
            "icon_lg": ICON_C182_LG,
            "icon_sm": ICON_C182_SM,
            "is_airborne": False,
            "status": "Arrived",
            "from_code": "CNM",
            "to_code": "TKI",
            "dep_time": "11:30a",
            "arr_time": "2:38p",
            "groundspeed": 0,
            "altitude_ft": 0,
            "heading_str": "",
            "nearest_city": "McKinney, TX",
        },
        {
            "ident": "N4135W",
            "type": "Piper Archer IV",
            "short_type": "ARCHR",
            "color": "#81c784",
            "icon_lg": ICON_ARCHER_LG,
            "icon_sm": ICON_ARCHER_SM,
            "is_airborne": False,
            "status": "Arrived",
            "from_code": "TKI",
            "to_code": "TKI",
            "dep_time": "10:15a",
            "arr_time": "11:30a",
            "groundspeed": 0,
            "altitude_ft": 0,
            "heading_str": "",
            "nearest_city": "McKinney, TX",
        },
        {
            "ident": "N6833C",
            "type": "Piper Cherokee",
            "short_type": "CHRK",
            "color": "#ff8a65",
            "icon_lg": ICON_CHEROKEE_LG,
            "icon_sm": ICON_CHEROKEE_SM,
            "is_airborne": False,
            "status": "Arrived",
            "from_code": "TKI",
            "to_code": "TKI",
            "dep_time": "9:05a",
            "arr_time": "9:42a",
            "groundspeed": 0,
            "altitude_ft": 0,
            "heading_str": "",
            "nearest_city": "McKinney, TX",
        },
    ]

# ---------------------------------------------------------------------------
# Tidbyt In-App Configuration Schema
# ---------------------------------------------------------------------------

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "api_key",
                name = "FlightAware AeroAPI Key",
                desc = "FlightAware AeroAPI v4 key (x-apikey)",
                icon = "key",
            ),
            schema.Dropdown(
                id = "mode",
                name = "Display Mode",
                desc = "Prioritize airborne aircraft or force a specific view",
                icon = "plane",
                default = "auto",
                options = [
                    schema.Option(
                        display = "Auto (Airborne first, 4-plane board when parked)",
                        value = "auto",
                    ),
                    schema.Option(
                        display = "Always Show 4-Plane Status Board",
                        value = "board",
                    ),
                    schema.Option(
                        display = "Cycle Full Cards for All 4 Planes",
                        value = "cycle",
                    ),
                    schema.Option(
                        display = "Demo Mode (Simulated Airborne Flight)",
                        value = "demo",
                    ),
                ],
            ),
        ],
    )
