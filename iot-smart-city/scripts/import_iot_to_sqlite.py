# Copyright (C) 2026 Dr Shuo Ding <shuoding@outlook.com>

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

import pandas as pd


WIDTH = 1200.0
HEIGHT = 760.0
PADDING = 78.0
TARGET_CENTER_LAT = -33.8216
TARGET_CENTER_LNG = 151.0451
TARGET_SPAN_X_METERS = 15_000.0
TARGET_SPAN_Y_METERS = 10_000.0

PLACE_LEFT = [
    "Aster",
    "Brindle",
    "Cairn",
    "Dovetail",
    "Elara",
    "Fallow",
    "Glen",
    "Harbor",
    "Ironwood",
    "Juniper",
    "Kite",
    "Lumen",
    "Marble",
    "Northstar",
    "Orchard",
    "Pioneer",
    "Quartz",
    "Ridge",
    "Solace",
    "Tallow",
    "Umber",
    "Vale",
    "Wattle",
    "Yarrow",
]

PLACE_RIGHT = [
    "Basin",
    "Bridge",
    "Circuit",
    "Common",
    "Crossing",
    "Field",
    "Gate",
    "Grove",
    "Harbour",
    "Junction",
    "Landing",
    "Market",
    "Park",
    "Quay",
    "Reach",
    "Reserve",
    "Rise",
    "Square",
    "Station",
    "Terrace",
    "Walk",
    "Yard",
]

AREA_WORDS = [
    "North District",
    "East District",
    "South District",
    "West District",
    "Central District",
    "Riverside District",
    "Upland District",
    "Meadow District",
    "Harbourline District",
    "Garden District",
]

SENSOR_TYPE_MAP = {
    "aqi": "Air Quality",
    "air quality": "Air Quality",
    "bin": "Bin",
    "bin level": "Bin",
    "people counter": "People Counter",
    "people counting": "People Counter",
    "temperature": "Temperature",
    "humidity": "Humidity",
    "pressure": "Pressure",
    "water level": "Water Level",
    "asset tracking": "Asset Tracking",
    "gateway": "Gateway",
    "speed": "Asset Tracking",
}


def stable_hash(value: str, length: int = 12) -> str:
    return hashlib.sha256(value.encode("utf-8", errors="ignore")).hexdigest()[:length]


def stable_unit(value: str, salt: str = "") -> float:
    raw = hashlib.sha256(f"{salt}|{value}".encode("utf-8", errors="ignore")).hexdigest()[:12]
    return int(raw, 16) / float(0xFFFFFFFFFFFF)


def clean_text(value: Any) -> str:
    if value is None:
        return ""
    try:
        if pd.isna(value):
            return ""
    except TypeError:
        pass
    text = str(value).strip()
    if text.lower() in {"nan", "none", "null"}:
        return ""
    return text


def normalize_sensor_type(sensor_type: Any, tag_type: Any, name: Any = "", channel_desc: Any = "") -> str:
    candidates = [clean_text(sensor_type), clean_text(tag_type), clean_text(name), clean_text(channel_desc)]
    for candidate in candidates:
        key = candidate.lower()
        if key in SENSOR_TYPE_MAP:
            return SENSOR_TYPE_MAP[key]
    for candidate in candidates:
        key = candidate.lower()
        for fragment, normalized in SENSOR_TYPE_MAP.items():
            if fragment in key:
                return normalized
    return "Unknown"


def normalize_columns(df: pd.DataFrame) -> pd.DataFrame:
    rename: dict[Any, str] = {}
    for col in df.columns:
        key = str(col).strip()
        lower = key.lower()
        if lower == "locationname":
            rename[col] = "name"
        elif lower == "locationowner":
            rename[col] = "owner"
        else:
            rename[col] = lower
    return df.rename(columns=rename)


def row_value(row: dict[str, Any], key: str, default: Any = "") -> Any:
    return row.get(key, default)


def build_entity_key(row: dict[str, Any], sensor_type: str) -> str:
    network = clean_text(row_value(row, "networkid"))
    serial = clean_text(row_value(row, "serial"))
    name = clean_text(row_value(row, "name"))
    fallback = clean_text(row_value(row, "id")) or "unknown-device"
    source_id = network or serial or name or fallback
    channel = clean_text(row_value(row, "channel")) or "0"
    tag_type = clean_text(row_value(row, "tag_type"))
    tag_number = clean_text(row_value(row, "tag_number"))
    return "|".join([source_id, channel, sensor_type, tag_type, tag_number])


def build_place_key(row: dict[str, Any], entity_key: str) -> str:
    owner = clean_text(row_value(row, "owner"))
    location = clean_text(row_value(row, "sensor_location"))
    detail = clean_text(row_value(row, "sensor_location_detail"))
    if location or detail:
        return "|".join(["place", owner, location, detail]).lower()

    lat = pd.to_numeric(pd.Series([row_value(row, "lat")]), errors="coerce").iloc[0]
    lng = pd.to_numeric(pd.Series([row_value(row, "lng")]), errors="coerce").iloc[0]
    if not pd.isna(lat) and not pd.isna(lng):
        return f"coord|{round(float(lat), 4)}|{round(float(lng), 4)}"

    return f"entity|{stable_hash(entity_key, 16)}"


def fake_place_name(place_key: str, used: set[str]) -> str:
    base = int(stable_hash(place_key, 12), 16)
    left = PLACE_LEFT[base % len(PLACE_LEFT)]
    right = PLACE_RIGHT[(base // len(PLACE_LEFT)) % len(PLACE_RIGHT)]
    name = f"{left} {right}"
    if name not in used:
        used.add(name)
        return name

    suffix = 2
    while f"{name} {suffix}" in used:
        suffix += 1
    final = f"{name} {suffix}"
    used.add(final)
    return final


def fake_area_name(owner_key: str) -> str:
    if not owner_key:
        owner_key = "unknown"
    idx = int(stable_hash(owner_key, 8), 16) % len(AREA_WORDS)
    return AREA_WORDS[idx]


def discover_sources(input_path: Path, include_all_files: bool) -> list[Path]:
    if input_path.is_file():
        return [input_path]
    if not input_path.exists():
        raise FileNotFoundError(f"Input path does not exist: {input_path}")

    preferred = [input_path / "all.csv", input_path / "IoTData.csv", input_path / "allIoT.xlsx"]
    if not include_all_files:
        for source in preferred:
            if source.exists():
                return [source]

    sources = sorted(
        [
            path
            for path in input_path.iterdir()
            if path.is_file() and path.suffix.lower() in {".csv", ".xlsx", ".xls"}
        ]
    )
    if not sources:
        raise FileNotFoundError(f"No CSV or Excel files found in: {input_path}")
    return sources


def iter_frames(path: Path, chunksize: int) -> Iterable[pd.DataFrame]:
    suffix = path.suffix.lower()
    if suffix == ".csv":
        for chunk in pd.read_csv(path, chunksize=chunksize, low_memory=False):
            yield normalize_columns(chunk)
        return

    if suffix in {".xlsx", ".xls"}:
        excel = pd.ExcelFile(path)
        for sheet in excel.sheet_names:
            yield normalize_columns(pd.read_excel(path, sheet_name=sheet))
        return

    raise ValueError(f"Unsupported source type: {path}")


def init_db(output: Path, replace: bool) -> sqlite3.Connection:
    output.parent.mkdir(parents=True, exist_ok=True)
    if replace:
        for candidate in [output, Path(f"{output}-wal"), Path(f"{output}-shm")]:
            if candidate.exists():
                candidate.unlink()

    con = sqlite3.connect(output)
    con.execute("PRAGMA journal_mode=WAL")
    con.execute("PRAGMA synchronous=NORMAL")
    con.execute("PRAGMA temp_store=MEMORY")
    con.executescript(
        """
        CREATE TABLE IF NOT EXISTS sensors (
          sensor_id TEXT PRIMARY KEY,
          sensor_type TEXT NOT NULL,
          tag_type TEXT,
          sensor_sub_type TEXT,
          fake_place TEXT NOT NULL,
          fake_area TEXT NOT NULL,
          fake_x REAL NOT NULL,
          fake_y REAL NOT NULL,
          fake_lat REAL NOT NULL,
          fake_lng REAL NOT NULL,
          reading_count INTEGER NOT NULL DEFAULT 0,
          value_min REAL,
          value_max REAL,
          first_timestamp_ms INTEGER,
          last_timestamp_ms INTEGER
        );

        CREATE TABLE IF NOT EXISTS readings (
          reading_hash TEXT PRIMARY KEY,
          sensor_id TEXT NOT NULL,
          timestamp_ms INTEGER NOT NULL,
          value REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS metadata (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_readings_time ON readings(timestamp_ms);
        CREATE INDEX IF NOT EXISTS idx_readings_sensor_time ON readings(sensor_id, timestamp_ms);
        CREATE INDEX IF NOT EXISTS idx_sensors_type ON sensors(sensor_type);
        """
    )
    return con


def to_timestamp_ms(series: pd.Series) -> pd.Series:
    numeric = pd.to_numeric(series, errors="coerce")
    return numeric.round().astype("Int64")


def to_float_or_none(value: Any) -> float | None:
    try:
        numeric = pd.to_numeric(pd.Series([value]), errors="coerce").iloc[0]
    except Exception:
        return None
    if pd.isna(numeric):
        return None
    return float(numeric)


def update_meta(meta: dict[str, Any], row: dict[str, Any], timestamp_ms: int, value: float) -> None:
    meta["reading_count"] += 1
    meta["value_min"] = value if meta["value_min"] is None else min(meta["value_min"], value)
    meta["value_max"] = value if meta["value_max"] is None else max(meta["value_max"], value)
    meta["first_timestamp_ms"] = (
        timestamp_ms
        if meta["first_timestamp_ms"] is None
        else min(meta["first_timestamp_ms"], timestamp_ms)
    )
    meta["last_timestamp_ms"] = (
        timestamp_ms
        if meta["last_timestamp_ms"] is None
        else max(meta["last_timestamp_ms"], timestamp_ms)
    )

    lat = to_float_or_none(row_value(row, "lat"))
    lng = to_float_or_none(row_value(row, "lng"))
    if lat is not None and lng is not None:
        meta["lat_sum"] += lat
        meta["lng_sum"] += lng
        meta["coord_count"] += 1


def anonymize_coordinates(sensor_meta: dict[str, dict[str, Any]]) -> None:
    valid: list[tuple[str, float, float]] = []
    for sensor_id, meta in sensor_meta.items():
        if meta["coord_count"] > 0:
            valid.append(
                (
                    sensor_id,
                    meta["lat_sum"] / meta["coord_count"],
                    meta["lng_sum"] / meta["coord_count"],
                )
            )

    projected: dict[str, tuple[float, float]] = {}
    target_cos_lat = math.cos(math.radians(TARGET_CENTER_LAT))
    if valid:
        center_lat = sum(lat for _, lat, _ in valid) / len(valid)
        center_lng = sum(lng for _, _, lng in valid) / len(valid)
        cos_lat = math.cos(math.radians(center_lat))
        angle = math.radians(37.0)
        cos_a = math.cos(angle)
        sin_a = math.sin(angle)

        xs: list[float] = []
        ys: list[float] = []
        for sensor_id, lat, lng in valid:
            raw_x = (lng - center_lng) * 111_320.0 * cos_lat
            raw_y = (lat - center_lat) * 110_540.0
            x = raw_x * cos_a - raw_y * sin_a
            y = raw_x * sin_a + raw_y * cos_a
            projected[sensor_id] = (x, y)
            xs.append(x)
            ys.append(y)

        min_x, max_x = min(xs), max(xs)
        min_y, max_y = min(ys), max(ys)
        span_x = max(max_x - min_x, 1.0)
        span_y = max(max_y - min_y, 1.0)
        mid_x = min_x + span_x / 2.0
        mid_y = min_y + span_y / 2.0
        target_scale = min(TARGET_SPAN_X_METERS / span_x, TARGET_SPAN_Y_METERS / span_y)

        for sensor_id, (x, y) in projected.items():
            sensor_meta[sensor_id]["fake_x"] = PADDING + ((x - min_x) / span_x) * (WIDTH - PADDING * 2.0)
            sensor_meta[sensor_id]["fake_y"] = PADDING + ((max_y - y) / span_y) * (HEIGHT - PADDING * 2.0)
            target_x = (x - mid_x) * target_scale
            target_y = (y - mid_y) * target_scale
            sensor_meta[sensor_id]["fake_lat"] = TARGET_CENTER_LAT + target_y / 110_540.0
            sensor_meta[sensor_id]["fake_lng"] = TARGET_CENTER_LNG + target_x / (111_320.0 * target_cos_lat)

    for sensor_id, meta in sensor_meta.items():
        if meta.get("fake_x") is None:
            place_key = meta["place_key"]
            meta["fake_x"] = 120.0 + stable_unit(place_key, "x") * (WIDTH - 240.0)
            meta["fake_y"] = 110.0 + stable_unit(place_key, "y") * (HEIGHT - 220.0)
            target_x = (stable_unit(place_key, "lng") - 0.5) * TARGET_SPAN_X_METERS
            target_y = (stable_unit(place_key, "lat") - 0.5) * TARGET_SPAN_Y_METERS
            meta["fake_lat"] = TARGET_CENTER_LAT + target_y / 110_540.0
            meta["fake_lng"] = TARGET_CENTER_LNG + target_x / (111_320.0 * target_cos_lat)

        jitter_x = (stable_unit(sensor_id, "jx") - 0.5) * 22.0
        jitter_y = (stable_unit(sensor_id, "jy") - 0.5) * 22.0
        meta["fake_x"] = min(max(meta["fake_x"] + jitter_x, 30.0), WIDTH - 30.0)
        meta["fake_y"] = min(max(meta["fake_y"] + jitter_y, 30.0), HEIGHT - 30.0)
        jitter_lng_m = (stable_unit(sensor_id, "jlng") - 0.5) * 36.0
        jitter_lat_m = (stable_unit(sensor_id, "jlat") - 0.5) * 36.0
        meta["fake_lat"] = meta["fake_lat"] + jitter_lat_m / 110_540.0
        meta["fake_lng"] = meta["fake_lng"] + jitter_lng_m / (111_320.0 * target_cos_lat)


def import_sources(args: argparse.Namespace) -> dict[str, Any]:
    sources = discover_sources(Path(args.input), args.include_all_files)
    con = init_db(Path(args.output), args.replace)
    sensor_meta: dict[str, dict[str, Any]] = {}
    place_names: dict[str, str] = {}
    used_place_names: set[str] = set()
    total_rows_seen = 0
    total_rows_inserted = 0
    min_timestamp: int | None = None
    max_timestamp: int | None = None

    insert_sql = """
      INSERT OR IGNORE INTO readings (reading_hash, sensor_id, timestamp_ms, value)
      VALUES (?, ?, ?, ?)
    """

    for source in sources:
        print(f"Reading {source}", flush=True)
        for frame in iter_frames(source, args.chunksize):
            if "data_date" not in frame.columns or "data_val" not in frame.columns:
                print(f"Skipping frame without data_date/data_val in {source}", file=sys.stderr)
                continue

            frame = frame.copy()
            frame["timestamp_ms"] = to_timestamp_ms(frame["data_date"])
            frame["numeric_value"] = pd.to_numeric(frame["data_val"], errors="coerce")
            frame = frame.dropna(subset=["timestamp_ms", "numeric_value"])

            batch: list[tuple[str, str, int, float]] = []
            for row in frame.to_dict("records"):
                total_rows_seen += 1
                timestamp_ms = int(row["timestamp_ms"])
                value = float(row["numeric_value"])
                sensor_type = normalize_sensor_type(
                    row_value(row, "sensor_type"),
                    row_value(row, "tag_type"),
                    row_value(row, "name"),
                    row_value(row, "channel_desc"),
                )
                entity_key = build_entity_key(row, sensor_type)
                sensor_id = f"SEN-{stable_hash(entity_key, 10).upper()}"
                source_record = clean_text(row_value(row, "id"))
                if source_record:
                    reading_basis = f"{source_record}|{entity_key}|{timestamp_ms}|{value:.8f}"
                else:
                    reading_basis = f"{entity_key}|{timestamp_ms}|{value:.8f}"
                reading_hash = stable_hash(reading_basis, 32)

                place_key = build_place_key(row, entity_key)
                if place_key not in place_names:
                    place_names[place_key] = fake_place_name(place_key, used_place_names)

                if sensor_id not in sensor_meta:
                    owner_key = clean_text(row_value(row, "owner")).lower()
                    sensor_meta[sensor_id] = {
                        "sensor_type": sensor_type,
                        "tag_type": clean_text(row_value(row, "tag_type")),
                        "sensor_sub_type": clean_text(row_value(row, "sensor_sub_type")),
                        "fake_place": place_names[place_key],
                        "fake_area": fake_area_name(owner_key),
                        "place_key": place_key,
                        "reading_count": 0,
                        "value_min": None,
                        "value_max": None,
                        "first_timestamp_ms": None,
                        "last_timestamp_ms": None,
                        "lat_sum": 0.0,
                        "lng_sum": 0.0,
                        "coord_count": 0,
                        "fake_x": None,
                        "fake_y": None,
                    }

                update_meta(sensor_meta[sensor_id], row, timestamp_ms, value)
                min_timestamp = timestamp_ms if min_timestamp is None else min(min_timestamp, timestamp_ms)
                max_timestamp = timestamp_ms if max_timestamp is None else max(max_timestamp, timestamp_ms)
                batch.append((reading_hash, sensor_id, timestamp_ms, value))

            if batch:
                before = con.total_changes
                con.executemany(insert_sql, batch)
                con.commit()
                total_rows_inserted += con.total_changes - before

            if total_rows_seen and total_rows_seen % args.progress_every < args.chunksize:
                print(f"  processed {total_rows_seen:,} rows", flush=True)

    anonymize_coordinates(sensor_meta)

    con.execute("DELETE FROM sensors")
    sensor_rows = [
        (
            sensor_id,
            meta["sensor_type"],
            meta["tag_type"],
            meta["sensor_sub_type"],
            meta["fake_place"],
            meta["fake_area"],
            round(float(meta["fake_x"]), 3),
            round(float(meta["fake_y"]), 3),
            round(float(meta["fake_lat"]), 7),
            round(float(meta["fake_lng"]), 7),
            int(meta["reading_count"]),
            meta["value_min"],
            meta["value_max"],
            meta["first_timestamp_ms"],
            meta["last_timestamp_ms"],
        )
        for sensor_id, meta in sorted(sensor_meta.items())
    ]
    con.executemany(
        """
        INSERT INTO sensors (
          sensor_id, sensor_type, tag_type, sensor_sub_type, fake_place, fake_area,
          fake_x, fake_y, fake_lat, fake_lng, reading_count, value_min, value_max, first_timestamp_ms,
          last_timestamp_ms
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        sensor_rows,
    )

    metadata = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source_files": json.dumps([str(path) for path in sources]),
        "rows_seen": str(total_rows_seen),
        "rows_inserted": str(total_rows_inserted),
        "sensor_count": str(len(sensor_rows)),
        "place_count": str(len(place_names)),
        "min_timestamp_ms": str(min_timestamp or ""),
        "max_timestamp_ms": str(max_timestamp or ""),
        "map_width": str(int(WIDTH)),
        "map_height": str(int(HEIGHT)),
        "target_center_lat": str(TARGET_CENTER_LAT),
        "target_center_lng": str(TARGET_CENTER_LNG),
        "target_region": "NSW synthetic relocation near Sydney Olympic Park / Parramatta",
        "anonymization": "source addresses and source coordinates are not stored; fake NSW coordinates preserve relative proximity only",
    }
    con.executemany(
        "INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)",
        sorted(metadata.items()),
    )
    con.commit()
    con.execute("VACUUM")
    con.close()

    return {
        "sources": [str(path) for path in sources],
        "rows_seen": total_rows_seen,
        "rows_inserted": total_rows_inserted,
        "sensor_count": len(sensor_rows),
        "place_count": len(place_names),
        "output": str(Path(args.output).resolve()),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Import IoT CSV/XLSX data into anonymized SQLite.")
    parser.add_argument("--input", default=r"D:\iotdataback\IoTData\dataall", help="CSV/XLSX file or directory")
    parser.add_argument("--output", default="data/smart_city_iot.sqlite", help="SQLite output path")
    parser.add_argument("--replace", action="store_true", help="Replace the existing SQLite database")
    parser.add_argument("--include-all-files", action="store_true", help="Import every CSV/XLSX in a directory")
    parser.add_argument("--chunksize", type=int, default=50_000, help="CSV rows per chunk")
    parser.add_argument("--progress-every", type=int, default=100_000, help="Progress print interval")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    summary = import_sources(args)
    print(json.dumps(summary, indent=2), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
