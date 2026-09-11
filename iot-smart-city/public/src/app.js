// Copyright (C) 2026 Dr Shuo Ding <shuoding@outlook.com>

import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  Activity,
  Cpu,
  Droplets,
  Eye,
  EyeOff,
  Gauge,
  Layers,
  MapPin,
  Pause,
  Play,
  Radio,
  RotateCcw,
  Route,
  Search,
  Thermometer,
  TimerReset,
  Trash2,
  Users,
  Waves,
  Wind,
} from "lucide-react";

const h = React.createElement;

const TYPE_META = {
  "Air Quality": { color: "#38bdf8", icon: Wind },
  Bin: { color: "#f59e0b", icon: Trash2 },
  Humidity: { color: "#60a5fa", icon: Droplets },
  "People Counter": { color: "#22c55e", icon: Users },
  Pressure: { color: "#a78bfa", icon: Gauge },
  Temperature: { color: "#fb7185", icon: Thermometer },
  "Water Level": { color: "#14b8a6", icon: Waves },
  "Asset Tracking": { color: "#eab308", icon: Route },
  Gateway: { color: "#f97316", icon: Cpu },
  Unknown: { color: "#94a3b8", icon: Activity },
};

const SPEEDS = [
  { label: "1 min/s", value: 60 },
  { label: "15 min/s", value: 900 },
  { label: "1 hour/s", value: 3600 },
  { label: "6 hour/s", value: 21600 },
  { label: "1 day/s", value: 86400 },
];

function icon(Icon, props = {}) {
  return h(Icon, { size: 17, strokeWidth: 2.2, ...props });
}

function typeMeta(type) {
  return TYPE_META[type] || TYPE_META.Unknown;
}

function TypeIcon({ type, size = 17 }) {
  const meta = typeMeta(type);
  return h(
    "span",
    { className: "type-icon", style: { "--type-color": meta.color } },
    icon(meta.icon, { size })
  );
}

function formatDate(ms) {
  if (!ms) return "Waiting";
  return new Intl.DateTimeFormat("en-AU", {
    month: "short",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(ms));
}

function formatValue(value) {
  if (value === undefined || value === null || Number.isNaN(Number(value))) return "-";
  const abs = Math.abs(Number(value));
  if (abs >= 1000) return Number(value).toLocaleString(undefined, { maximumFractionDigits: 0 });
  if (abs >= 100) return Number(value).toLocaleString(undefined, { maximumFractionDigits: 1 });
  return Number(value).toLocaleString(undefined, { maximumFractionDigits: 2 });
}

function classNames(...items) {
  return items.filter(Boolean).join(" ");
}

function App() {
  const [bootstrap, setBootstrap] = useState(null);
  const [error, setError] = useState("");
  const [sensorType, setSensorType] = useState("All");
  const [selectedSensor, setSelectedSensor] = useState("");
  const [speed, setSpeed] = useState(3600);
  const [playing, setPlaying] = useState(true);
  const [currentMs, setCurrentMs] = useState(0);
  const [latest, setLatest] = useState({});
  const [chartPoints, setChartPoints] = useState([]);
  const [lastBatch, setLastBatch] = useState({ count: 0, truncated: false });
  const [visibleIds, setVisibleIds] = useState(null);
  const [resetToken, setResetToken] = useState(0);
  const [showLabels, setShowLabels] = useState(false);

  const currentMsRef = useRef(0);
  const selectedSensorRef = useRef(selectedSensor);
  const sensorTypeRef = useRef(sensorType);

  useEffect(() => {
    selectedSensorRef.current = selectedSensor;
    setChartPoints([]);
  }, [selectedSensor]);

  useEffect(() => {
    sensorTypeRef.current = sensorType;
    setSelectedSensor("");
    setChartPoints([]);
    setLatest({});
    setVisibleIds(null);
  }, [sensorType]);

  useEffect(() => {
    fetch("/api/bootstrap")
      .then((res) => {
        if (!res.ok) throw new Error(`Bootstrap failed: ${res.status}`);
        return res.json();
      })
      .then((data) => {
        setBootstrap(data);
        setCurrentMs(data.minTimestamp);
        currentMsRef.current = data.minTimestamp;
      })
      .catch((err) => setError(err.message));
  }, []);

  useEffect(() => {
    if (!bootstrap || !playing) return undefined;

    const params = new URLSearchParams({
      speed: String(speed),
      sensorType,
      start: String(currentMsRef.current || bootstrap.minTimestamp),
    });
    const events = new EventSource(`/api/stream?${params.toString()}`);

    events.addEventListener("tick", (event) => {
      const payload = JSON.parse(event.data);
      currentMsRef.current = payload.currentMs;
      setCurrentMs(payload.currentMs);
      setLastBatch({ count: payload.count, truncated: payload.truncated });

      if (payload.rows.length) {
        setLatest((prev) => {
          const next = { ...prev };
          for (const row of payload.rows) {
            next[row.sensor_id] = { ...row, receivedAt: Date.now() };
          }
          return next;
        });

        setChartPoints((prev) => {
          const selected = selectedSensorRef.current;
          let point = null;
          if (selected) {
            const selectedRows = payload.rows.filter((row) => row.sensor_id === selected);
            if (selectedRows.length) {
              const last = selectedRows[selectedRows.length - 1];
              point = {
                timestamp_ms: last.timestamp_ms,
                value: last.value,
                label: last.fake_place,
              };
            }
          } else {
            const values = payload.rows.map((row) => Number(row.value)).filter(Number.isFinite);
            if (values.length) {
              point = {
                timestamp_ms: payload.currentMs,
                value: values.reduce((sum, value) => sum + value, 0) / values.length,
                label: sensorTypeRef.current === "All" ? "All sensors" : sensorTypeRef.current,
              };
            }
          }
          if (!point) return prev;
          const byTimestamp = new Map(prev.map((item) => [item.timestamp_ms, item]));
          byTimestamp.set(point.timestamp_ms, point);
          return [...byTimestamp.values()].sort((a, b) => a.timestamp_ms - b.timestamp_ms).slice(-180);
        });
      }
    });

    events.onerror = () => {
      setError("Live stream disconnected");
      events.close();
    };

    return () => events.close();
  }, [bootstrap, playing, resetToken, sensorType, speed]);

  useEffect(() => {
    if (!selectedSensor) return undefined;
    let cancelled = false;
    fetch(`/api/readings?sensorId=${encodeURIComponent(selectedSensor)}&limit=180`)
      .then((res) => {
        if (!res.ok) throw new Error(`Readings failed: ${res.status}`);
        return res.json();
      })
      .then((data) => {
        if (cancelled) return;
        setChartPoints(
          data.rows.map((row) => ({
            timestamp_ms: row.timestamp_ms,
            value: row.value,
            label: selectedSensor,
          }))
        );
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [selectedSensor]);

  const sensors = bootstrap?.sensors || [];
  const filteredSensors = useMemo(() => {
    if (sensorType === "All") return sensors;
    return sensors.filter((sensor) => sensor.sensor_type === sensorType);
  }, [sensorType, sensors]);

  const visibleSensors = useMemo(() => {
    if (!visibleIds) return filteredSensors;
    return filteredSensors.filter((sensor) => visibleIds.has(sensor.sensor_id));
  }, [filteredSensors, visibleIds]);

  const selectedSensorMeta = useMemo(
    () => sensors.find((sensor) => sensor.sensor_id === selectedSensor) || null,
    [selectedSensor, sensors]
  );

  const mapSensors = useMemo(() => {
    if (selectedSensorMeta) return [selectedSensorMeta];
    return filteredSensors;
  }, [filteredSensors, selectedSensorMeta]);

  const handleReset = useCallback(() => {
    if (!bootstrap) return;
    currentMsRef.current = bootstrap.minTimestamp;
    setCurrentMs(bootstrap.minTimestamp);
    setLatest({});
    setChartPoints([]);
    setLastBatch({ count: 0, truncated: false });
    setResetToken((value) => value + 1);
  }, [bootstrap]);

  const handleSeek = useCallback(
    (nextMs) => {
      if (!bootstrap) return;
      const bounded = Math.min(Math.max(Number(nextMs), bootstrap.minTimestamp), bootstrap.maxTimestamp);
      currentMsRef.current = bounded;
      setCurrentMs(bounded);
      setLatest({});
      setChartPoints([]);
      setLastBatch({ count: 0, truncated: false });
      setResetToken((value) => value + 1);
    },
    [bootstrap]
  );

  if (error) {
    return h("main", { className: "fatal" }, h("h1", null, "Smart City IoT Network Monitor"), h("p", null, error));
  }

  if (!bootstrap) {
    return h(
      "main",
      { className: "loading" },
      h("div", { className: "loader" }),
      h("span", null, "Loading IoT stream")
    );
  }

  return h(
    "div",
    { className: "app-shell" },
    h(TopBar, {
      bootstrap,
      currentMs,
      playing,
      speed,
      sensorType,
      selectedSensor,
      sensors: filteredSensors,
      allSensors: sensors,
      visibleSensors: selectedSensorMeta ? [selectedSensorMeta] : visibleSensors,
      showLabels,
      lastBatch,
      onPlayingChange: setPlaying,
      onReset: handleReset,
      onSeek: handleSeek,
      onShowLabelsChange: setShowLabels,
      onSpeedChange: setSpeed,
      onSensorTypeChange: setSensorType,
      onSelectedSensorChange: setSelectedSensor,
    }),
    h(
      "main",
      { className: "workspace" },
      h(StreetMapPanel, {
        metadata: bootstrap.metadata,
        sensors: mapSensors,
        latest,
        selectedSensor,
        showLabels,
        sensorType,
        onSelectedSensorChange: setSelectedSensor,
        onVisibleIdsChange: setVisibleIds,
      }),
      h(SidePanel, {
        sensors: selectedSensorMeta ? [selectedSensorMeta] : visibleSensors,
        allFilteredSensors: selectedSensorMeta ? [selectedSensorMeta] : filteredSensors,
        latest,
        selectedSensor,
        selectedSensorMeta,
        sensorType,
        onSelectedSensorChange: setSelectedSensor,
      })
    ),
    h(ChartPanel, {
      chartPoints,
      currentMs,
      selectedSensorMeta,
      sensorType,
      lastBatch,
    })
  );
}

function TopBar(props) {
  const sensorTypes = ["All", ...props.bootstrap.sensorTypes.map((item) => item.sensor_type)];
  return h(
    "header",
    { className: "topbar" },
    h(
      "div",
      { className: "brand" },
      h("div", { className: "brand-mark" }, icon(Radio)),
      h(
        "div",
        null,
        h("h1", null, "Smart City IoT Network Monitor"),
        h("span", null, `Smart city IoT monitoring - ${props.allSensors.length} sensors - ${props.visibleSensors.length} in view`)
      )
    ),
    h(
      "div",
      { className: "control-strip" },
      h(
        "button",
        {
          className: "icon-button primary",
          onClick: () => props.onPlayingChange(!props.playing),
          title: props.playing ? "Pause" : "Play",
        },
        icon(props.playing ? Pause : Play)
      ),
      h(
        "button",
        {
          className: "icon-button",
          onClick: props.onReset,
          title: "Reset",
        },
        icon(RotateCcw)
      ),
      h(
        "button",
        {
          className: classNames("icon-button label-toggle", props.showLabels && "active"),
          onClick: () => props.onShowLabelsChange(!props.showLabels),
          title: props.showLabels ? "Hide labels" : "Show labels",
        },
        icon(props.showLabels ? EyeOff : Eye),
        h("span", null, props.showLabels ? "Labels on" : "Labels")
      ),
      h(SelectControl, {
        icon: TimerReset,
        value: String(props.speed),
        onChange: (event) => props.onSpeedChange(Number(event.target.value)),
        options: SPEEDS.map((speed) => ({ value: String(speed.value), label: speed.label })),
        label: "Speed",
      }),
      h(SelectControl, {
        icon: Layers,
        value: props.sensorType,
        onChange: (event) => props.onSensorTypeChange(event.target.value),
        options: sensorTypes.map((type) => ({ value: type, label: type })),
        label: "Type",
      }),
      h(SelectControl, {
        icon: MapPin,
        value: props.selectedSensor,
        onChange: (event) => props.onSelectedSensorChange(event.target.value),
        options: [
          { value: "", label: "All sensors" },
          ...props.sensors.map((sensor) => ({
            value: sensor.sensor_id,
            label: `${sensor.fake_place} · ${sensor.sensor_type}`,
          })),
        ],
        label: "Sensor",
      })
    ),
    h(
      "div",
      { className: "time-stack" },
      h("span", null, "Simulation time"),
      h("strong", null, formatDate(props.currentMs)),
      h(
        "small",
        null,
        `${props.lastBatch.count.toLocaleString()} records${props.lastBatch.truncated ? " - capped" : ""}`
      )
    ),
    h(CelestialIndicator, { currentMs: props.currentMs }),
    h(TimelineControl, {
      minTimestamp: props.bootstrap.minTimestamp,
      maxTimestamp: props.bootstrap.maxTimestamp,
      currentMs: props.currentMs,
      onSeek: props.onSeek,
    })
  );
}

function CelestialIndicator({ currentMs }) {
  const date = new Date(currentMs || Date.now());
  const hour = date.getHours() + date.getMinutes() / 60;
  const sunrise = 6;
  const noon = 12;
  const sunset = 18;
  const isDay = hour >= sunrise && hour < sunset;
  let intensity = 0.18;
  let label = "Moonlight";
  if (isDay) {
    if (hour <= noon) {
      intensity = 0.28 + ((hour - sunrise) / (noon - sunrise)) * 0.72;
      label = hour < 9 ? "Morning sun" : "Rising light";
    } else {
      intensity = 0.28 + ((sunset - hour) / (sunset - noon)) * 0.72;
      label = hour > 16 ? "Late sun" : "Midday sun";
    }
  }
  const percent = Math.round(Math.max(0.12, Math.min(1, intensity)) * 100);
  return h(
    "div",
    { className: classNames("sky-card", isDay ? "day" : "night"), style: { "--sky-intensity": percent / 100 } },
    h("div", { className: "sky-orb-wrap" }, h("span", { className: classNames("sky-orb", isDay ? "sun" : "moon") })),
    h("div", null, h("strong", null, label), h("span", null, `${percent}% light`))
  );
}

function TimelineControl({ minTimestamp, maxTimestamp, currentMs, onSeek }) {
  const [draft, setDraft] = useState(currentMs || minTimestamp);
  const [dragging, setDragging] = useState(false);

  useEffect(() => {
    if (!dragging) setDraft(currentMs || minTimestamp);
  }, [currentMs, dragging, minTimestamp]);

  const commitValue = useCallback((value) => {
    setDragging(false);
    const nextValue = Number(value);
    setDraft(nextValue);
    onSeek(nextValue);
  }, [onSeek]);

  return h(
    "div",
    { className: "timeline-control" },
    h(
      "div",
      { className: "timeline-labels" },
      h("span", null, formatDate(minTimestamp)),
      h("strong", null, formatDate(draft)),
      h("span", null, formatDate(maxTimestamp))
    ),
    h("input", {
      type: "range",
      min: minTimestamp,
      max: maxTimestamp,
      step: 60_000,
      value: Math.min(Math.max(Number(draft), minTimestamp), maxTimestamp),
      onChange: (event) => {
        setDragging(true);
        setDraft(Number(event.target.value));
      },
      onPointerUp: (event) => commitValue(event.currentTarget.value),
      onTouchEnd: (event) => commitValue(event.currentTarget.value),
      onBlur: (event) => commitValue(event.currentTarget.value),
      onKeyUp: (event) => {
        if (event.key === "Enter" || event.key === " ") commitValue(event.currentTarget.value);
      },
    })
  );
}

function SelectControl({ icon: Icon, value, onChange, options, label }) {
  return h(
    "label",
    { className: "select-control" },
    icon(Icon),
    h("span", null, label),
    h(
      "select",
      { value, onChange },
      options.map((option) => h("option", { key: option.value, value: option.value }, option.label))
    )
  );
}

function StreetMapPanel({
  metadata,
  sensors,
  latest,
  selectedSensor,
  showLabels,
  sensorType,
  onSelectedSensorChange,
  onVisibleIdsChange,
}) {
  const mapNodeRef = useRef(null);
  const mapRef = useRef(null);
  const sensorLayerRef = useRef(null);
  const heatLayerRef = useRef(null);
  const heatMemoryRef = useRef(new Map());
  const latestRef = useRef(latest);
  const sensorsRef = useRef(sensors);
  const fitKeyRef = useRef("");

  useEffect(() => {
    latestRef.current = latest;
  }, [latest]);

  useEffect(() => {
    sensorsRef.current = sensors;
  }, [sensors]);

  const publishVisible = useCallback(() => {
    const map = mapRef.current;
    if (!map) return;
    const bounds = map.getBounds();
    const ids = new Set();
    for (const sensor of sensorsRef.current) {
      if (Number.isFinite(sensor.fake_lat) && Number.isFinite(sensor.fake_lng)) {
        if (bounds.contains([sensor.fake_lat, sensor.fake_lng])) ids.add(sensor.sensor_id);
      }
    }
    onVisibleIdsChange(ids);
  }, [onVisibleIdsChange]);

  useEffect(() => {
    const L = window.L;
    if (!mapNodeRef.current || mapRef.current || !L) return undefined;

    const center = [Number(metadata.target_center_lat || -33.8216), Number(metadata.target_center_lng || 151.0451)];
    const map = L.map(mapNodeRef.current, {
      zoomControl: false,
      preferCanvas: true,
      attributionControl: true,
    }).setView(center, 12);

    // OpenStreetMap standard tiles are free and need no API key, unlike the
    // CARTO basemap that was used before. The dark look of the old basemap is
    // reproduced with a CSS filter on the tile pane, see .leaflet-tile-pane in
    // styles.css. Keep the OSM attribution: it is required by their tile policy.
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    }).addTo(map);
    L.control.zoom({ position: "topleft" }).addTo(map);

    sensorLayerRef.current = L.layerGroup().addTo(map);
    heatLayerRef.current = L.layerGroup().addTo(map);
    mapRef.current = map;
    map.on("moveend zoomend", publishVisible);

    setTimeout(() => {
      map.invalidateSize();
      publishVisible();
    }, 120);

    return () => {
      map.remove();
      mapRef.current = null;
    };
  }, [metadata, publishVisible]);

  useEffect(() => {
    const L = window.L;
    const map = mapRef.current;
    const sensorLayer = sensorLayerRef.current;
    const heatLayer = heatLayerRef.current;
    if (!L || !map || !sensorLayer || !heatLayer) return;

    sensorLayer.clearLayers();
    heatLayer.clearLayers();

    const bounds = [];
    const activeSensorIds = new Set();
    const now = Date.now();
    for (const sensor of sensors) {
      const lat = Number(sensor.fake_lat);
      const lng = Number(sensor.fake_lng);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
      activeSensorIds.add(sensor.sensor_id);

      const current = latest[sensor.sensor_id];
      const meta = typeMeta(sensor.sensor_type);
      const selected = selectedSensor === sensor.sensor_id;
      const recent = current && Date.now() - current.receivedAt < 2200;
      const marker = L.circleMarker([lat, lng], {
        radius: selected ? 9 : recent ? 7 : 5.4,
        color: selected ? "#fff7ed" : "rgba(10, 16, 14, 0.9)",
        weight: selected ? 3 : 1.8,
        fillColor: meta.color,
        fillOpacity: selected ? 0.98 : 0.86,
        opacity: 1,
      }).addTo(sensorLayer);

      marker.on("click", () => onSelectedSensorChange(sensor.sensor_id));
      const labelHtml = `<strong>${sensor.fake_place}</strong><br>${sensor.sensor_type}${current ? `<br>${formatValue(current.value)}` : ""}`;
      marker.bindTooltip(
        labelHtml,
        {
          className: showLabels ? "sensor-permanent-label" : "",
          direction: "top",
          opacity: showLabels ? 0.96 : 0.94,
          permanent: showLabels,
          sticky: !showLabels,
        }
      );

      if (current) {
        const heat = getHeatBand(sensor, current.value);
        if (heat) {
          heatMemoryRef.current.set(sensor.sensor_id, {
            lat,
            lng,
            heat,
            expiresAt: now + 60_000,
          });
        }
      }
      bounds.push([lat, lng]);
    }

    for (const [sensorId, hotspot] of heatMemoryRef.current) {
      if (!activeSensorIds.has(sensorId) || hotspot.expiresAt < now) {
        heatMemoryRef.current.delete(sensorId);
        continue;
      }
      L.circle([hotspot.lat, hotspot.lng], {
        radius: 85 + hotspot.heat.intensity * 330,
        stroke: false,
        fillColor: hotspot.heat.color,
        fillOpacity: hotspot.heat.opacity * 0.86,
        interactive: false,
      }).addTo(heatLayer);
    }

    if (bounds.length) {
      const fitKey = `${sensorType}|${sensors.length}`;
      if (fitKeyRef.current !== fitKey) {
        map.invalidateSize();
        if (sensors.length === 1) {
          map.setView(bounds[0], 17, { animate: false });
        } else {
          const nextBounds = getMapFitBounds(L, sensors, sensorType === "All");
          map.fitBounds(nextBounds, { animate: false, padding: [0, 0] });
        }
        if (sensorType === "All" && sensors.length > 1) {
          map.setZoom(Math.min(map.getZoom() + 1, 14), { animate: false });
        }
        fitKeyRef.current = fitKey;
      }
    }

    publishVisible();
  }, [latest, onSelectedSensorChange, publishVisible, selectedSensor, sensorType, sensors, showLabels]);

  return h(
    "section",
    { className: "map-panel street-map-panel" },
    h("div", { ref: mapNodeRef, className: "leaflet-map" }),
    h(
      "div",
      { className: "map-badge" },
      h("strong", null, "NSW relocated view"),
      h("span", null, "Relative spacing preserved - original locations hidden")
    ),
    h(HeatLegend)
  );
}

function getMapFitBounds(L, sensors, focusDenseArea) {
  const points = sensors
    .map((sensor) => [Number(sensor.fake_lat), Number(sensor.fake_lng)])
    .filter(([lat, lng]) => Number.isFinite(lat) && Number.isFinite(lng));
  if (!points.length) return L.latLngBounds([[-33.86, 150.96], [-33.78, 151.13]]);
  if (!focusDenseArea || points.length < 30) return L.latLngBounds(points);

  const lats = points.map(([lat]) => lat).sort((a, b) => a - b);
  const lngs = points.map(([, lng]) => lng).sort((a, b) => a - b);
  const low = 0.06;
  const high = 0.94;
  return L.latLngBounds([
    [quantile(lats, low), quantile(lngs, low)],
    [quantile(lats, high), quantile(lngs, high)],
  ]);
}

function quantile(sortedValues, q) {
  const pos = (sortedValues.length - 1) * q;
  const base = Math.floor(pos);
  const rest = pos - base;
  const next = sortedValues[base + 1];
  if (next === undefined) return sortedValues[base];
  return sortedValues[base] + rest * (next - sortedValues[base]);
}

function getHeatBand(sensor, value) {
  const min = Number(sensor.value_min);
  const max = Number(sensor.value_max);
  const numeric = Number(value);
  if (!Number.isFinite(min) || !Number.isFinite(max) || !Number.isFinite(numeric) || max <= min) return null;
  const ratio = Math.max(0, Math.min(1, (numeric - min) / (max - min)));
  if (ratio >= 0.95) return { label: "Extreme", color: "#ef4444", intensity: ratio, opacity: 0.28 };
  if (ratio >= 0.85) return { label: "High", color: "#f97316", intensity: ratio, opacity: 0.22 };
  if (ratio >= 0.7) return { label: "Elevated", color: "#facc15", intensity: ratio, opacity: 0.16 };
  return null;
}

function HeatLegend() {
  return h(
    "div",
    { className: "heat-legend" },
    h("strong", null, "Heat scale"),
    h("span", null, "Current value vs sensor history - persists 60s"),
    h("div", { className: "heat-bar" }, h("i", null), h("i", null), h("i", null)),
    h(
      "div",
      { className: "heat-steps" },
      h("span", null, "70%"),
      h("span", null, "85%"),
      h("span", null, "95%+")
    )
  );
}

function SidePanel({ sensors, allFilteredSensors, latest, selectedSensor, selectedSensorMeta, sensorType, onSelectedSensorChange }) {
  const [query, setQuery] = useState("");
  const visibleStats = useMemo(() => buildVisibleStats(sensors, latest), [sensors, latest]);
  const legend = useMemo(() => buildLegend(sensors, latest, sensorType), [sensors, latest, sensorType]);
  const visibleSensors = useMemo(() => {
    const needle = query.trim().toLowerCase();
    const source = sensors.length ? sensors : allFilteredSensors;
    if (!needle) return source.slice(0, 80);
    return source
      .filter((sensor) => `${sensor.fake_place} ${sensor.sensor_type} ${sensor.fake_area}`.toLowerCase().includes(needle))
      .slice(0, 80);
  }, [allFilteredSensors, query, sensors]);

  return h(
    "aside",
    { className: "side-panel" },
    h(
      "div",
      { className: "panel-section selected-card" },
      h("div", { className: "section-kicker" }, icon(Gauge), h("span", null, selectedSensorMeta ? "Selected" : "Map View")),
      selectedSensorMeta
        ? h(SensorDetail, { sensor: selectedSensorMeta, current: latest[selectedSensorMeta.sensor_id] })
        : h(MapViewDetail, { stats: visibleStats, sensorType })
    ),
    h(
      "div",
      { className: "panel-section legend-panel" },
      h(
        "div",
        { className: "legend-heading" },
        h("span", null, "Visible Legend"),
        h("strong", null, sensors.length.toLocaleString())
      ),
      h(
        "div",
        { className: "type-grid" },
        legend.map((item) =>
          h(
            "div",
            { key: item.sensor_type, className: "type-chip", style: { "--chip": item.color } },
            h(TypeIcon, { type: item.sensor_type }),
            h("span", null, item.sensor_type),
            h("strong", null, item.sensor_count),
            h("small", null, `${item.live_count} live`)
          )
        )
      )
    ),
    h(
      "div",
      { className: "panel-section roster" },
      h(
        "label",
        { className: "search-box" },
        icon(Search),
        h("input", {
          value: query,
          onChange: (event) => setQuery(event.target.value),
          placeholder: "Search visible sensors",
        })
      ),
      h(
        "div",
        { className: "sensor-list" },
        visibleSensors.map((sensor) =>
          h(
            "button",
            {
              key: sensor.sensor_id,
              className: classNames("sensor-row", selectedSensor === sensor.sensor_id && "active"),
              onClick: () => onSelectedSensorChange(sensor.sensor_id),
            },
            h(TypeIcon, { type: sensor.sensor_type, size: 15 }),
            h("span", { className: "row-main" }, h("strong", null, sensor.fake_place), h("small", null, sensor.sensor_type)),
            h("span", { className: "row-value" }, formatValue(latest[sensor.sensor_id]?.value))
          )
        )
      )
    )
  );
}

function buildVisibleStats(sensors, latest) {
  const values = sensors
    .map((sensor) => latest[sensor.sensor_id]?.value)
    .map(Number)
    .filter(Number.isFinite);
  const live = values.length;
  const min = live ? Math.min(...values) : null;
  const max = live ? Math.max(...values) : null;
  const avg = live ? values.reduce((sum, value) => sum + value, 0) / live : null;
  return {
    sensors: sensors.length,
    live,
    min,
    max,
    avg,
  };
}

function buildLegend(sensors, latest, sensorType) {
  const groups = new Map();
  for (const sensor of sensors) {
    if (sensorType !== "All" && sensor.sensor_type !== sensorType) continue;
    const current = groups.get(sensor.sensor_type) || {
      sensor_type: sensor.sensor_type,
      sensor_count: 0,
      live_count: 0,
      color: typeMeta(sensor.sensor_type).color,
    };
    current.sensor_count += 1;
    if (latest[sensor.sensor_id]) current.live_count += 1;
    groups.set(sensor.sensor_type, current);
  }
  return [...groups.values()].sort((a, b) => b.sensor_count - a.sensor_count);
}

function MapViewDetail({ stats, sensorType }) {
  return h(
    "div",
    { className: "map-view-detail" },
    h("h2", null, sensorType === "All" ? "Current map view" : sensorType),
    h("div", { className: "detail-type" }, "Visible sensors"),
    h(
      "div",
      { className: "summary-grid" },
      h("span", null, "Sensors"),
      h("strong", null, stats.sensors.toLocaleString()),
      h("span", null, "Live now"),
      h("strong", null, stats.live.toLocaleString()),
      h("span", null, "Current average"),
      h("strong", null, formatValue(stats.avg)),
      h("span", null, "Range"),
      h("strong", null, `${formatValue(stats.min)} - ${formatValue(stats.max)}`)
    )
  );
}

function SensorDetail({ sensor, current }) {
  return h(
    "div",
    { className: "sensor-detail" },
    h("h2", null, sensor.fake_place),
    h("div", { className: "detail-type" }, h(TypeIcon, { type: sensor.sensor_type, size: 14 }), sensor.sensor_type),
    h(
      "div",
      { className: "detail-value" },
      h("strong", null, formatValue(current?.value)),
      h("span", null, current ? formatDate(current.timestamp_ms) : "No reading yet")
    ),
    h(
      "div",
      { className: "detail-grid" },
      h("span", null, "Area"),
      h("strong", null, sensor.fake_area),
      h("span", null, "Records"),
      h("strong", null, Number(sensor.reading_count).toLocaleString()),
      h("span", null, "Range"),
      h("strong", null, `${formatValue(sensor.value_min)} - ${formatValue(sensor.value_max)}`)
    )
  );
}

function ChartPanel({ chartPoints, currentMs, selectedSensorMeta, sensorType, lastBatch }) {
  const meta = selectedSensorMeta ? typeMeta(selectedSensorMeta.sensor_type) : sensorType === "All" ? { color: "#d9f99d" } : typeMeta(sensorType);
  const title = selectedSensorMeta
    ? selectedSensorMeta.fake_place
    : sensorType === "All"
      ? "All Sensors Live Average"
      : `${sensorType} Live Average`;
  const mode = selectedSensorMeta ? "Selected Sensor Curve" : "Live Rolling Curve";

  return h(
    "section",
    { className: "chart-panel" },
    h(
      "div",
      { className: "chart-heading" },
      h("div", null, h("span", null, mode), h("strong", null, title)),
      h(
        "div",
        { className: "chart-stats" },
        h("span", null, formatDate(currentMs)),
        h("span", null, `${lastBatch.count.toLocaleString()} records`)
      )
    ),
    h(LineChart, { points: chartPoints, color: meta.color, emptyLabel: "Waiting for replay data" })
  );
}

function LineChart({ points, color, emptyLabel }) {
  const width = 1200;
  const height = 172;
  const pad = 26;
  const values = points.map((point) => Number(point.value)).filter(Number.isFinite);
  const min = values.length ? Math.min(...values) : 0;
  const max = values.length ? Math.max(...values) : 1;
  const span = Math.max(max - min, 1);
  const path = points
    .map((point, index) => {
      const x = pad + (index / Math.max(points.length - 1, 1)) * (width - pad * 2);
      const y = height - pad - ((Number(point.value) - min) / span) * (height - pad * 2);
      return `${index === 0 ? "M" : "L"} ${x.toFixed(2)} ${y.toFixed(2)}`;
    })
    .join(" ");
  const latest = points[points.length - 1];

  return h(
    "div",
    { className: "chart-wrap" },
    h(
      "svg",
      { viewBox: `0 0 ${width} ${height}`, className: "line-chart", role: "img" },
      h(
        "defs",
        null,
        h(
          "linearGradient",
          { id: "chartFill", x1: "0", x2: "0", y1: "0", y2: "1" },
          h("stop", { offset: "0%", stopColor: color, stopOpacity: "0.26" }),
          h("stop", { offset: "100%", stopColor: color, stopOpacity: "0.02" })
        )
      ),
      h("line", { x1: pad, y1: pad, x2: pad, y2: height - pad, className: "axis" }),
      h("line", { x1: pad, y1: height - pad, x2: width - pad, y2: height - pad, className: "axis" }),
      !points.length &&
        h("text", { x: width / 2, y: height / 2 + 6, className: "chart-empty", textAnchor: "middle" }, emptyLabel),
      points.length > 1 &&
        h("path", {
          d: `${path} L ${width - pad} ${height - pad} L ${pad} ${height - pad} Z`,
          fill: "url(#chartFill)",
        }),
      points.length > 1 && h("path", { d: path, fill: "none", stroke: color, strokeWidth: 3.2, strokeLinecap: "round" }),
      latest &&
        h("circle", {
          cx: pad + ((points.length - 1) / Math.max(points.length - 1, 1)) * (width - pad * 2),
          cy: height - pad - ((Number(latest.value) - min) / span) * (height - pad * 2),
          r: 5.5,
          fill: color,
        }),
      h("text", { x: width - pad, y: 22, className: "chart-label", textAnchor: "end" }, formatValue(max)),
      h("text", { x: width - pad, y: height - 8, className: "chart-label", textAnchor: "end" }, formatValue(min))
    )
  );
}

createRoot(document.getElementById("root")).render(h(App));
