# Smart City IoT Network Monitor

Local React + Node.js + SQLite project for replaying dummy IoT sensor readings on a fake street map.

## License

Copyright (C) 2026 Dr Shuo Ding <shuoding@outlook.com>

This project is licensed under the GNU Affero General Public License version 3 or later (AGPL-3.0-or-later). See `LICENSE` for the full license text.

## Test Data And Scenario Notice

All scenario information, map placement, sensor identifiers, place names, areas, coordinates, readings, and related display data used by this project are fake, synthetic, anonymized, or relocated for testing only.

These data are not real operational, municipal, infrastructure, or sensor records. They are provided only to test the software. They are not part of the licensed program code, must not be treated as factual, must not be redistributed, and must not be used for any other purpose.

The author accepts no responsibility or liability for any consequence arising from anyone interpreting, relying on, distributing, or otherwise using the scenario, map, sensor, or reading data as real data.

## Windows Entry Point

From PowerShell or Command Prompt, run the Windows launcher from the project directory:

```text
start_site.bat
```

The first run imports the default test input path `D:\iotdataback\IoTData\dataall` into `data\smart_city_iot.sqlite`, then starts the app.

Open:

```text
http://localhost:5177
```

Advanced Windows options can be passed through the `.bat` file:

```cmd
start_site.bat -Reimport
start_site.bat -Input "D:\iotdataback\IoTData\dataall\banyule.xlsx" -Reimport
start_site.bat -Port 8080
```

`run.ps1` is an internal helper used by `start_site.bat`; do not use it as the normal Windows entry point unless you are debugging the launcher.

## Ubuntu Entry Point

From a terminal in the project directory, make the launcher executable and provide a CSV/XLSX test input file or directory:

```bash
chmod +x run_ubuntu.sh
./run_ubuntu.sh --input /path/to/all.csv
```

The Ubuntu script installs:

- Node.js 24, required for Node's built-in `node:sqlite`
- `python3`, `python3-venv`, `python3-pip`
- Python packages `pandas` and `openpyxl`
- `sqlite3`

Useful options:

```bash
./run_ubuntu.sh --input /path/to/all.csv --reimport
./run_ubuntu.sh --input /path/to/data-directory --port 8080
IOT_INPUT=/path/to/all.csv PORT=5177 ./run_ubuntu.sh
```

If dependencies are already installed, use:

```bash
./run_ubuntu.sh --input /path/to/all.csv --skip-install
```

## Project Shape

- `scripts/import_iot_to_sqlite.py` reads CSV/XLSX files, anonymizes sensor/place/location data, relocates sensors to fake NSW coordinates, and writes SQLite.
- `server/server.mjs` serves the React app, metadata APIs, and a Server-Sent Events playback stream.
- `public/src/app.js` contains the React UI.
- `public/src/styles.css` contains the dashboard and synthetic map styling.

The SQLite database stores anonymized sensor ids, fake place names, fake NSW coordinates, normalized sensor types, and ordered readings for testing. It does not store the source address or source latitude/longitude.

The chart is sensor-only: select a marker or sensor row to show that sensor's historical curve. The heat overlay uses each sensor's current value relative to its own historical min/max range and keeps high-value events visible briefly so they are easier to inspect.
