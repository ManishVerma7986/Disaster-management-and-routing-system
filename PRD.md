# Product Requirements Document (PRD)

## Disaster Aware Routing & Emergency Management System

**Version:** 1.0
**Platform:** Android Mobile + FastAPI Backend
**Frontend:** Flutter
**Backend:** FastAPI / Python
**Database:** PostgreSQL / SQLite for local development
**Maps & Geocoding:** Geoapify
**Routing:** Local cached graph + GraphHopper
**Authentication:** JWT
**Project Type:** College / Academic + Prototype Disaster Management System

---

# 1. Product Overview

## 1.1 Product Name

**Disaster Aware Routing & Emergency Management System**

## 1.2 Product Vision

The Disaster Aware Routing System is a mobile-first emergency-management platform designed to help users **navigate safely during disasters and emergencies**.

Unlike conventional navigation applications that primarily optimize for distance or travel time, this system considers disaster-related information such as:

* Flood risk
* Landslide risk
* Road closures
* Reported incidents
* Weather conditions
* Traffic conditions
* Emergency facilities
* Safe shelters
* Route safety
* Emergency SOS requirements

The application combines a **Flutter mobile application** with a **FastAPI backend** to provide users with disaster-aware routing, emergency reporting, risk information, and safety services.

---

# 2. Problem Statement

During disasters such as floods, landslides, cyclones, earthquakes, and severe weather events, normal navigation systems may not provide sufficient information about road safety.

A road that is geographically the shortest route may be:

* Flooded
* Blocked
* Damaged
* Affected by landslides
* Near an active disaster incident
* Unsafe for emergency travel

Users therefore need a navigation system that considers both **transportation efficiency and disaster risk**.

### Current problems

1. Conventional navigation focuses mainly on distance and travel time.
2. Disaster-related road information may not be integrated into navigation.
3. Emergency reports may be scattered across different sources.
4. Users may not know the nearest safe facility or shelter.
5. Internet connectivity may become unreliable during disasters.
6. Emergency responders need structured incident information.
7. Users need a simple mechanism to report hazards.
8. The system should maintain an audit trail for important emergency operations.

---

# 3. Product Goals

The primary goals are:

### G1 — Disaster-aware navigation

Provide routes that consider disaster-related risk rather than only distance.

### G2 — Emergency information

Provide users with relevant disaster warnings, incidents, weather, and traffic information.

### G3 — Safe destination discovery

Help users locate:

* Hospitals
* Police stations
* Fire stations
* Emergency centers
* Shelters
* Other safe facilities

### G4 — Community reporting

Allow users to report:

* Floods
* Blocked roads
* Landslides
* Accidents
* Infrastructure damage
* Other hazards

### G5 — Emergency SOS

Provide an emergency mechanism allowing users to initiate an SOS request.

### G6 — Offline resilience

Maintain locally cached routing and synchronization data so core functionality can continue when connectivity is limited.

### G7 — Administrative management

Allow authorized administrators to manage:

* Roads
* Closures
* Incidents
* Reports
* Facilities
* Warnings
* Users
* Verification workflows

---

# 4. Product Scope

## 4.1 In Scope

### Mobile application

* User registration
* User login
* JWT authentication
* Current-location detection
* Destination search
* Disaster-aware route calculation
* Route alternatives
* Risk information
* Road closure information
* Emergency facilities
* Safe shelters
* Incident reporting
* Report verification
* Weather information
* Traffic information
* Risk prediction
* SOS
* Nearby warnings
* Offline cached data
* Synchronization

### Backend

* REST APIs
* Authentication
* Route calculation
* Road graph management
* Incident management
* Report management
* Facility management
* Weather integration
* Traffic integration
* Geocoding
* Risk prediction
* Synchronization
* Audit logging
* Emergency management

---

# 5. Out of Scope

The initial version will not attempt to provide:

* Real-world emergency dispatch
* Direct communication with government emergency systems
* Guaranteed rescue services
* Fully autonomous emergency vehicle control
* Guaranteed real-time disaster predictions
* Satellite-based disaster detection
* Professional-grade emergency command-center replacement
* Guaranteed operation without any network connectivity

The system is a **decision-support and navigation platform**, not a replacement for official emergency services.

---

# 6. Target Users

## 6.1 General Users

People travelling through disaster-affected or potentially hazardous areas.

### Needs

* Safe route
* Current risk information
* Nearby shelter
* Emergency facilities
* Warnings
* SOS
* Simple reporting

---

## 6.2 Emergency Responders

Emergency personnel who need information about:

* Road closures
* Incidents
* Safe routes
* Facilities
* Disaster locations

---

## 6.3 Administrators

System administrators responsible for:

* Managing road information
* Verifying reports
* Managing incidents
* Managing facilities
* Managing closures
* Monitoring system activity

---

## 6.4 Local Authorities

Potential future users who may use the system for:

* Disaster monitoring
* Road management
* Emergency coordination
* Warning dissemination

---

# 7. User Personas

## Persona 1 — Normal Traveller

**Goal:** Reach a destination safely.

Needs:

> "I don't just want the fastest route. I want to know whether the route is affected by a flood or road closure."

---

## Persona 2 — Disaster-Affected User

**Goal:** Escape an affected area.

Needs:

> "I need to find the nearest safe route and shelter quickly."

---

## Persona 3 — Emergency Responder

**Goal:** Reach an incident.

Needs:

> "I need route information that considers blocked roads."

---

## Persona 4 — Administrator

**Goal:** Maintain reliable disaster information.

Needs:

> "I need to verify reports and update road closures."

---

# 8. Functional Requirements

# FR-01 — User Registration

The application shall allow users to create an account.

### Input

* Name
* Email
* Password
* Optional profile information

### System behavior

1. Validate input.
2. Check whether the email already exists.
3. Hash password.
4. Create user.
5. Return successful registration response.

### Acceptance Criteria

* Invalid email is rejected.
* Duplicate account is rejected.
* Password is never stored in plaintext.
* Successful registration creates a user record.

---

# FR-02 — User Authentication

Users shall be able to log in.

### Process

```text
User
 ↓
Email + Password
 ↓
FastAPI
 ↓
Validate credentials
 ↓
Generate JWT
 ↓
Flutter stores token
```

### Acceptance Criteria

* Valid credentials return JWT.
* Invalid credentials return an authentication error.
* Protected APIs reject missing/invalid tokens.

---

# FR-03 — Current Location

The application shall obtain the user's current location using the device's GPS/location services.

### Location data

```text
Latitude
Longitude
Timestamp
Accuracy
```

### Requirements

* Request location permission.
* Handle permission denial.
* Handle unavailable GPS.
* Avoid exposing unnecessary location data.

---

# FR-04 — Destination Search

Users shall be able to search for destinations.

Example:

```text
Hospital
Mysore Palace
Bus Station
Shelter
Emergency Center
```

The backend may use Geoapify geocoding services.

### Output

```text
Place Name
Address
Latitude
Longitude
```

---

# FR-05 — Disaster-Aware Routing

This is the core product feature.

The system shall calculate routes using both:

### Transportation factors

* Distance
* Travel time
* Transportation mode

### Disaster factors

* Flood risk
* Landslide risk
* Road closure
* Incident information
* Disaster warnings
* Road confidence

---

# 9. Routing Modes

The system shall support:

```text
SAFEST
FASTEST
BALANCED
EMERGENCY
DRIVING
WALKING
CYCLING
```

These modes may be represented by a backend enum.

Example:

```json
{
  "source": "12.3004,76.6674",
  "destination": "12.3050,76.6700",
  "mode": "DRIVING"
}
```

---

# 10. Routing Algorithm

The routing engine shall evaluate candidate routes using a configurable cost function.

Conceptually:

```text
Route Cost =
    Distance Cost
  + Travel Time Cost
  + Disaster Risk Cost
  + Closure Penalty
  + Incident Penalty
```

For example:

```text
Cost = α(distance)
     + β(time)
     + γ(flood risk)
     + δ(landslide risk)
     + ε(closure)
```

The coefficients should be configurable.

---

# 11. Route Safety Logic

A route should be rejected if critical road segments are unavailable.

Example:

```text
Road A
   ↓
Flooded
   ↓
Route rejected
```

Alternative:

```text
Road A → Road B → Road C
             ↓
        Safe route
```

The system should return:

### Recommended route

* Route ID
* Distance
* ETA
* Overall risk
* Confidence
* Warnings
* Geometry
* Segments

### Alternative routes

The system may return additional routes for comparison.

---

# 12. Route Response

Example conceptual response:

```json
{
  "recommended": {
    "route_id": "route_0",
    "recommended": true,
    "distance_km": 5.2,
    "eta_minutes": 14,
    "risk": {
      "overall": "LOW",
      "flood": "LOW",
      "landslide": "LOW",
      "confidence": 90
    },
    "warnings": [],
    "geometry": [],
    "segments": []
  },
  "alternatives": [],
  "destination_risk": "LOW"
}
```

---

# 13. Local Cached Routing

The system should support a local/cached road graph.

This is important because disasters can cause:

* Internet outages
* Mobile network congestion
* API unavailability

The system should maintain locally available routing information.

### Offline flow

```text
Internet Available
       ↓
Download/Sync road data
       ↓
Local cache
       ↓
Network unavailable
       ↓
Local route calculation
```

---

# 14. Online Routing

When available, the system may use GraphHopper for external route calculation.

### Online flow

```text
Flutter
 ↓
FastAPI
 ↓
GraphHopper
 ↓
Route
 ↓
Disaster-risk evaluation
 ↓
Flutter
```

The application should clearly distinguish between:

```text
ONLINE ROUTE
```

and:

```text
OFFLINE/CACHED ROUTE
```

---

# 15. Road Management

The backend shall maintain road information.

Each road may contain:

* Road ID
* Road name
* Start node
* End node
* Distance
* Travel time
* Geometry
* Flood risk
* Landslide risk
* Confidence
* Closure status

---

# 16. Road Closures

Authorized users/admins shall be able to create road closures.

Example:

```text
Road: NH-212
Status: CLOSED
Reason: Flooding
Severity: HIGH
```

The routing engine must consider closed roads unavailable.

---

# 17. Disaster Incidents

Users or administrators shall be able to create incidents.

Possible incident types:

* Flood
* Landslide
* Fire
* Accident
* Earthquake
* Storm
* Road damage
* Building damage
* Other

### Incident data

```text
Incident ID
Type
Latitude
Longitude
Severity
Description
Reported By
Timestamp
Status
```

---

# 18. Community Reporting

Users shall be able to report hazards.

Example:

```text
User sees flooded road
        ↓
Open Report
        ↓
Select "Flood"
        ↓
Add location
        ↓
Add description/photo
        ↓
Submit
```

---

# 19. Report Verification

Reports should have a verification workflow.

```text
SUBMITTED
    ↓
PENDING
    ↓
VERIFIED
    ↓
ACTIVE
```

or:

```text
SUBMITTED
    ↓
REJECTED
```

Administrators should be able to:

* Verify
* Reject
* Group related reports

This reduces the risk of unreliable community information affecting routing.

---

# 20. Weather Information

The system shall provide weather information where API access is configured.

Possible information:

* Temperature
* Humidity
* Rain
* Wind
* Weather condition
* Visibility
* Weather alerts where available

Weather data can contribute to risk assessment.

---

# 21. Traffic Information

Where a traffic provider is configured, the system shall obtain traffic information.

Possible information:

* Congestion
* Travel time
* Traffic status
* Road delays

If unavailable, the system should gracefully fall back to cached/static data.

---

# 22. Risk Prediction

The system shall provide disaster-risk predictions.

Possible factors:

```text
Weather
+
Historical incidents
+
Current reports
+
Road conditions
+
Geographic information
```

Output:

```text
LOW
MEDIUM
HIGH
CRITICAL
```

The system should expose confidence information where available.

---

# 23. Emergency Facilities

The application shall maintain emergency facilities.

Examples:

* Hospitals
* Police stations
* Fire stations
* Emergency centers
* Relief centers
* Shelters

### Facility information

```text
Facility ID
Name
Type
Latitude
Longitude
Address
Contact
Capacity
Availability
```

---

# 24. Nearest Safe Facility

Users shall be able to find nearby safe facilities.

Example:

```text
Current Location
       ↓
Search facilities
       ↓
Calculate distance
       ↓
Filter unsafe/unavailable facilities
       ↓
Return nearest suitable facility
```

---

# 25. Safe Shelters

The system shall provide information about safe shelters.

Possible information:

* Shelter name
* Location
* Capacity
* Current occupancy
* Available services
* Safety status
* Contact information

---

# 26. Emergency SOS

The application shall provide an SOS feature.

Example:

```text
User presses SOS
       ↓
Confirm emergency
       ↓
Capture location
       ↓
Create SOS request
       ↓
Backend
       ↓
Emergency record
```

The system should clearly communicate that creating an SOS record does not necessarily mean that professional emergency services have been dispatched unless such integration exists.

---

# 27. Nearby Warnings

The system shall provide warnings relevant to the user's location.

Example:

```text
⚠ Flood warning
2.4 km away
High severity
```

Warnings should include:

* Title
* Description
* Location
* Radius
* Severity
* Timestamp
* Expiry

---

# 28. Synchronization

The mobile application shall synchronize locally cached data with the backend.

### Synchronizable data

* Roads
* Closures
* Incidents
* Reports
* Facilities
* Warnings

### Synchronization model

```text
Local Data
     ↓
Detect changes
     ↓
Sync API
     ↓
Server
     ↓
Conflict handling
     ↓
Updated local cache
```

---

# 29. Authentication and Authorization

Roles may include:

```text
USER
RESPONDER
ADMIN
```

### Example permissions

| Feature           | User | Responder | Admin |
| ----------------- | ---: | --------: | ----: |
| View routes       |    ✓ |         ✓ |     ✓ |
| Report incident   |    ✓ |         ✓ |     ✓ |
| View warnings     |    ✓ |         ✓ |     ✓ |
| Create closure    |    — |         ✓ |     ✓ |
| Verify report     |    — |         ✓ |     ✓ |
| Manage facilities |    — |         — |     ✓ |
| View audit logs   |    — |         — |     ✓ |

---

# 30. Audit Logging

Important administrative operations shall be recorded.

Example:

```text
User: admin123
Action: VERIFY_REPORT
Resource: report_105
Timestamp: 2026-09-18 10:45
```

Audit logs should not be editable through normal application operations.

---

# 31. Backend API Requirements

The backend currently exposes APIs including:

```text
GET    /health

POST   /auth/register
POST   /auth/login
GET    /auth/me

POST   /devices/push-token

GET    /roads

GET    /closures
POST   /closures
DELETE /closures/{road_id}

POST   /route

GET    /places/search
GET    /places/reverse

GET    /reports
POST   /reports
GET    /reports/mine

POST   /reports/{report_id}/verify
POST   /reports/{report_id}/reject

GET    /audit-logs

POST   /sync

GET    /facilities
GET    /facilities/nearest-safe

GET    /weather
GET    /traffic

POST   /risk/predict

GET    /incidents
POST   /incidents

POST   /reports/{report_id}/group

POST   /emergency/sos

GET    /warnings/nearby
```

---

# 32. API Error Handling

The backend should return meaningful HTTP status codes.

| Code | Meaning                      |
| ---- | ---------------------------- |
| 200  | Successful request           |
| 201  | Resource created             |
| 400  | Invalid request              |
| 401  | Authentication required      |
| 403  | Permission denied            |
| 404  | Resource/route unavailable   |
| 409  | Conflict                     |
| 422  | Validation error             |
| 429  | Too many requests            |
| 500  | Internal server error        |
| 503  | External service unavailable |

The mobile application should translate these into user-friendly messages.

---

# 33. Important Routing Error Handling

For example, if no safe route exists:

```json
{
  "detail": "No safe route is currently available"
}
```

The Flutter application should not simply display:

```text
404 Not Found
```

Instead it should display something like:

> **No safe route available**
> We couldn't find a route that meets the current safety conditions. Try another destination or check nearby shelters.

This distinction is important because HTTP `404` may represent an **application-level routing condition**, not a missing API endpoint.

---

# 34. Flutter Application Requirements

The Flutter application should provide the following primary screens:

### Authentication

* Splash screen
* Login
* Registration

### Main application

* Home
* Map
* Route planning
* Route details
* Disaster warnings
* Nearby facilities
* Shelters
* Reports
* Incidents
* Weather
* Profile
* SOS

---

# 35. Home Screen

The home screen should provide quick access to:

```text
Current Location

[ Where do you want to go? ]

[Find Safe Route]

Nearby:
 ├─ Warnings
 ├─ Shelters
 ├─ Hospitals
 └─ Emergency Facilities

[ SOS ]
```

---

# 36. Route Planning UI

Users should select:

```text
Source
Destination
Travel Mode
Routing Preference
```

Travel mode:

```text
Driving
Walking
Cycling
```

Routing preference:

```text
Safest
Fastest
Balanced
Emergency
```

---

# 37. Route Result UI

Display:

```text
Recommended Route

Distance: 5.2 km
ETA: 14 min

Risk: LOW

Flood Risk: LOW
Landslide Risk: LOW

Confidence: 92%

Warnings:
None
```

Alternative routes should also be displayed.

---

# 38. Map Visualization

The map should visualize:

### Normal roads

Standard route lines.

### High-risk roads

Risk indicators.

### Closed roads

Clearly marked as unavailable.

### Incidents

Incident markers.

### Facilities

Facility markers.

### Shelters

Shelter markers.

### Current location

User location marker.

---

# 39. Disaster Risk Visualization

Use consistent risk categories:

```text
LOW
MEDIUM
HIGH
CRITICAL
```

The UI should avoid relying solely on color; use:

* Text
* Icons
* Symbols
* Labels

This improves accessibility.

---

# 40. Report UI

A report form should include:

```text
Incident Type
Location
Description
Severity
Optional Image
Submit
```

After submission:

```text
Report submitted successfully.
Status: Pending verification.
```

---

# 41. Offline Mode

When connectivity is unavailable, the application should:

* Display cached map/road data.
* Calculate routes using cached graph data.
* Display cached facilities.
* Display cached warnings with timestamps.
* Queue reports for later synchronization.

The UI should clearly indicate:

```text
OFFLINE MODE
```

and show the timestamp of cached information.

---

# 42. Connectivity Strategy

For Android development using a physical phone and USB debugging, the development configuration can use:

```text
127.0.0.1:8000
```

with ADB reverse:

```cmd
adb reverse tcp:8000 tcp:8000
```

This allows:

```text
Flutter Phone
     ↓
USB
     ↓
ADB Reverse
     ↓
127.0.0.1:8000
     ↓
FastAPI
```

For production deployment, the mobile application should use the deployed backend URL rather than the development ADB configuration.

---

# 43. External Services

Potential integrations:

| Service          | Purpose                     |
| ---------------- | --------------------------- |
| Geoapify         | Geocoding/reverse geocoding |
| GraphHopper      | Online routing              |
| OpenWeather      | Weather                     |
| Traffic provider | Traffic conditions          |
| PostgreSQL       | Production database         |

The system must support graceful degradation if an external provider is unavailable.

---

# 44. Graceful Degradation

Example:

```text
GraphHopper unavailable
        ↓
Use local route graph
        ↓
Calculate cached route
        ↓
Show "Offline/Cached route"
```

Similarly:

```text
Weather API unavailable
        ↓
Show last cached weather
        ↓
Display timestamp
```

The application should never silently present stale data as real-time information.

---

# 45. Non-Functional Requirements

## NFR-01 Performance

Normal API responses should ideally complete within:

```text
< 2 seconds
```

under normal local/provider conditions.

Route calculation should target:

```text
< 3 seconds
```

for the normal cached graph.

---

## NFR-02 Availability

Core local routing should remain available when external routing providers are unavailable.

---

## NFR-03 Security

The system shall:

* Use HTTPS in production.
* Hash passwords.
* Use JWT authentication.
* Protect administrative APIs.
* Validate user input.
* Protect API keys.
* Avoid exposing secrets to Flutter.
* Record sensitive administrative actions.

---

# 46. API Key Security

Provider API keys must remain on the backend.

Architecture:

```text
Flutter
   ↓
FastAPI
   ↓
Geoapify / GraphHopper / Weather API
```

Not:

```text
Flutter
   ↓
API Key
   ↓
External provider
```

`.env` should never be committed to Git.

Example:

```text
.env
.env.example
```

`.env` should be included in `.gitignore`.

---

# 47. Privacy Requirements

The application handles potentially sensitive information such as:

* Location
* User account information
* Emergency reports
* SOS events

Therefore:

* Collect only necessary information.
* Explain location usage.
* Restrict access to user-specific data.
* Protect stored credentials.
* Avoid unnecessary location retention.
* Apply role-based authorization.

---

# 48. Reliability Requirements

The system should handle:

* API timeouts
* Network loss
* Invalid GPS coordinates
* Invalid destinations
* External provider failures
* Empty route results
* Invalid reports
* Duplicate reports
* Database failures

The mobile application should provide understandable error messages.

---

# 49. Database Requirements

Core entities include:

```text
User
Road
RoadClosure
Incident
Report
Facility
Warning
Route
AuditLog
DeviceToken
```

Conceptual relationships:

```text
User
 ├── Reports
 ├── Incidents
 ├── SOS
 └── Device Tokens

Road
 ├── Closures
 └── Route Segments

Reports
 └── Incidents

Facilities
 └── Locations

Warnings
 └── Geographic Areas
```

---

# 50. Data Validation

Examples:

### Latitude

```text
-90 ≤ latitude ≤ 90
```

### Longitude

```text
-180 ≤ longitude ≤ 180
```

### Severity

Only supported enum values should be accepted.

### Routing mode

Only:

```text
SAFEST
FASTEST
BALANCED
EMERGENCY
DRIVING
WALKING
CYCLING
```

should be accepted.

This also explains the earlier API validation behavior when `"driving"` was sent instead of `"DRIVING"`.

---

# 51. Testing Requirements

## Unit Testing

Test:

* Route calculations
* Risk calculations
* Authentication
* Validation
* Incident processing
* Report processing
* Synchronization

---

## API Testing

Test every endpoint.

Example:

```text
POST /auth/login
POST /route
GET /roads
GET /facilities
POST /emergency/sos
```

---

## Flutter Testing

Test:

* Login
* Navigation
* Map
* Route request
* Error handling
* SOS
* Reports
* Offline mode

---

# 52. Integration Testing

Test complete workflows.

### Route workflow

```text
Login
 ↓
Get location
 ↓
Select destination
 ↓
Request route
 ↓
Backend
 ↓
Risk evaluation
 ↓
Route response
 ↓
Display map
```

### Reporting workflow

```text
User
 ↓
Create report
 ↓
Backend
 ↓
Pending
 ↓
Admin
 ↓
Verify
 ↓
Incident/risk data updated
```

---

# 53. Acceptance Criteria

The product will be considered functionally complete when:

### Authentication

* [ ] User can register.
* [ ] User can log in.
* [ ] JWT authentication works.
* [ ] Protected endpoints reject unauthorized users.

### Routing

* [ ] User location can be obtained.
* [ ] Destination can be selected.
* [ ] Route request reaches backend.
* [ ] Supported routing modes work.
* [ ] Unsafe/closed roads can be excluded.
* [ ] Alternative routes can be returned.
* [ ] Offline routing works with cached data.

### Disaster management

* [ ] Incidents can be created.
* [ ] Reports can be submitted.
* [ ] Reports can be verified/rejected.
* [ ] Road closures affect routing.
* [ ] Warnings can be displayed.

### Emergency

* [ ] SOS can be generated.
* [ ] Nearby facilities can be found.
* [ ] Safe shelters can be displayed.

### Reliability

* [ ] External provider failures are handled.
* [ ] Cached data can be used.
* [ ] Synchronization works after reconnection.

---

# 54. MVP Definition

The minimum viable product should contain:

```text
Authentication
       +
Location
       +
Destination Search
       +
Disaster-Aware Routing
       +
Road Closures
       +
Incident Reports
       +
Emergency Facilities
       +
SOS
       +
Basic Offline Cache
```

Advanced features can then be added.

---

# 55. Phase 1 — Foundation

### Deliverables

* Flutter project
* FastAPI project
* Database
* Authentication
* Basic API architecture
* Environment configuration

---

# 56. Phase 2 — Mapping & Routing

### Deliverables

* Current location
* Geocoding
* Reverse geocoding
* Road graph
* Route calculation
* Route alternatives
* GraphHopper integration
* Local routing

---

# 57. Phase 3 — Disaster Intelligence

### Deliverables

* Incidents
* Road closures
* Disaster reports
* Risk prediction
* Warnings
* Weather
* Traffic

---

# 58. Phase 4 — Emergency Management

### Deliverables

* Emergency facilities
* Safe shelters
* Nearest safe facility
* SOS
* Emergency workflows

---

# 59. Phase 5 — Offline & Synchronization

### Deliverables

* Local database/cache
* Cached routing graph
* Offline routing
* Offline report queue
* Synchronization
* Conflict handling

---

# 60. Phase 6 — Testing & Deployment

### Deliverables

* Backend unit tests
* API tests
* Flutter tests
* Integration tests
* Security testing
* Android release build
* Production backend
* Deployment documentation

---

# 61. Success Metrics

For a college/prototype implementation, useful measurable metrics include:

### Routing

* Route calculation success rate
* Average route calculation time
* Percentage of unsafe roads correctly excluded

### API

* API response time
* API error rate
* External provider failure recovery

### Application

* Crash-free sessions
* Successful route requests
* Successful report submissions

### Offline

* Offline route success rate
* Synchronization success rate

---

# 62. Major Risks

| Risk                       | Impact | Mitigation                      |
| -------------------------- | ------ | ------------------------------- |
| Internet unavailable       | High   | Local cached routing            |
| External API unavailable   | High   | Provider fallback               |
| Incorrect community report | High   | Verification workflow           |
| Outdated road information  | High   | Synchronization                 |
| GPS inaccurate             | Medium | Accuracy indicator              |
| API key exposure           | High   | Backend-only secrets            |
| Database failure           | High   | Backup/recovery                 |
| False risk prediction      | High   | Confidence + source information |

---

# 63. Future Enhancements

Potential future versions can include:

### AI-based disaster prediction

Use historical and real-time data to predict:

* Flood probability
* Landslide probability
* Road failure

### Computer vision

Analyze uploaded images to detect:

* Flooded roads
* Fire
* Road damage
* Landslides

### Real-time crowdsourcing

Aggregate reports from multiple users.

### Government integration

Integrate official:

* Weather alerts
* Disaster-management systems
* Emergency services
* Road authorities

### Push notifications

Notify users about nearby:

* Floods
* Road closures
* Severe weather
* Shelters

### Advanced route optimization

Optimize for:

```text
Safety
+
Distance
+
Time
+
Vehicle type
+
Emergency priority
```

---

# 64. High-Level System Architecture

```text
                  ┌─────────────────────┐
                  │    Flutter Mobile   │
                  │       App           │
                  └──────────┬──────────┘
                             │
                       HTTPS / REST
                             │
                             ▼
                  ┌─────────────────────┐
                  │     FastAPI         │
                  │      Backend        │
                  └──────────┬──────────┘
                             │
          ┌──────────────────┼───────────────────┐
          │                  │                   │
          ▼                  ▼                   ▼
    ┌───────────┐      ┌────────────┐     ┌────────────┐
    │ PostgreSQL│      │ Local Route│     │ Risk Engine│
    │ Database  │      │   Graph    │     │            │
    └───────────┘      └────────────┘     └────────────┘
                             │
                 ┌───────────┼────────────┐
                 │           │            │
                 ▼           ▼            ▼
             Geoapify   GraphHopper   Weather API
```

---

# 65. Core User Journey

```text
                  START
                    │
                    ▼
                 Login
                    │
                    ▼
             Get Current Location
                    │
                    ▼
            Enter Destination
                    │
                    ▼
             Select Route Mode
                    │
                    ▼
             Request Safe Route
                    │
                    ▼
          ┌─────────────────────┐
          │ Disaster Risk Check │
          └──────────┬──────────┘
                     │
          ┌──────────┴───────────┐
          ▼                      ▼
      Safe route             Unsafe route
          │                      │
          ▼                      ▼
    Show navigation        Find alternative
                                 │
                                 ▼
                          Safe alternative
                                 │
                                 ▼
                           Show route
                                 │
                                 ▼
                                END
```

---

# 66. Product Principle

The core design principle of this project is:

> **The shortest route is not necessarily the safest route.**

The system therefore combines **navigation + disaster intelligence + emergency management** into one platform.

---

# 67. Final Product Definition

The completed system will function as a **disaster-aware mobile navigation and emergency-management platform** where:

```text
             USER
               │
               ▼
        Flutter Mobile App
               │
               ▼
          FastAPI Backend
               │
     ┌─────────┼──────────┐
     ▼         ▼          ▼
  Routing    Risk      Emergency
     │         │          │
     ▼         ▼          ▼
  Roads     Incidents   Shelters
  Closures  Weather     Facilities
  Graph     Reports     SOS
     │         │          │
     └─────────┼──────────┘
               ▼
       SAFE DECISION SUPPORT
```

The result is a system that does more than conventional navigation: it uses **road conditions, disaster information, risk levels, incidents, closures, and emergency resources** to help users make safer travel decisions during emergencies.
