
from datetime import datetime, timezone
import logging
from pathlib import Path
import time
import sqlite3

import requests
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="Kerala Climate Twin API")
logger = logging.getLogger("kerala_climate_twin")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

DB_PATH = Path(__file__).with_name("climate.db")
OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"

DISTRICTS = {
    "Thiruvananthapuram": (8.5241, 76.9366),
    "Kollam": (8.8932, 76.6141),
    "Pathanamthitta": (9.2648, 76.7870),
    "Alappuzha": (9.4981, 76.3388),
    "Kottayam": (9.5916, 76.5222),
    "Idukki": (9.8494, 76.9720),
    "Kochi": (9.9312, 76.2673),
    "Thrissur": (10.5276, 76.2144),
    "Palakkad": (10.7867, 76.6548),
    "Malappuram": (11.0510, 76.0711),
    "Kozhikode": (11.2588, 75.7804),
    "Wayanad": (11.6854, 76.1320),
    "Kannur": (11.8745, 75.3704),
    "Kasaragod": (12.4996, 74.9869),
}


def initialise_database():
    with sqlite3.connect(DB_PATH) as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS weather_snapshots (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                district TEXT NOT NULL,
                fetched_at TEXT NOT NULL,
                weather_time TEXT,
                temperature_c REAL,
                humidity_percent REAL,
                precipitation_mm REAL,
                wind_speed_kmh REAL,
                cloud_cover_percent REAL,
                source TEXT NOT NULL
            )
        """)


initialise_database()


@app.get("/")
def home():
    return {
        "message": "Kerala Climate Twin API is running",
        "docs": "/docs",
    }


@app.get("/api/districts")
def get_districts():
    return [
        {
            "name": name,
            "latitude": coordinates[0],
            "longitude": coordinates[1],
        }
        for name, coordinates in DISTRICTS.items()
    ]


@app.get("/api/weather/{district}")
def get_weather(district: str):
    matched_name = next(
        (name for name in DISTRICTS if name.lower() == district.lower()),
        None,
    )

    if matched_name is None:
        raise HTTPException(
            status_code=404,
            detail="District/location not found",
        )

    latitude, longitude = DISTRICTS[matched_name]

    params = {
        "latitude": latitude,
        "longitude": longitude,
        "current": (
            "temperature_2m,relative_humidity_2m,precipitation,"
            "wind_speed_10m,wind_direction_10m,cloud_cover,weather_code"
        ),
        "hourly": (
            "temperature_2m,precipitation,wind_speed_10m,"
            "wind_direction_10m,relative_humidity_2m,cloud_cover"
        ),
        "forecast_days": 3,
        "timezone": "Asia/Kolkata",
    }

    try:
        response = None
        for attempt in range(2):
            try:
                response = requests.get(
                    OPEN_METEO_URL,
                    params=params,
                    headers={
                        "Accept": "application/json",
                        "User-Agent": "KeralaClimateTwin/1.0",
                    },
                    timeout=20,
                )
                response.raise_for_status()
                break
            except requests.RequestException:
                if attempt == 1:
                    raise
                time.sleep(1)

        if response is None:
            raise requests.RequestException("No response from weather provider")

        payload = response.json()

        current = payload.get("current")
        if not isinstance(current, dict):
            raise ValueError("Current weather data is missing")

        required = [
            "temperature_2m",
            "relative_humidity_2m",
            "precipitation",
            "wind_speed_10m",
            "wind_direction_10m",
            "cloud_cover",
            "weather_code",
            "time",
        ]

        if any(current.get(key) is None for key in required):
            raise ValueError("One or more weather values are missing")

        fetched_at = datetime.now(timezone.utc).isoformat()

        result = {
            "district": matched_name,
            "latitude": latitude,
            "longitude": longitude,
            "temperature_c": current["temperature_2m"],
            "humidity_percent": current["relative_humidity_2m"],
            "precipitation_mm": current["precipitation"],
            "wind_speed_kmh": current["wind_speed_10m"],
            "cloud_cover_percent": current["cloud_cover"],
            "weather_code": current["weather_code"],
            "weather_time": current["time"],
            "fetched_at": fetched_at,
            "timezone": payload.get("timezone", "Asia/Kolkata"),
            "source": "Open-Meteo Forecast API",
            "data_type": "Model-based current conditions",
            "attribution": "Weather data by Open-Meteo.com",
            "hourly": payload.get("hourly", {}),
            "wind_direction_degrees": current["wind_direction_10m"],
        }

        with sqlite3.connect(DB_PATH) as conn:
            conn.execute("""
                INSERT INTO weather_snapshots (
                    district, fetched_at, weather_time,
                    temperature_c, humidity_percent,
                    precipitation_mm, wind_speed_kmh,
                    cloud_cover_percent, source
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                matched_name,
                fetched_at,
                current["time"],
                current["temperature_2m"],
                current["relative_humidity_2m"],
                current["precipitation"],
                current["wind_speed_10m"],
                current["cloud_cover"],
                "Open-Meteo Forecast API",
            ))

        return result

    except requests.RequestException as exc:
        upstream_status = (
            exc.response.status_code
            if exc.response is not None
            else "no response"
        )
        upstream_body = (
            exc.response.text[:300]
            if exc.response is not None
            else str(exc)
        )
        logger.exception(
            "Open-Meteo request failed for %s (status %s): %s",
            matched_name,
            upstream_status,
            upstream_body,
        )
        raise HTTPException(
            status_code=502,
            detail=(
                "Weather provider unavailable. "
                f"Upstream status: {upstream_status}. "
                f"Reason: {upstream_body}"
            ),
        ) from exc
    except (ValueError, KeyError, TypeError) as exc:
        raise HTTPException(
            status_code=502,
            detail="Weather provider returned incomplete data.",
        ) from exc


@app.get("/api/history/{district}")
def get_history(district: str):
    matched_name = next(
        (name for name in DISTRICTS if name.lower() == district.lower()),
        None,
    )

    if matched_name is None:
        raise HTTPException(
            status_code=404,
            detail="District/location not found",
        )

    with sqlite3.connect(DB_PATH) as conn:
        conn.row_factory = sqlite3.Row
        rows = conn.execute("""
            SELECT * FROM weather_snapshots
            WHERE district = ?
            ORDER BY id DESC
            LIMIT 100
        """, (matched_name,)).fetchall()

    return {
        "district": matched_name,
        "records": [dict(row) for row in rows],
    }

from datetime import date, timedelta


@app.get("/api/climate/history/{district}")
def get_historical_climate(
    district: str,
    start_date: date,
    end_date: date,
):
    matched_name = next(
        (name for name in DISTRICTS if name.lower() == district.lower()),
        None,
    )

    if matched_name is None:
        raise HTTPException(
            status_code=404,
            detail="District/location not found",
        )

    if start_date > end_date:
        raise HTTPException(
            status_code=400,
            detail="start_date must be on or before end_date",
        )

    # Limit requests to one year at a time.
    if (end_date - start_date).days > 366:
        raise HTTPException(
            status_code=400,
            detail="Please request a maximum of 367 calendar days at a time",
        )

    # Recent ERA5-based historical data may have a delay.
    # Use data ending at least 5 days before today.
    latest_available_date = date.today() - timedelta(days=5)

    if end_date > latest_available_date:
        raise HTTPException(
            status_code=400,
            detail=(
                "For this historical endpoint, choose an end_date "
                f"on or before {latest_available_date.isoformat()}"
            ),
        )

    latitude, longitude = DISTRICTS[matched_name]

    params = {
        "latitude": latitude,
        "longitude": longitude,
        "start_date": start_date.isoformat(),
        "end_date": end_date.isoformat(),
        "daily": (
            "temperature_2m_mean,"
            "temperature_2m_max,"
            "temperature_2m_min,"
            "precipitation_sum"
        ),
        "timezone": "Asia/Kolkata",
        "models": "era5",
    }

    try:
        response = requests.get(
            "https://archive-api.open-meteo.com/v1/archive",
            params=params,
            timeout=30,
        )
        response.raise_for_status()
        payload = response.json()

        daily = payload.get("daily")
        if not isinstance(daily, dict):
            raise ValueError("Historical daily data is missing")

        times = daily.get("time", [])
        temperatures = daily.get("temperature_2m_mean", [])
        maximums = daily.get("temperature_2m_max", [])
        minimums = daily.get("temperature_2m_min", [])
        rainfall = daily.get("precipitation_sum", [])

        if not all(
            isinstance(values, list)
            for values in [times, temperatures, maximums, minimums, rainfall]
        ):
            raise ValueError("Historical data arrays are invalid")

        if not (
            len(times)
            == len(temperatures)
            == len(maximums)
            == len(minimums)
            == len(rainfall)
        ):
            raise ValueError("Historical data arrays have different lengths")

        records = []
        for index, day in enumerate(times):
            records.append({
                "date": day,
                "temperature_mean_c": temperatures[index],
                "temperature_max_c": maximums[index],
                "temperature_min_c": minimums[index],
                "precipitation_mm": rainfall[index],
            })

        valid_temperatures = [
            value for value in temperatures if isinstance(value, (int, float))
        ]
        valid_rainfall = [
            value for value in rainfall if isinstance(value, (int, float))
        ]

        return {
            "district": matched_name,
            "latitude": latitude,
            "longitude": longitude,
            "start_date": start_date.isoformat(),
            "end_date": end_date.isoformat(),
            "model": "ERA5",
            "source": "Open-Meteo Historical Weather API",
            "timezone": payload.get("timezone", "Asia/Kolkata"),
            "summary": {
                "average_temperature_c": (
                    round(sum(valid_temperatures) / len(valid_temperatures), 2)
                    if valid_temperatures else None
                ),
                "total_precipitation_mm": (
                    round(sum(valid_rainfall), 2)
                    if valid_rainfall else None
                ),
                "days_returned": len(records),
            },
            "daily": records,
        }

    except requests.RequestException as exc:
        raise HTTPException(
            status_code=502,
            detail="Historical weather provider unavailable. Please retry.",
        ) from exc
    except (ValueError, KeyError, TypeError) as exc:
        raise HTTPException(
            status_code=502,
            detail="Historical weather provider returned invalid data.",
        ) from exc

import math


@app.get("/api/climate/wind-grid")
def get_wind_grid():
    """
    Return gridded wind samples over Kerala for map visualization.
    Wind components describe the direction the air is moving toward.
    """

    # Approximate regional grid covering Kerala and nearby areas.
    latitudes = []
    latitude = 8.0
    while latitude <= 12.5:
        latitudes.append(round(latitude, 2))
        latitude += 0.5

    longitudes = []
    longitude = 74.5
    while longitude <= 77.5:
        longitudes.append(round(longitude, 2))
        longitude += 0.5

    grid_points = [
        (lat, lon)
        for lat in latitudes
        for lon in longitudes
    ]

    params = {
        "latitude": ",".join(str(lat) for lat, _ in grid_points),
        "longitude": ",".join(str(lon) for _, lon in grid_points),
        "current": "wind_speed_10m,wind_direction_10m",
        "wind_speed_unit": "kmh",
        "timezone": "Asia/Kolkata",
    }

    try:
        response = requests.get(
            OPEN_METEO_URL,
            params=params,
            timeout=45,
        )
        response.raise_for_status()
        payload = response.json()

        # A multi-coordinate request normally returns a list of locations.
        # Also support a single-object response defensively.
        if isinstance(payload, dict):
            payload = [payload]

        if not isinstance(payload, list):
            raise ValueError("Unexpected wind-grid response format")

        points = []

        for index, item in enumerate(payload):
            if index >= len(grid_points) or not isinstance(item, dict):
                continue

            current = item.get("current", {})
            if not isinstance(current, dict):
                continue

            speed = current.get("wind_speed_10m")
            direction = current.get("wind_direction_10m")

            if speed is None or direction is None:
                continue

            speed = float(speed)
            direction = float(direction)

            # Meteorological direction is where wind comes FROM.
            # Convert it into the direction the air moves TOWARD.
            radians = math.radians(direction)
            u = -speed * math.sin(radians)
            v = -speed * math.cos(radians)

            latitude, longitude = grid_points[index]

            points.append({
                "latitude": latitude,
                "longitude": longitude,
                "wind_speed_kmh": speed,
                "wind_direction_degrees": direction,
                "u_kmh": round(u, 3),
                "v_kmh": round(v, 3),
                "weather_time": current.get("time"),
            })

        if not points:
            raise ValueError("No usable wind-grid points returned")

        return {
            "source": "Open-Meteo Forecast API",
            "data_type": "Model-based wind estimates",
            "timezone": "Asia/Kolkata",
            "grid_spacing_degrees": 0.5,
            "units": {
                "wind_speed": "km/h",
                "wind_direction": "degrees clockwise from north",
                "u": "km/h eastward",
                "v": "km/h northward",
            },
            "point_count": len(points),
            "points": points,
        }

    except requests.RequestException as exc:
        raise HTTPException(
            status_code=502,
            detail="Wind data provider unavailable. Please retry.",
        ) from exc
    except (ValueError, KeyError, TypeError, OverflowError) as exc:
        raise HTTPException(
            status_code=502,
            detail="Wind data provider returned invalid grid data.",
        ) from exc


@app.get("/api/climate/forecast-grid")
def get_forecast_grid(
    hour: int = 0,
    variable: str = "temperature",
):
    """Return forecast values on a grid covering Kerala."""

    if hour < 0 or hour > 71:
        raise HTTPException(
            status_code=400,
            detail="Hour must be between 0 and 71",
        )

    if variable not in ("temperature", "rainfall"):
        raise HTTPException(
            status_code=400,
            detail="Variable must be temperature or rainfall",
        )

    latitudes = []
    latitude = 8.0
    while latitude <= 12.5:
        latitudes.append(round(latitude, 2))
        latitude += 0.5

    longitudes = []
    longitude = 74.5
    while longitude <= 77.5:
        longitudes.append(round(longitude, 2))
        longitude += 0.5

    grid_points = [
        (lat, lon)
        for lat in latitudes
        for lon in longitudes
    ]

    hourly_variable = (
        "temperature_2m"
        if variable == "temperature"
        else "precipitation"
    )

    params = {
        "latitude": ",".join(str(lat) for lat, _ in grid_points),
        "longitude": ",".join(str(lon) for _, lon in grid_points),
        "hourly": hourly_variable,
        "forecast_days": 3,
        "timezone": "Asia/Kolkata",
    }

    try:
        response = requests.get(
            OPEN_METEO_URL,
            params=params,
            timeout=45,
        )
        response.raise_for_status()
        payload = response.json()

        if isinstance(payload, dict):
            payload = [payload]

        if not isinstance(payload, list):
            raise ValueError("Unexpected forecast-grid response")

        points = []

        for index, item in enumerate(payload):
            if index >= len(grid_points) or not isinstance(item, dict):
                continue

            hourly = item.get("hourly", {})
            times = hourly.get("time", [])
            values = hourly.get(hourly_variable, [])

            if hour >= len(times) or hour >= len(values):
                continue

            value = values[hour]
            if value is None:
                continue

            lat, lon = grid_points[index]

            points.append({
                "latitude": lat,
                "longitude": lon,
                "value": float(value),
                "time": times[hour],
            })

        if not points:
            raise ValueError("No forecast-grid values returned")

        return {
            "source": "Open-Meteo Forecast API",
            "data_type": "Model-based forecast grid",
            "variable": variable,
            "unit": "°C" if variable == "temperature" else "mm",
            "hour_index": hour,
            "time": points[0]["time"],
            "point_count": len(points),
            "points": points,
        }

    except requests.RequestException as exc:
        raise HTTPException(
            status_code=502,
            detail="Forecast provider unavailable. Please retry.",
        ) from exc
    except (ValueError, KeyError, TypeError, OverflowError) as exc:
        raise HTTPException(
            status_code=502,
            detail="Forecast provider returned invalid grid data.",
        ) from exc
