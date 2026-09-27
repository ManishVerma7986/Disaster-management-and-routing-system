# SafeRoute Dependencies and Run Guide

SafeRoute is a disaster-aware routing application composed of a FastAPI backend and a Flutter client. The default local setup uses SQLite. PostgreSQL/PostGIS, Firebase, weather APIs, and traffic APIs are optional provider integrations.

## Project layout

- `backend/`: FastAPI API, SQLAlchemy storage, Alembic migrations, and pytest tests.
- `mobile/`: Flutter Material 3 client for Android, Windows, and web.
- `database/schema.sql`: optional PostGIS bootstrap schema.
- `docker-compose.yml`: optional PostgreSQL/PostGIS service.
- `docs/`: architecture and operational documentation.

## Required tools

| Tool | Version or source | Purpose |
| --- | --- | --- |
| Python | 3.11 or newer | Backend runtime and tests |
| `venv` and `pip` | Included with Python | Isolated Python dependencies |
| Flutter SDK | Dart SDK 3.5 or newer | Mobile, Windows, and web client |
| Android Studio and Android SDK | Android development only | Android emulator/device builds |
| JDK | 17 | Android Gradle and Kotlin builds |
| Docker Desktop | Optional | PostgreSQL/PostGIS container |

Run `flutter doctor` after installing Flutter. For Android, also create an emulator or connect a device and accept the Android SDK licenses.

## Backend libraries

Install the pinned versions from `backend/requirements.txt`:

| Library | Purpose |
| --- | --- |
| FastAPI | REST API framework and OpenAPI documentation |
| Uvicorn | ASGI development server |
| Pydantic Settings | Request validation and `.env` configuration |
| SQLAlchemy | ORM and SQLite/PostgreSQL persistence |
| Alembic | Database migrations |
| `psycopg[binary]` | PostgreSQL driver |
| PyJWT | JWT access tokens |
| `pwdlib[argon2]` | Password hashing |
| HTTPX | External HTTP calls and FastAPI test client support |
| pytest | Backend test runner |

## Flutter libraries

The exact Flutter package versions are resolved by `mobile/pubspec.lock`. Direct application dependencies in `mobile/pubspec.yaml` are:

| Package | Purpose |
| --- | --- |
| Flutter Material 3 | Application UI |
| `http` | Backend HTTP requests |
| `flutter_map` and `latlong2` | OpenStreetMap route map rendering |
| `geolocator` | Foreground location access |
| `shared_preferences` | Tokens and cached route data |
| `flutter_tts` | Voice navigation output |
| `firebase_core` and `firebase_messaging` | Optional Firebase push notifications |
| `flutter_background_service` | Optional background location service |
| `cupertino_icons` | Cupertino icons |
| `flutter_lints` | Dart/Flutter lint rules |

The Android build also uses Gradle, Android Gradle Plugin `8.11.1`, Kotlin `2.2.20`, and Google Services plugin `4.4.2`, as configured in `mobile/android/settings.gradle.kts`.

## Backend setup with SQLite

From the repository root in PowerShell:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r backend\requirements.txt

Set-Location backend
python -m alembic upgrade head
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

The API is available at `http://127.0.0.1:8000`. Interactive documentation is at `http://127.0.0.1:8000/docs`. When started from `backend`, SQLite is stored at `backend/disaster_routing.db`.

Users register through the application. Authority accounts are created by an existing authority/admin.

## Flutter setup and run

In a second terminal:

```powershell
Set-Location mobile
flutter pub get
flutter run
```

The client chooses the backend URL by platform:

- Android emulator: `http://10.0.2.2:8000`
- Windows and web: `http://127.0.0.1:8000`
- Physical phone: pass the computer LAN address and keep both devices on the same network.

Example for a physical phone:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.42:8000
```

Replace `192.168.1.42` with the host computer's LAN address. The URL must be reachable from the selected device.

## Optional PostgreSQL/PostGIS

Docker Desktop can start the included PostGIS service:

```powershell
docker compose up -d postgres
Set-Location backend
$env:DATABASE_URL = 'postgresql+psycopg://postgres:postgres@127.0.0.1:5432/disaster_routing'
python -m alembic upgrade head
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

For persistent settings, create `backend/.env` and configure values such as:

```dotenv
DATABASE_URL=postgresql+psycopg://postgres:postgres@127.0.0.1:5432/disaster_routing
JWT_SECRET=replace-this-in-development
WEATHER_API_KEY=
TRAFFIC_API_URL=
TRAFFIC_API_KEY=
```

Do not commit `.env` files or production secrets. Use Alembic for the application schema. `database/schema.sql` is an alternative PostGIS bootstrap schema, not a command that must be run in addition to Alembic.

## Optional integrations

- Firebase notifications require a Firebase project, an Android application with ID `com.example.disaster_routing_mobile`, and a valid `mobile/android/app/google-services.json`.
- OpenWeather requires `WEATHER_API_KEY`; without it, weather is unavailable.
- Live traffic requires both `TRAFFIC_API_URL` and `TRAFFIC_API_KEY` in the provider format expected by the routing service.
- Route maps use OpenStreetMap tiles and require network access and compliance with the OpenStreetMap tile usage policy.
- Destination suggestions use the backend Geoapify adapter and require network access when `GEOAPIFY_API_KEY` is configured. Requests are debounced in Flutter and provider failures are shown as an unavailable-search state.
- Optional provider adapters use Geoapify for search/reverse geocoding and Geoapify's OSM-derived tiles, and GraphHopper for coordinate routing. Configure their keys in `backend/.env` from [backend/.env.example](../backend/.env.example); keys are never embedded in Flutter source. The Flutter tile key is only needed when launching with `--dart-define=GEOAPIFY_API_KEY=...`.
- The current map provider remains `flutter_map` with OpenStreetMap tiles. Google Maps is not enabled because this repository does not contain a restricted Google Maps key or a configured Google Routes/Places backend. Enabling it requires a real restricted key, Android package/SHA-1 restrictions, billing, and the appropriate Google APIs; do not add an unrestricted key to source control.

### Geoapify and GraphHopper

1. Create Geoapify and GraphHopper accounts and obtain API keys.
2. Copy `backend/.env.example` to `backend/.env`.
3. Set `GEOAPIFY_API_KEY` and `GRAPHHOPPER_API_KEY` in `backend/.env`.
4. Start the backend. The Flutter search field calls `/places/search` and map picker calls `/places/reverse`; coordinate routes using `DRIVING`, `WALKING`, or `CYCLING` use GraphHopper.
5. To use Geoapify tiles in the client, launch Flutter with a restricted tile key:

```powershell
flutter run --dart-define=GEOAPIFY_API_KEY=your_restricted_geoapify_key
```

The tile key is a client-side publishable credential and must be restricted in the provider dashboard. The GraphHopper key remains backend-only. Without these keys, the app keeps its local graph and seeded-data behavior and clearly reports online provider unavailability.

## Implemented mobile workflows and limits

- Foreground journey tracking uses real `geolocator` GPS updates, off-route detection, a live position marker, and explicit Start Journey/End Journey controls.
- Saved offline routes persist route geometry and metadata locally. They do not claim to download arbitrary OpenStreetMap tiles; map tiles still require network access unless a supported tile cache is added.
- Map-selected destinations are sent as coordinates and resolved by the backend to the nearest configured road-graph node. The local graph is not a global turn-by-turn provider.
- Normal user registration is public. Administrator registration is intentionally not self-service; authority/admin provisioning must remain a protected backend operation.
- Background location service scaffolding exists, but foreground journey tracking is the validated workflow. Android background tracking still requires device-level permission review and testing on a real emulator/device.

## Validation commands

Backend, from the repository root:

```powershell
.\.venv\Scripts\python.exe -m pytest backend\tests -q
.\.venv\Scripts\python.exe -m compileall -q backend\app backend\tests
```

Flutter, from `mobile`:

```powershell
flutter analyze
flutter test
```

The current repository validation results are:

- Backend: 29 tests passed in the last fully captured run; API smoke coverage is included in the test suite.
- Flutter: analysis completed with no issues.
- Flutter: all tests passed.
- Python bytecode compilation completed successfully.
- Flutter Windows, web, and Android release builds completed successfully.

## Common problems

- `flutter.sdk not set in local.properties`: run Flutter tooling from `mobile` and ensure `mobile/android/local.properties` points to the Flutter SDK.
- Android cannot reach the API: use `10.0.2.2` from an Android emulator, or pass `API_BASE_URL` for a physical device.
- `Connection refused` on `10.0.2.2:8000`: the backend is stopped or is using another port. Keep the Uvicorn terminal running, open `http://127.0.0.1:8000/health` on the host, and only then start the Flutter app. If the API uses another port, pass the matching URL with `--dart-define=API_BASE_URL=http://10.0.2.2:PORT`.
- Firebase initialization fails: install the correct `google-services.json` for your own Firebase project, or treat push notifications as optional.
- Migration connection errors: verify `DATABASE_URL`, start PostgreSQL if using it, and run `python -m alembic upgrade head` from `backend`.
- PowerShell blocks activation: run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` once, or invoke `.venv\Scripts\python.exe` directly without activating the environment.
