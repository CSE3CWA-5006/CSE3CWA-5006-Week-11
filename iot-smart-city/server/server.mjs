// Copyright (C) 2026 Dr Shuo Ding <shuoding@outlook.com>

import { createReadStream, existsSync, statSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { join, normalize, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { DatabaseSync } from "node:sqlite";

const __dirname = fileURLToPath(new URL(".", import.meta.url));
const rootDir = resolve(__dirname, "..");
const publicDir = join(rootDir, "public");
const dbPath = process.env.IOT_DB || join(rootDir, "data", "smart_city_iot.sqlite");
const port = Number(process.env.PORT || 5177);

if (!existsSync(dbPath)) {
  console.error(`SQLite database not found: ${dbPath}`);
  console.error("Use the prepared data/smart_city_iot.sqlite database from the GitHub repository, or ask your lecturer before rebuilding the database.");
  process.exit(1);
}

const db = new DatabaseSync(dbPath, { readOnly: true });

const mimeTypes = new Map([
  [".html", "text/html; charset=utf-8"],
  [".js", "text/javascript; charset=utf-8"],
  [".css", "text/css; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".svg", "image/svg+xml"],
  [".png", "image/png"],
  [".ico", "image/x-icon"],
]);

function sendJson(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(body),
    "Cache-Control": "no-store",
  });
  res.end(body);
}

function sendError(res, status, message) {
  sendJson(res, status, { error: message });
}

function getMetadata() {
  const rows = db.prepare("SELECT key, value FROM metadata").all();
  return Object.fromEntries(rows.map((row) => [row.key, row.value]));
}

function getBootstrap() {
  const metadata = getMetadata();
  const sensors = db
    .prepare(
      `
      SELECT sensor_id, sensor_type, tag_type, sensor_sub_type, fake_place, fake_area,
             fake_x, fake_y, fake_lat, fake_lng, reading_count, value_min, value_max,
             first_timestamp_ms, last_timestamp_ms
      FROM sensors
      ORDER BY sensor_type, fake_place, sensor_id
      `
    )
    .all();

  const sensorTypes = db
    .prepare(
      `
      SELECT sensor_type,
             COUNT(*) AS sensor_count,
             SUM(reading_count) AS reading_count,
             MIN(value_min) AS value_min,
             MAX(value_max) AS value_max
      FROM sensors
      GROUP BY sensor_type
      ORDER BY reading_count DESC
      `
    )
    .all();

  return {
    metadata,
    sensors,
    sensorTypes,
    minTimestamp: Number(metadata.min_timestamp_ms || 0),
    maxTimestamp: Number(metadata.max_timestamp_ms || 0),
    map: {
      width: Number(metadata.map_width || 1200),
      height: Number(metadata.map_height || 760),
    },
  };
}

function handleBootstrap(_req, res) {
  sendJson(res, 200, getBootstrap());
}

function handleSensorReadings(url, res) {
  const sensorId = url.searchParams.get("sensorId");
  if (!sensorId) {
    sendError(res, 400, "sensorId is required");
    return;
  }

  const limit = Math.min(Number(url.searchParams.get("limit") || 600), 5000);
  const before = Number(url.searchParams.get("before") || 0);
  const hasBefore = Number.isFinite(before) && before > 0;
  const rows = db
    .prepare(
      `
      SELECT timestamp_ms, value
      FROM readings
      WHERE sensor_id = ?
      ${hasBefore ? "AND timestamp_ms <= ?" : ""}
      ORDER BY timestamp_ms DESC
      LIMIT ?
      `
    )
    .all(...(hasBefore ? [sensorId, before, limit] : [sensorId, limit]))
    .reverse();

  sendJson(res, 200, { sensorId, rows });
}

function createStreamQuery(sensorType) {
  const hasTypeFilter = sensorType && sensorType !== "All";
  const sql = `
    SELECT r.sensor_id, r.timestamp_ms, r.value,
           s.sensor_type, s.fake_place, s.fake_area, s.fake_x, s.fake_y, s.fake_lat, s.fake_lng
    FROM readings r
    JOIN sensors s ON s.sensor_id = r.sensor_id
    WHERE r.timestamp_ms > ? AND r.timestamp_ms <= ?
    ${hasTypeFilter ? "AND s.sensor_type = ?" : ""}
    ORDER BY r.timestamp_ms ASC
    LIMIT ?
  `;
  return {
    statement: db.prepare(sql),
    hasTypeFilter,
  };
}

function streamEvent(res, event, payload) {
  res.write(`event: ${event}\n`);
  res.write(`data: ${JSON.stringify(payload)}\n\n`);
}

function handleStream(req, res, url) {
  const bootstrap = getBootstrap();
  const speed = Math.max(1, Math.min(Number(url.searchParams.get("speed") || 3600), 604800));
  const sensorType = url.searchParams.get("sensorType") || "All";
  const maxRows = Math.max(250, Math.min(Number(url.searchParams.get("maxRows") || 5000), 20000));
  const loop = url.searchParams.get("loop") !== "false";
  const startParam = Number(url.searchParams.get("start") || 0);
  let lastMs =
    Number.isFinite(startParam) && startParam >= bootstrap.minTimestamp && startParam < bootstrap.maxTimestamp
      ? startParam
      : bootstrap.minTimestamp;
  let currentMs = lastMs;
  const query = createStreamQuery(sensorType);

  res.writeHead(200, {
    "Content-Type": "text/event-stream; charset=utf-8",
    "Cache-Control": "no-cache, no-transform",
    Connection: "keep-alive",
    "X-Accel-Buffering": "no",
  });

  streamEvent(res, "init", {
    minTimestamp: bootstrap.minTimestamp,
    maxTimestamp: bootstrap.maxTimestamp,
    currentMs,
    speed,
    sensorType,
  });

  const tick = () => {
    if (currentMs >= bootstrap.maxTimestamp) {
      if (!loop) {
        streamEvent(res, "done", { currentMs });
        clearInterval(timer);
        res.end();
        return;
      }
      lastMs = bootstrap.minTimestamp;
      currentMs = bootstrap.minTimestamp;
    }

    currentMs = Math.min(currentMs + speed * 1000, bootstrap.maxTimestamp);
    const rows = query.hasTypeFilter
      ? query.statement.all(lastMs, currentMs, sensorType, maxRows + 1)
      : query.statement.all(lastMs, currentMs, maxRows + 1);
    const truncated = rows.length > maxRows;
    const payloadRows = truncated ? rows.slice(0, maxRows) : rows;

    streamEvent(res, "tick", {
      currentMs,
      previousMs: lastMs,
      speed,
      sensorType,
      rows: payloadRows,
      count: payloadRows.length,
      truncated,
    });
    lastMs = currentMs;
  };

  const timer = setInterval(tick, 1000);
  tick();

  req.on("close", () => clearInterval(timer));
}

async function serveStatic(req, res, url) {
  let pathname = decodeURIComponent(url.pathname);
  if (pathname === "/") {
    pathname = "/index.html";
  }

  const filePath = normalize(join(publicDir, pathname));
  if (!filePath.startsWith(publicDir)) {
    sendError(res, 403, "Forbidden");
    return;
  }

  if (!existsSync(filePath) || !statSync(filePath).isFile()) {
    const indexPath = join(publicDir, "index.html");
    const body = await readFile(indexPath);
    res.writeHead(200, {
      "Content-Type": "text/html; charset=utf-8",
      "Content-Length": body.length,
    });
    res.end(body);
    return;
  }

  const extension = filePath.slice(filePath.lastIndexOf("."));
  const contentType = mimeTypes.get(extension) || "application/octet-stream";
  res.writeHead(200, {
    "Content-Type": contentType,
    "Cache-Control": "no-cache",
  });
  createReadStream(filePath).pipe(res);
}

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);

    if (url.pathname === "/api/health") {
      sendJson(res, 200, { ok: true, dbPath });
      return;
    }

    if (url.pathname === "/api/bootstrap") {
      handleBootstrap(req, res);
      return;
    }

    if (url.pathname === "/api/readings") {
      handleSensorReadings(url, res);
      return;
    }

    if (url.pathname === "/api/stream") {
      handleStream(req, res, url);
      return;
    }

    await serveStatic(req, res, url);
  } catch (error) {
    console.error(error);
    if (!res.headersSent) {
      sendError(res, 500, error.message || "Internal server error");
    } else {
      res.end();
    }
  }
});

server.listen(port, () => {
  console.log(`Anonymized IoT Replay running at http://localhost:${port}`);
  console.log(`SQLite: ${dbPath}`);
});
