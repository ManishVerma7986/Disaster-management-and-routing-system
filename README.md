# SafeRoute: Real-Time Disaster-Aware Emergency Routing

A disaster-aware routing application that prefers the safest practical route instead of blindly choosing the shortest one. The runnable slice includes FastAPI, JWT roles, a configured local road graph, risk-aware alternatives, explainable route responses, authority closures, user reports, audit entries, and a Flutter Material 3 client with authentication, GPS handling, OSM route maps, cached routes, offline status, and hazard reporting.

## Architecture

`Flutter mobile client -> FastAPI -> routing service -> PostgreSQL/PostGIS or SQLite`

OpenStreetMap is treated as base map/road data only. Weather, traffic, facilities, and incidents are returned only from configured providers or persisted authority/user data.

## One click run bat file

Make the necessary changes to run_project.bat file like add coorect file locations as per your system.
```
set "PROJECT=A:\PYTHON PROJECT\ruthwik disaster management project"
set "BACKEND=A:\PYTHON PROJECT\ruthwik disaster management project\backend"
set "MOBILE=A:\PYTHON PROJECT\ruthwik disaster management project\mobile"

REM Confirmed virtual environment location
set "VENV=A:\PYTHON PROJECT\ruthwik disaster management project\.venv"

set "PYTHON=A:\PYTHON PROJECT\ruthwik disaster management project\.venv\Scripts\python.exe"
set "PIP=A:\PYTHON PROJECT\ruthwik disaster management project\.venv\Scripts\pip.exe"
set "ALEMBIC=A:\PYTHON PROJECT\ruthwik disaster management project\.venv\Scripts\alembic.exe"

set "FLUTTER=C:\flutter\flutter\bin\flutter.bat"
set "ADB=C:\flutter\flutter\bin\platform-tools\adb.exe"

set "DB_NAME=disaster_routing"
set "DB_USER=postgres"
set "DB_HOST=localhost"
set "DB_PORT=5432"

set "BACKEND_URL=http://127.0.0.1:8000"
set "HEALTH_URL=http://127.0.0.1:8000/health"
```
Also change this command as per your directary
```
start "DISASTER MANAGEMENT - FASTAPI" cmd /k "cd /d "%PROJECT%" && "%PYTHON%" -m uvicorn backend.app.main:app --host 0.0.0.0 --port 8000 --reload"
```

## Run the backend

```powershell
cd backend
& "C:/Program Files/Python314/python.exe" -m pip install -r requirements.txt
& "C:/Program Files/Python314/python.exe" -m uvicorn app.main:app --reload
```

Open `http://127.0.0.1:8000/docs` for the interactive API documentation.

Register an account through the application or `/auth/register`. Authority accounts must be provisioned by an existing authority/admin. The API persists roads, closures, reports, and audit logs through SQLAlchemy. Local runs default to SQLite at `backend/disaster_routing.db`; set `DATABASE_URL` in `backend/.env` to use PostgreSQL/PostGIS. Optional Geoapify search/reverse geocoding and GraphHopper coordinate routing are configured through `backend/.env.example`; missing provider keys are reported as unavailable rather than replaced with fabricated data. `database/schema.sql` contains the PostGIS schema for deployment, and migrations are managed with Alembic:

```powershell
cd backend
alembic upgrade head
```

## Run the Flutter client

```powershell
choco install flutter --version=3.41.9 -y
winget install --id Google.AndroidStudio --source winget
flutter doctor
cd mobile
flutter pub get
flutter run
```

Android emulator requests use `http://10.0.2.2:8000`. For a physical device, pass `--dart-define=API_BASE_URL=http://HOST_LAN_IP:8000`. Geoapify tile rendering can be enabled with a restricted client key using `--dart-define=GEOAPIFY_API_KEY=...`; GraphHopper keys remain backend-only.

Flutter analysis, tests, Android release build, Windows release build, and web release build have been validated locally. Physical Android runtime, emulator launch, background location, and hot restart require a connected device or emulator and are not claimed by this audit.

## Incident and closure workflow

1. Start the API and open the Flutter app.
2. Allow location access and request a route.
3. An authority can create or deactivate incidents and road closures.
4. Connected users receive incident changes in realtime.

## What is next

Persistent users, authority report review, route alternatives, temporal closures, local cached-graph routing, optional Geoapify/GraphHopper providers, GPS handling, OSM map rendering, destination search, map picking, hazard reporting, emergency facilities/SOS, incident grouping, realtime incident updates, advisory risk scoring, and Alembic migrations are implemented. Background location, push delivery, geofencing, and validated predictive/AI models still require additional platform/provider work.

## Advanced feature boundaries

- Weather, traffic, and predictive risk use replaceable provider interfaces. Provider failures are surfaced to the client and predictive risk is advisory only.
- Incident grouping uses a one-kilometre proximity rule and is currently process-backed; production deployments should move incidents into the PostGIS repository.
- Offline routing uses the last synchronized road graph and Dijkstra-style local search. It reports cached-data status and never presents the result as live.
- Foreground GPS monitoring emits off-route and route-progress events. Android background tracking and push delivery require platform/provider validation; voice output is supported when a device TTS engine is available.
- `database/schema.sql` contains PostGIS facility/weather geometry tables; run `alembic upgrade head` before deploying schema changes.

## Safety and limitations

This system cannot guarantee physical road safety. Authority-verified data must control official closures. Offline cached values can become stale, user reports are unverified until reviewed, and risk weights are configurable assumptions rather than scientific predictions.
