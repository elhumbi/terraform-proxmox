import json
import math
import os
import time
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

TZ_ZURICH = ZoneInfo("Europe/Zurich")

import httpx
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from fastapi import FastAPI
from fastapi.responses import HTMLResponse, Response
from prometheus_client import CONTENT_TYPE_LATEST, Gauge, generate_latest

API_URL = os.getenv(
    "API_URL",
    "https://messtechnik.meteotest.ch/api_v1?action=wuerenlos_latest_data&user_id=29",
)
SCRAPE_INTERVAL_MINUTES = int(os.getenv("SCRAPE_INTERVAL_MINUTES", "10"))

HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; weather-crawler/1.0)"}

g_temperature = Gauge("weather_temperature_celsius",    "Lufttemperatur °C")
g_humidity    = Gauge("weather_humidity_percent",       "Luftfeuchtigkeit %")
g_rain        = Gauge("weather_rain_mm",                "Regenmenge mm")
g_wind_speed  = Gauge("weather_wind_speed_kmh",         "Windgeschwindigkeit km/h")
g_wind_dir    = Gauge("weather_wind_direction_degrees", "Windrichtung °")
g_success     = Gauge("weather_scrape_success",         "1 = letzter Scrape ok")
g_duration    = Gauge("weather_scrape_duration_seconds","Scrape-Dauer Sekunden")
g_last_scrape = Gauge("weather_last_scrape_timestamp",  "Unix-Timestamp letzter Scrape")

state: dict = {"current": {}, "last_ok": None}

WIND_DIRS = ["N","NNO","NO","ONO","O","OSO","SO","SSO","S","SSW","SW","WSW","W","WNW","NW","NNW"]

def deg_to_compass(deg: float) -> str:
    return WIND_DIRS[round(deg / 22.5) % 16]


def log(level: str, event: str, **kw):
    print(json.dumps({"ts": datetime.now(timezone.utc).isoformat(), "level": level, "event": event, **kw}, ensure_ascii=False), flush=True)


async def do_scrape():
    start = time.monotonic()
    try:
        async with httpx.AsyncClient(headers=HEADERS, timeout=15, follow_redirects=True) as client:
            r = await client.get(API_URL)
        r.raise_for_status()
        body = r.json()

        payload = body.get("payload", {})
        station = next(iter(payload.values())) if payload else {}

        def val(key: str) -> float | None:
            v = station.get(key, {}).get("value")
            return float(v) if v is not None else None

        temp      = val("tt")
        humidity  = val("rh")
        rain      = val("rr10")
        wind_ms   = val("ff")
        wind_dir  = val("dd")
        wind_kmh  = round(wind_ms * 3.6, 1) if wind_ms is not None else None
        timestamp = station.get("tt", {}).get("timestamp", "")

        if temp     is not None: g_temperature.set(temp)
        if humidity is not None: g_humidity.set(humidity)
        if rain     is not None: g_rain.set(rain)
        if wind_kmh is not None: g_wind_speed.set(wind_kmh)
        if wind_dir is not None: g_wind_dir.set(wind_dir)

        state["current"] = {
            "temperature": temp,
            "humidity":    humidity,
            "rain":        rain,
            "wind_speed":  wind_kmh,
            "wind_dir":    wind_dir,
            "wind_compass": deg_to_compass(wind_dir) if wind_dir is not None else None,
            "measured_at": timestamp,
            "scraped_at":  datetime.now(timezone.utc).isoformat(),
        }
        state["last_ok"] = datetime.now(timezone.utc)
        g_success.set(1)
        g_last_scrape.set(time.time())
        g_duration.set(time.monotonic() - start)

        log("info", "scrape_complete", duration_s=round(time.monotonic() - start, 2), **{
            k: v for k, v in state["current"].items() if k not in ("scraped_at",)
        })

    except Exception as exc:
        g_success.set(0)
        g_duration.set(time.monotonic() - start)
        log("error", "scrape_failed", error=str(exc))


@asynccontextmanager
async def lifespan(app: FastAPI):
    log("info", "startup", api_url=API_URL, interval_min=SCRAPE_INTERVAL_MINUTES)
    await do_scrape()
    scheduler = AsyncIOScheduler()
    scheduler.add_job(do_scrape, "interval", minutes=SCRAPE_INTERVAL_MINUTES)
    scheduler.start()
    yield
    scheduler.shutdown()


app = FastAPI(lifespan=lifespan)


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/healthz")
def health():
    return {"ok": True}


@app.get("/api/current")
def api_current():
    return state["current"]


@app.get("/", response_class=HTMLResponse)
def index():
    d = state["current"]
    last_ok  = state["last_ok"]
    last_str = last_ok.astimezone(TZ_ZURICH).strftime("%d.%m.%Y %H:%M") if last_ok else "—"
    meas_str = d.get("measured_at", "—")

    def card(icon: str, label: str, value, unit: str = "") -> str:
        display = f"{value:g} {unit}".strip() if value is not None else "—"
        return f"""
        <div class="card">
          <div class="icon">{icon}</div>
          <div class="label">{label}</div>
          <div class="value">{display}</div>
        </div>"""

    wind_display = f'{d.get("wind_speed", "—"):g} km/h {d.get("wind_compass", "")}' if d.get("wind_speed") is not None else "—"

    cards = "".join([
        card("🌡️", "Temperatur",      d.get("temperature"), "°C"),
        card("💧", "Luftfeuchtigkeit", d.get("humidity"),    "%"),
        card("🌧️", "Regen",           d.get("rain"),        "mm"),
        f'<div class="card"><div class="icon">💨</div><div class="label">Wind</div><div class="value">{wind_display}</div></div>',
    ])

    return f"""<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta http-equiv="refresh" content="600">
  <title>Wetter Würenlos</title>
  <style>
    *{{box-sizing:border-box;margin:0;padding:0}}
    body{{background:#0f1117;color:#e2e8f0;font-family:system-ui,sans-serif;padding:1.5rem 1rem}}
    h1{{font-size:1.4rem;font-weight:700;color:#a5b4fc;margin-bottom:0.25rem}}
    .sub{{font-size:0.78rem;color:#64748b;margin-bottom:1.5rem}}
    .grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:1rem;max-width:700px}}
    .card{{background:#1a1d27;border:1px solid #2d3148;border-radius:12px;padding:1.25rem;text-align:center}}
    .icon{{font-size:2rem;margin-bottom:0.5rem}}
    .label{{font-size:0.75rem;color:#94a3b8;margin-bottom:0.35rem}}
    .value{{font-size:1.4rem;font-weight:700;color:#f1f5f9}}
    .section{{margin-top:2rem;max-width:900px}}
    .section h2{{font-size:1rem;font-weight:600;color:#a5b4fc;margin-bottom:0.75rem}}
    .iframe-wrap{{border-radius:12px;overflow:hidden;width:100%}}
    iframe{{border:none;width:100%;display:block}}
    .two-col{{display:grid;grid-template-columns:1fr 1fr;gap:1rem;max-width:900px}}
    @media(max-width:600px){{.two-col{{grid-template-columns:1fr}}}}
    .footer{{margin-top:1.5rem;font-size:0.72rem;color:#475569}}
    a{{color:#6366f1}}
  </style>
</head>
<body>
  <h1>Wetterstation Würenlos</h1>
  <p class="sub">Messung: {meas_str} &nbsp;·&nbsp; Abgerufen: {last_str} &nbsp;·&nbsp; <a href="/metrics">Metrics</a></p>

  <div class="grid">{cards}</div>

  <div class="two-col">
    <div class="section">
      <h2>Regenradar</h2>
      <div class="iframe-wrap">
        <iframe src="https://embed.windy.com/embed2.html?lat=47.521&lon=8.267&zoom=9&level=surface&overlay=rain&menu=&message=true&marker=true&metricWind=km%2Fh&metricTemp=%C2%B0C&type=map"
                height="400" scrolling="no" loading="lazy"></iframe>
      </div>
    </div>
    <div class="section">
      <h2>Windkarte</h2>
      <div class="iframe-wrap">
        <iframe src="https://embed.windy.com/embed2.html?lat=47.521&lon=8.267&zoom=9&level=surface&overlay=wind&menu=&message=true&marker=true&metricWind=km%2Fh&metricTemp=%C2%B0C&type=map"
                height="400" scrolling="no" loading="lazy"></iframe>
      </div>
    </div>
  </div>

  <p class="footer">Daten: messtechnik.meteotest.ch · Intervall: {SCRAPE_INTERVAL_MINUTES} min</p>
</body>
</html>"""
