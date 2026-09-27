# External Dependency Status

| Feature | Status | External requirement |
| --- | --- | --- |
| Background location | Implemented adapter, runtime unverified | Android SDK/device, foreground-service approval, runtime permissions |
| Push notifications | Firebase Messaging adapter implemented, delivery unverified | Firebase project, `google-services.json`, Firebase credentials, Android channel configuration |
| Voice navigation | Flutter TTS adapter implemented | Device TTS engine and supported locale |
| Live weather | OpenWeather adapter implemented | `WEATHER_API_KEY` in backend `.env`; unavailable when not configured |
| Live traffic | Configurable HTTP traffic adapter implemented | `TRAFFIC_API_URL` and `TRAFFIC_API_KEY`; provider response must match road IDs |
| Persistent incidents/facilities | SQLAlchemy repositories and Alembic migration implemented | PostgreSQL/PostGIS for generated point geometry and spatial indexes |
| Scientific prediction | Advisory interface only | Real historical labeled dataset, training pipeline, validation metrics, model artifact |
| AI image classification | Not claimed as implemented | Trained model or external vision provider, preprocessing contract, credentials |
| Android runtime validation | Blocked in current shell | `flutter doctor` must find Android SDK and an emulator/device |

The application does not label unavailable weather or traffic as live. Firebase initialization and notification delivery fail closed when platform configuration is absent.

## Firebase setup

1. Create a Firebase Android app matching the Flutter application ID.
2. Add `google-services.json` under `mobile/android/app/` without committing secrets.
3. Run `flutterfire configure` or add the generated Firebase options for all target platforms.
4. Grant notification permission on Android 13+.
5. Configure the backend push sender separately. This repository currently registers device tokens but does not contain a server credential or send loop.

## Android background location

The manifest declares fine/coarse/background location and foreground-service permissions. Runtime testing must verify user-granted "Allow all the time" permission, the foreground notification, app minimization, process restart behavior, battery policy, and OS termination behavior. The code intentionally does not claim those checks passed until an emulator/device is visible to Flutter.
