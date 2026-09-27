# SafeRoute setup and run guide

SafeRoute has a Python/FastAPI backend and a Flutter client. The default local setup uses SQLite and works without Docker or PostgreSQL. Provider-backed weather, traffic, facilities, and risk data require configured API credentials.

## Required tools

Install these once:

| Tool | Required version | Used for |
| --- | --- | --- |
| Python | 3.11 or later | FastAPI backend and tests |
| pip and `venv` | bundled with Python | Backend package installation and isolation |
| Flutter SDK | Dart 3.5 or later | Mobile, web, and Windows client |
| Android Studio + Android SDK | Android builds only | Emulator/device deployment |
| JDK | 17 | Android Gradle builds |

Run `flutter doctor` after installing Flutter. It reports any missing Android SDK or emulator configuration.

## Backend libraries and frameworks

Install the exact Python packages in [backend/requirements.txt](../backend/requirements.txt):

| Package | Purpose |
| --- | --- |
| FastAPI and Uvicorn | HTTP API and local server |
| Pydantic Settings | Request validation and `.env` configuration |
| SQLAlchemy and Alembic | SQLite/PostgreSQL persistence and schema migrations |
| psycopg | PostgreSQL driver |
| PyJWT and pwdlib[argon2] | Bearer-token authentication and password hashing |
| httpx | Weather/traffic provider calls and HTTP test client |
| pytest | Backend test runner |

## Flutter libraries and frameworks

Run `flutter pub get` in `mobile`; it installs the packages pinned in [mobile/pubspec.lock](../mobile/pubspec.lock). Direct application dependencies are Flutter Material 3, `http`, `flutter_map`, `latlong2`, `geolocator`, `shared_preferences`, `flutter_tts`, `firebase_core`, `firebase_messaging`, and `flutter_background_service`.

The Android project uses Gradle, the Android Gradle Plugin, Kotlin, and Google Services. Their configured versions are in `mobile/android/` and are resolved by the Flutter tool.

## Run locally with SQLite

From the repository root in PowerShell:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r backend\requirements.txt

Set-Location backend
python -m alembic upgrade head
python -m uvicorn app.main:app --reload
```

Open <http://127.0.0.1:8000/docs> to use the API. The SQLite database is created at `backend/disaster_routing.db` when these commands are run from the `backend` directory.

In a second terminal:

```powershell
Set-Location mobile
flutter pub get
flutter run
```

For an Android emulator, the client defaults to `http://10.0.2.2:8000`. For Windows or a web browser it defaults to `http://127.0.0.1:8000`. For a physical phone, pass the computer's LAN address explicitly (the phone and computer must be on the same network):

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.42:8000
```

Replace the example IP address with the host computer's actual LAN IP. The app removes a trailing slash from this setting automatically.

For a physical Android device using USB debugging, the equivalent workflow is:

```powershell
adb devices
adb reverse tcp:8000 tcp:8000
flutter devices
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

The Android manifest permits cleartext HTTP only in debug builds. Release builds require an HTTPS API URL; set it with `--dart-define=API_BASE_URL=https://api.example.com`.

Register a user through the application or `/auth/register`. Authority accounts are created by an existing authority/admin through `/auth/create-admin`.

The offline cache synchronization endpoint is `POST /sync` and requires the logged-in user's bearer token. It returns roads, active closures, incidents, facilities, nearby-warning data, and the user's reports for local caching.

## Optional PostgreSQL/PostGIS setup

Docker Desktop is the easiest way to start the included PostGIS service:

```powershell
docker compose up -d postgres
Set-Location backend
$env:DATABASE_URL = 'postgresql+psycopg://postgres:postgres@127.0.0.1:5432/disaster_routing'
python -m alembic upgrade head
python -m uvicorn app.main:app --reload
```

For persistent configuration, create `backend/.env` with `DATABASE_URL`, `JWT_SECRET`, `WEATHER_API_KEY`, and/or `TRAFFIC_API_URL` plus `TRAFFIC_API_KEY`. Do not commit this file. `database/schema.sql` is an alternative PostGIS bootstrap schema; normally use Alembic for a new database, not both as independent initializers.

Production configuration must set `ENVIRONMENT=production`, a generated `JWT_SECRET`, an HTTPS `DATABASE_URL`, explicit `CORS_ORIGINS`, and provider keys through the deployment secret store. Do not use the development JWT secret, wildcard CORS, cleartext API URLs, or debug signing for a production release.

## Optional service configuration

- Firebase Cloud Messaging: create your own Firebase Android application with ID `com.example.disaster_routing_mobile`, then place its `google-services.json` at `mobile/android/app/google-services.json`. It is ignored by Git. Configure every target platform with `flutterfire configure` before relying on notifications.
- OpenWeather: set `WEATHER_API_KEY` in `backend/.env`. Without it, weather is unavailable.
- Traffic provider: set `TRAFFIC_API_URL` and `TRAFFIC_API_KEY`. The provider must return data keyed by SafeRoute road IDs.
- OpenStreetMap tiles: the route map needs network access and must follow the OpenStreetMap tile usage policy in deployed applications.

## Validate the project

```powershell
.\.venv\Scripts\python.exe -m pytest backend\tests -q
Set-Location mobile
flutter analyze
flutter test
```

Run the backend test command from the repository root. Run the Flutter commands from `mobile` after `flutter pub get`.
