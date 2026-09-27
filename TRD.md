# TECHNICAL REQUIREMENTS SPECIFICATION (TRS)

## Disaster Aware Routing & Emergency Management System

**Document Version:** 1.0
**Document Status:** Baseline
**Document Type:** Technical Requirements Specification
**Development Methodology:** Iterative / Agile
**Client Platform:** Flutter Android Application
**Backend Platform:** Python FastAPI
**Database:** SQLite / PostgreSQL
**Routing:** Local Graph + GraphHopper
**Authentication:** JWT

---

# 1. Document Control

## 1.1 Purpose

This Technical Requirements Specification defines the functional, non-functional, technical, integration, security, performance, and deployment requirements for the **Disaster Aware Routing & Emergency Management System**.

The document establishes a measurable baseline against which the implementation and testing of the system can be evaluated.

Each requirement is assigned a unique identifier, priority, dependency information, and verification method.

---

## 1.2 Intended Audience

This document is intended for:

* Project developers
* Backend developers
* Flutter developers
* Database developers
* Test engineers
* Project guides
* System administrators
* Academic evaluators
* Future maintenance teams

---

# 2. System Purpose

The system provides disaster-aware navigation and emergency-management capabilities through a mobile application.

The system shall analyze available road, disaster, incident, weather, traffic, and closure information to provide routes that consider both **travel efficiency and safety**.

The system shall also provide:

* User authentication
* Location search
* Route planning
* Disaster-aware routing
* Road closure management
* Incident reporting
* Community reports
* Report verification
* Emergency facilities
* SOS functionality
* Disaster warnings
* Risk prediction
* Data synchronization
* Offline/local routing

---

# 3. System Architecture

The proposed architecture is:

```text
+--------------------------------------------------+
|              Flutter Mobile Application          |
|                                                  |
| Authentication | Map | Routing | Reports | SOS  |
+-----------------------------+--------------------+
                              |
                              | HTTPS / REST
                              |
+-----------------------------v--------------------+
|                 FastAPI Backend                  |
|                                                  |
| Auth | Routing | Risk | Reports | Incidents     |
| Weather | Traffic | Facilities | Warnings       |
+----------------------+---------------------------+
                       |
          +------------+-------------+
          |            |             |
          v            v             v
     +---------+  +---------+  +-------------+
     |Database |  | Routing |  | External    |
     |         |  | Engine  |  | Services    |
     |SQLite/  |  |Local +  |  |Geoapify     |
     |Postgres |  |GraphH.  |  |GraphHopper  |
     +---------+  +---------+  |Weather      |
                               |Traffic      |
                               +-------------+
```

---

# 4. Requirement Classification

Requirements are divided into:

| Category       | Prefix | Description                             |
| -------------- | ------ | --------------------------------------- |
| Functional     | FR     | Required system functionality           |
| Non-Functional | NFR    | Quality and operational requirements    |
| Interface      | IF     | User/system/API interfaces              |
| Security       | SEC    | Security and privacy                    |
| Data           | DR     | Data and database requirements          |
| Integration    | INT    | External system integration             |
| Performance    | PER    | Performance requirements                |
| Deployment     | DEP    | Deployment and environment requirements |

---

# 5. Priority Classification

Each requirement uses the following priority:

### P1 — Mandatory

The system cannot be considered complete without the requirement.

### P2 — Important

Required for a complete production-quality implementation but may be deferred during early development.

### P3 — Optional / Future

Useful enhancement that can be implemented in a later version.

---

# 6. Functional Requirements

## 6.1 User Registration

### FR-AUTH-001 — User Registration

**Priority:** P1
**Dependency:** DR-USER-001
**Verification:** Functional Test

The system shall allow a new user to create an account using valid registration information.

**Acceptance Criteria:**

* Valid registration data creates a user account.
* Duplicate accounts are rejected.
* Invalid input generates a validation error.
* Passwords are not stored in plain text.

---

## 6.2 User Authentication

### FR-AUTH-002 — User Login

**Priority:** P1
**Dependency:** FR-AUTH-001, SEC-AUTH-001
**Verification:** Functional Test

The system shall authenticate users using valid credentials.

**API:**

```text
POST /auth/login
```

**Acceptance Criteria:**

* Valid credentials produce an authentication token.
* Invalid credentials are rejected.
* Expired credentials cannot be used.

---

### FR-AUTH-003 — JWT Authentication

**Priority:** P1
**Dependency:** FR-AUTH-002
**Verification:** Security Test

The system shall use JWT-based authentication for protected API resources.

---

### FR-AUTH-004 — Current User Information

**Priority:** P2
**Dependency:** FR-AUTH-003
**Verification:** API Test

The system shall provide:

```text
GET /auth/me
```

to retrieve information about the authenticated user.

---

# 7. Location Requirements

### FR-LOC-001 — Place Search

**Priority:** P1
**Dependency:** INT-GEO-001
**Verification:** Integration Test

The system shall allow users to search for geographic locations.

```text
GET /places/search
```

---

### FR-LOC-002 — Reverse Geocoding

**Priority:** P1
**Dependency:** INT-GEO-001
**Verification:** Integration Test

The system shall convert latitude and longitude into a human-readable location.

```text
GET /places/reverse
```

---

### FR-LOC-003 — GPS Location

**Priority:** P1
**Dependency:** IF-MOB-001
**Verification:** Device Test

The mobile application shall obtain the user's current geographic coordinates when location permission is granted.

---

# 8. Routing Requirements

### FR-ROUTE-001 — Route Calculation

**Priority:** P1
**Dependency:** DR-ROAD-001, FR-ROUTE-002
**Verification:** Functional Test

The system shall calculate a route between a source and destination.

```text
POST /route
```

---

### FR-ROUTE-002 — Routing Modes

**Priority:** P1
**Dependency:** FR-ROUTE-001
**Verification:** Functional Test

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

---

### FR-ROUTE-003 — Disaster-Aware Routing

**Priority:** P1
**Dependency:** FR-RISK-001, FR-CLOSURE-001, DR-ROAD-001
**Verification:** Integration Test

The routing engine shall consider disaster-related conditions when calculating routes.

---

### FR-ROUTE-004 — Alternative Routes

**Priority:** P2
**Dependency:** FR-ROUTE-001
**Verification:** Functional Test

The system shall return alternative routes where multiple valid paths exist.

---

### FR-ROUTE-005 — Route Risk Information

**Priority:** P1
**Dependency:** FR-RISK-001
**Verification:** Functional Test

The route response shall include:

* Overall risk
* Flood risk
* Landslide risk
* Confidence
* Warnings

---

### FR-ROUTE-006 — Local Route Calculation

**Priority:** P1
**Dependency:** DR-ROAD-001
**Verification:** Offline Test

The system shall support route calculation using a locally available road graph.

---

### FR-ROUTE-007 — Online Route Calculation

**Priority:** P2
**Dependency:** INT-ROUTE-001
**Verification:** Integration Test

The system shall support online route calculation through GraphHopper when configured.

---

### FR-ROUTE-008 — Route Fallback

**Priority:** P1
**Dependency:** FR-ROUTE-006, FR-ROUTE-007
**Verification:** Failure Recovery Test

When the online routing provider is unavailable, the system shall attempt local routing where sufficient local data exists.

---

# 9. Road Management Requirements

### FR-ROAD-001 — Road Retrieval

**Priority:** P1
**Dependency:** DR-ROAD-001
**Verification:** API Test

The system shall provide:

```text
GET /roads
```

to retrieve road information.

---

### FR-ROAD-002 — Road Information

**Priority:** P1
**Dependency:** DR-ROAD-001
**Verification:** Database Test

Each road shall support:

* Road ID
* Name
* Geometry
* Distance
* Travel time
* Flood risk
* Landslide risk
* Confidence
* Closure status

---

# 10. Road Closure Requirements

### FR-CLOSE-001 — Road Closure Creation

**Priority:** P1
**Dependency:** DR-CLOSE-001
**Verification:** Functional Test

Authorized users shall be able to create road closure records.

---

### FR-CLOSE-002 — Road Closure Retrieval

**Priority:** P1
**Dependency:** FR-CLOSE-001
**Verification:** API Test

The system shall provide:

```text
GET /closures
```

---

### FR-CLOSE-003 — Road Closure Removal

**Priority:** P2
**Dependency:** FR-CLOSE-001
**Verification:** Functional Test

Authorized users shall be able to remove or deactivate a road closure.

---

### FR-CLOSE-004 — Closure-Aware Routing

**Priority:** P1
**Dependency:** FR-CLOSE-001, FR-ROUTE-001
**Verification:** Integration Test

The routing engine shall avoid or heavily penalize roads marked as closed.

---

# 11. Risk Management Requirements

### FR-RISK-001 — Risk Calculation

**Priority:** P1
**Dependency:** DR-RISK-001
**Verification:** Functional Test

The system shall calculate a route or road risk level.

Supported levels:

```text
LOW
MEDIUM
HIGH
CRITICAL
```

---

### FR-RISK-002 — Risk Factors

**Priority:** P1
**Dependency:** FR-RISK-001
**Verification:** Functional Test

The risk calculation shall consider available:

* Flood information
* Landslide information
* Road closures
* Weather
* Traffic
* Incidents

---

### FR-RISK-003 — Risk Prediction

**Priority:** P2
**Dependency:** DR-RISK-001
**Verification:** Integration Test

The system shall provide a risk prediction service.

```text
/risk/predict
```

---

# 12. Incident Requirements

### FR-INC-001 — Incident Creation

**Priority:** P1
**Dependency:** DR-INC-001
**Verification:** Functional Test

Users or authorized personnel shall be able to report incidents.

---

### FR-INC-002 — Incident Retrieval

**Priority:** P1
**Dependency:** FR-INC-001
**Verification:** API Test

The system shall provide:

```text
GET /incidents
```

---

### FR-INC-003 — Incident Classification

**Priority:** P1
**Dependency:** FR-INC-001
**Verification:** Functional Test

Incidents shall support types such as:

* Flood
* Landslide
* Accident
* Fire
* Road blockage
* Infrastructure damage

---

# 13. Community Reporting Requirements

### FR-REPORT-001 — Report Submission

**Priority:** P1
**Dependency:** FR-AUTH-003, DR-REPORT-001
**Verification:** Functional Test

Authenticated users shall be able to submit disaster or road-condition reports.

---

### FR-REPORT-002 — User Report History

**Priority:** P2
**Dependency:** FR-REPORT-001
**Verification:** API Test

Users shall be able to retrieve their own reports.

```text
GET /reports/mine
```

---

### FR-REPORT-003 — Report Verification

**Priority:** P1
**Dependency:** FR-REPORT-001, SEC-AUTH-002
**Verification:** Authorization Test

Authorized users shall be able to verify reports.

---

### FR-REPORT-004 — Report Rejection

**Priority:** P1
**Dependency:** FR-REPORT-001, SEC-AUTH-002
**Verification:** Authorization Test

Authorized users shall be able to reject invalid reports.

---

### FR-REPORT-005 — Report Grouping

**Priority:** P2
**Dependency:** FR-REPORT-001
**Verification:** Integration Test

The system shall support grouping related reports referring to the same incident.

---

# 14. Emergency Requirements

### FR-EMG-001 — Emergency SOS

**Priority:** P1
**Dependency:** FR-LOC-003, FR-AUTH-003
**Verification:** End-to-End Test

The system shall provide:

```text
POST /emergency/sos
```

to record an emergency event.

---

### FR-EMG-002 — Emergency Location

**Priority:** P1
**Dependency:** FR-EMG-001, FR-LOC-003
**Verification:** Device Test

The SOS request shall support the user's current location.

---

# 15. Emergency Facility Requirements

### FR-FAC-001 — Facility Retrieval

**Priority:** P1
**Dependency:** DR-FAC-001
**Verification:** API Test

The system shall provide emergency facilities.

---

### FR-FAC-002 — Nearest Safe Facility

**Priority:** P1
**Dependency:** FR-FAC-001, FR-RISK-001, FR-ROUTE-003
**Verification:** Integration Test

The system shall identify nearby accessible facilities while considering route safety.

```text
GET /facilities/nearest-safe
```

---

# 16. Warning Requirements

### FR-WARN-001 — Nearby Warnings

**Priority:** P1
**Dependency:** FR-INC-001, FR-RISK-001
**Verification:** Integration Test

The system shall provide warnings relevant to the user's location.

```text
GET /warnings/nearby
```

---

### FR-WARN-002 — Warning Severity

**Priority:** P1
**Dependency:** FR-WARN-001
**Verification:** Functional Test

Warnings shall support severity levels.

---

# 17. Weather Requirements

### FR-WEATHER-001 — Weather Retrieval

**Priority:** P2
**Dependency:** INT-WEATHER-001
**Verification:** Integration Test

The system shall retrieve weather information from a configured provider.

---

### FR-WEATHER-002 — Weather Failure Handling

**Priority:** P1
**Dependency:** FR-WEATHER-001
**Verification:** Failure Test

The system shall continue operating when the weather provider is unavailable.

---

# 18. Traffic Requirements

### FR-TRAFFIC-001 — Traffic Retrieval

**Priority:** P2
**Dependency:** INT-TRAFFIC-001
**Verification:** Integration Test

The system shall retrieve traffic information when a traffic provider is configured.

---

### FR-TRAFFIC-002 — Traffic Failure Handling

**Priority:** P1
**Dependency:** FR-TRAFFIC-001
**Verification:** Failure Test

Traffic-provider failure shall not terminate the application.

---

# 19. Synchronization Requirements

### FR-SYNC-001 — Data Synchronization

**Priority:** P1
**Dependency:** DR-SYNC-001
**Verification:** Integration Test

The mobile application shall synchronize locally cached data with the backend.

---

### FR-SYNC-002 — Cached Data

**Priority:** P1
**Dependency:** FR-SYNC-001
**Verification:** Offline Test

The application shall retain selected data for offline usage.

---

### FR-SYNC-003 — Offline Routing

**Priority:** P1
**Dependency:** FR-ROUTE-006, FR-SYNC-002
**Verification:** Offline Test

The system shall support local route calculation when sufficient cached road data is available.

---

# 20. Database Requirements

### DR-USER-001 — User Data

**Priority:** P1
**Dependency:** None
**Verification:** Database Test

The database shall store user account information securely.

---

### DR-ROAD-001 — Road Graph Data

**Priority:** P1
**Dependency:** None
**Verification:** Database Test

The database or local data store shall maintain road graph information required for routing.

---

### DR-CLOSE-001 — Closure Data

**Priority:** P1
**Dependency:** DR-ROAD-001
**Verification:** Database Test

The system shall store road closure information.

---

### DR-REPORT-001 — Report Data

**Priority:** P1
**Dependency:** DR-USER-001
**Verification:** Database Test

The system shall store community reports.

---

### DR-INC-001 — Incident Data

**Priority:** P1
**Dependency:** None
**Verification:** Database Test

The system shall store incident information.

---

### DR-FAC-001 — Facility Data

**Priority:** P1
**Dependency:** None
**Verification:** Database Test

The system shall store emergency facility information.

---

### DR-RISK-001 — Risk Data

**Priority:** P1
**Dependency:** DR-ROAD-001
**Verification:** Database Test

The system shall store or calculate risk-related road information.

---

### DR-SYNC-001 — Synchronization Data

**Priority:** P1
**Dependency:** DR-ROAD-001
**Verification:** Integration Test

The system shall maintain metadata necessary to synchronize cached information.

---

# 21. Security Requirements

### SEC-AUTH-001 — Password Protection

**Priority:** P1
**Dependency:** FR-AUTH-001
**Verification:** Security Test

Passwords shall be stored using secure password hashing.

---

### SEC-AUTH-002 — Authorization

**Priority:** P1
**Dependency:** FR-AUTH-003
**Verification:** Security Test

Protected operations shall only be accessible to authorized users.

---

### SEC-AUTH-003 — Token Expiration

**Priority:** P1
**Dependency:** FR-AUTH-003
**Verification:** Security Test

JWT tokens shall expire after the configured period.

---

### SEC-DATA-001 — Secret Protection

**Priority:** P1
**Dependency:** DEP-CONFIG-001
**Verification:** Security Review

API keys and cryptographic secrets shall not be hard-coded into source code.

---

### SEC-DATA-002 — Client Secret Isolation

**Priority:** P1
**Dependency:** SEC-DATA-001
**Verification:** Security Review

Third-party API secrets shall remain on the backend and shall not be embedded in the Flutter application.

---

### SEC-LOG-001 — Sensitive Data Logging

**Priority:** P1
**Dependency:** INT-LOG-001
**Verification:** Security Review

Passwords, JWT secrets, API keys, and other sensitive credentials shall not be written to logs.

---

# 22. Interface Requirements

### IF-MOB-001 — Mobile Location Interface

**Priority:** P1
**Dependency:** Android location services
**Verification:** Device Test

The mobile application shall interface with Android location services.

---

### IF-MOB-002 — REST API Interface

**Priority:** P1
**Dependency:** Backend availability
**Verification:** Integration Test

Flutter shall communicate with FastAPI through HTTP/REST APIs.

---

### IF-MOB-003 — Error Interface

**Priority:** P1
**Dependency:** IF-MOB-002
**Verification:** UI Test

The Flutter application shall display meaningful messages for API failures.

---

### IF-API-001 — JSON Interface

**Priority:** P1
**Dependency:** IF-MOB-002
**Verification:** API Test

REST API request and response bodies shall use JSON where applicable.

---

# 23. Integration Requirements

### INT-GEO-001 — Geoapify Integration

**Priority:** P2
**Dependency:** SEC-DATA-001
**Verification:** Integration Test

The backend shall support Geoapify for geocoding and reverse geocoding.

---

### INT-ROUTE-001 — GraphHopper Integration

**Priority:** P2
**Dependency:** SEC-DATA-001
**Verification:** Integration Test

The backend shall support GraphHopper for online routing.

---

### INT-WEATHER-001 — Weather API

**Priority:** P2
**Dependency:** SEC-DATA-001
**Verification:** Integration Test

The backend shall support a configurable weather API.

---

### INT-TRAFFIC-001 — Traffic API

**Priority:** P2
**Dependency:** SEC-DATA-001
**Verification:** Integration Test

The backend shall support a configurable traffic API.

---

### INT-LOG-001 — Application Logging

**Priority:** P1
**Dependency:** None
**Verification:** System Test

The backend shall maintain application logs for significant events and failures.

---

# 24. Performance Requirements

### PER-001 — API Response Time

**Priority:** P1
**Dependency:** Backend deployment
**Verification:** Performance Test

Normal backend API requests should respond within approximately:

```text
2 seconds
```

under normal development/deployment conditions, excluding slow third-party APIs.

---

### PER-002 — Local Route Calculation

**Priority:** P1
**Dependency:** FR-ROUTE-006
**Verification:** Performance Test

Local route calculation should normally complete within approximately:

```text
2 seconds
```

for the supported local road graph.

---

### PER-003 — Mobile Responsiveness

**Priority:** P1
**Dependency:** Flutter implementation
**Verification:** UI Performance Test

Long-running route or synchronization operations shall not block the Flutter UI thread.

---

# 25. Reliability Requirements

### NFR-REL-001 — External Service Failure

**Priority:** P1
**Dependency:** INT-GEO-001, INT-ROUTE-001
**Verification:** Failure Test

Failure of an external service shall not crash the complete application.

---

### NFR-REL-002 — Local Fallback

**Priority:** P1
**Dependency:** FR-ROUTE-006
**Verification:** Failure Recovery Test

The system shall use local routing where possible when online routing is unavailable.

---

### NFR-REL-003 — Invalid External Response

**Priority:** P1
**Dependency:** External APIs
**Verification:** Failure Test

Invalid or unexpected external API responses shall be handled safely.

---

# 26. Usability Requirements

### NFR-USE-001 — Simple Navigation

**Priority:** P1
**Dependency:** Flutter UI
**Verification:** Usability Test

The application shall provide clear navigation between major functions.

---

### NFR-USE-002 — Emergency Accessibility

**Priority:** P1
**Dependency:** FR-EMG-001
**Verification:** Usability Test

The emergency/SOS functionality shall be easily accessible from the primary application interface.

---

### NFR-USE-003 — Clear Risk Presentation

**Priority:** P1
**Dependency:** FR-RISK-001
**Verification:** UI Test

Route risk and disaster warnings shall be presented clearly to the user.

---

# 27. Maintainability Requirements

### NFR-MAIN-001 — Modular Backend

**Priority:** P1
**Dependency:** None
**Verification:** Code Review

The backend shall separate major concerns such as:

* Configuration
* Models
* Routing
* Authentication
* Risk
* External services
* API endpoints

---

### NFR-MAIN-002 — Configuration Management

**Priority:** P1
**Dependency:** SEC-DATA-001
**Verification:** Code Review

Environment-specific configuration shall be maintained separately from application source code.

---

# 28. Deployment Requirements

### DEP-CONFIG-001 — Environment Configuration

**Priority:** P1
**Dependency:** None
**Verification:** Deployment Test

The backend shall load configuration through environment variables or a secure environment configuration file.

Example:

```text
JWT_SECRET
DATABASE_URL
GEOAPIFY_API_KEY
GRAPHHOPPER_API_KEY
WEATHER_API_KEY
TRAFFIC_API_KEY
```

---

### DEP-BACKEND-001 — FastAPI Deployment

**Priority:** P1
**Dependency:** Backend implementation
**Verification:** Deployment Test

The backend shall be executable through Uvicorn.

Example:

```cmd
uvicorn backend.app.main:app --host 0.0.0.0 --port 8000
```

---

### DEP-MOBILE-001 — Android Deployment

**Priority:** P1
**Dependency:** Flutter implementation
**Verification:** Device Test

The Flutter application shall build and run on a supported Android device.

---

# 29. Development Connectivity Requirements

### DEP-CONNECT-001 — ADB Reverse Connection

**Priority:** P1
**Dependency:** Android USB debugging
**Verification:** Device Test

During local development, the Android device shall be capable of accessing the local FastAPI backend through ADB reverse.

```cmd
adb reverse tcp:8000 tcp:8000
```

The application shall use:

```text
http://127.0.0.1:8000
```

for this development configuration.

---

# 30. Testing Requirements

### TEST-001 — Unit Testing

**Priority:** P1

The system shall include unit tests for critical business logic.

---

### TEST-002 — API Testing

**Priority:** P1

All major API endpoints shall be tested for:

* Valid input
* Invalid input
* Authentication
* Authorization
* Error handling

---

### TEST-003 — Integration Testing

**Priority:** P1

Integration tests shall verify communication between:

```text
Flutter
↓
FastAPI
↓
Database
↓
Routing/External Services
```

---

### TEST-004 — Offline Testing

**Priority:** P1

The application shall be tested with external network connectivity disabled.

---

### TEST-005 — Failure Testing

**Priority:** P1

The system shall be tested under:

* API failure
* Database failure
* Invalid route
* Missing API key
* Invalid authentication
* External service timeout

---

# 31. Requirement Dependency Summary

The major dependency flow is:

```text
User Authentication
        |
        v
   Authorization
        |
        +-------------------+
        |                   |
        v                   v
   User Reports          Emergency
        |                   |
        v                   v
   Incidents            SOS / Facilities
        |
        v
   Risk Engine
        |
        v
  Routing Engine
        |
        +----------------+
        |                |
        v                v
   Local Graph       GraphHopper
        |
        v
 Route Recommendation
```

---

# 32. Requirements Traceability Matrix

The following matrix maps major requirements to system modules and verification methods.

| Requirement ID  | Requirement               | Module              | Dependency      | Priority | Verification     |
| --------------- | ------------------------- | ------------------- | --------------- | -------- | ---------------- |
| FR-AUTH-001     | User Registration         | Authentication      | DR-USER-001     | P1       | Functional       |
| FR-AUTH-002     | User Login                | Authentication      | FR-AUTH-001     | P1       | Functional       |
| FR-AUTH-003     | JWT Authentication        | Security            | FR-AUTH-002     | P1       | Security         |
| FR-AUTH-004     | Current User              | Authentication      | FR-AUTH-003     | P2       | API              |
| FR-LOC-001      | Place Search              | Location            | INT-GEO-001     | P1       | Integration      |
| FR-LOC-002      | Reverse Geocoding         | Location            | INT-GEO-001     | P1       | Integration      |
| FR-LOC-003      | GPS Location              | Flutter             | IF-MOB-001      | P1       | Device           |
| FR-ROUTE-001    | Route Calculation         | Routing             | DR-ROAD-001     | P1       | Functional       |
| FR-ROUTE-002    | Routing Modes             | Routing             | FR-ROUTE-001    | P1       | Functional       |
| FR-ROUTE-003    | Disaster-Aware Routing    | Routing/Risk        | FR-RISK-001     | P1       | Integration      |
| FR-ROUTE-004    | Alternative Routes        | Routing             | FR-ROUTE-001    | P2       | Functional       |
| FR-ROUTE-005    | Route Risk                | Routing/Risk        | FR-RISK-001     | P1       | Functional       |
| FR-ROUTE-006    | Local Routing             | Routing             | DR-ROAD-001     | P1       | Offline          |
| FR-ROUTE-007    | Online Routing            | Routing             | INT-ROUTE-001   | P2       | Integration      |
| FR-ROUTE-008    | Routing Fallback          | Routing             | FR-ROUTE-006    | P1       | Failure Recovery |
| FR-ROAD-001     | Road Retrieval            | Road Management     | DR-ROAD-001     | P1       | API              |
| FR-ROAD-002     | Road Information          | Database            | DR-ROAD-001     | P1       | Database         |
| FR-CLOSE-001    | Create Closure            | Closure Management  | DR-CLOSE-001    | P1       | Functional       |
| FR-CLOSE-002    | Retrieve Closures         | Closure Management  | FR-CLOSE-001    | P1       | API              |
| FR-CLOSE-003    | Remove Closure            | Closure Management  | FR-CLOSE-001    | P2       | Functional       |
| FR-CLOSE-004    | Closure-Aware Routing     | Routing             | FR-CLOSE-001    | P1       | Integration      |
| FR-RISK-001     | Risk Calculation          | Risk Engine         | DR-RISK-001     | P1       | Functional       |
| FR-RISK-002     | Risk Factors              | Risk Engine         | FR-RISK-001     | P1       | Functional       |
| FR-RISK-003     | Risk Prediction           | Risk Engine         | DR-RISK-001     | P2       | Integration      |
| FR-INC-001      | Create Incident           | Incident Management | DR-INC-001      | P1       | Functional       |
| FR-INC-002      | Retrieve Incidents        | Incident Management | FR-INC-001      | P1       | API              |
| FR-INC-003      | Incident Classification   | Incident Management | FR-INC-001      | P1       | Functional       |
| FR-REPORT-001   | Submit Report             | Reports             | FR-AUTH-003     | P1       | Functional       |
| FR-REPORT-002   | Report History            | Reports             | FR-REPORT-001   | P2       | API              |
| FR-REPORT-003   | Verify Report             | Reports             | FR-REPORT-001   | P1       | Authorization    |
| FR-REPORT-004   | Reject Report             | Reports             | FR-REPORT-001   | P1       | Authorization    |
| FR-REPORT-005   | Group Reports             | Reports             | FR-REPORT-001   | P2       | Integration      |
| FR-EMG-001      | SOS                       | Emergency           | FR-AUTH-003     | P1       | End-to-End       |
| FR-EMG-002      | Emergency Location        | Emergency           | FR-LOC-003      | P1       | Device           |
| FR-FAC-001      | Facilities                | Emergency           | DR-FAC-001      | P1       | API              |
| FR-FAC-002      | Nearest Safe Facility     | Emergency/Routing   | FR-RISK-001     | P1       | Integration      |
| FR-WARN-001     | Nearby Warnings           | Warning             | FR-INC-001      | P1       | Integration      |
| FR-WARN-002     | Warning Severity          | Warning             | FR-WARN-001     | P1       | Functional       |
| FR-WEATHER-001  | Weather                   | External Services   | INT-WEATHER-001 | P2       | Integration      |
| FR-WEATHER-002  | Weather Failure           | External Services   | FR-WEATHER-001  | P1       | Failure          |
| FR-TRAFFIC-001  | Traffic                   | External Services   | INT-TRAFFIC-001 | P2       | Integration      |
| FR-TRAFFIC-002  | Traffic Failure           | External Services   | FR-TRAFFIC-001  | P1       | Failure          |
| FR-SYNC-001     | Synchronization           | Sync                | DR-SYNC-001     | P1       | Integration      |
| FR-SYNC-002     | Cached Data               | Sync                | FR-SYNC-001     | P1       | Offline          |
| FR-SYNC-003     | Offline Routing           | Sync/Routing        | FR-ROUTE-006    | P1       | Offline          |
| SEC-AUTH-001    | Password Protection       | Security            | FR-AUTH-001     | P1       | Security         |
| SEC-AUTH-002    | Authorization             | Security            | FR-AUTH-003     | P1       | Security         |
| SEC-AUTH-003    | Token Expiration          | Security            | FR-AUTH-003     | P1       | Security         |
| SEC-DATA-001    | Secret Protection         | Security            | DEP-CONFIG-001  | P1       | Security Review  |
| SEC-DATA-002    | Client Secret Isolation   | Security            | SEC-DATA-001    | P1       | Security Review  |
| SEC-LOG-001     | Sensitive Log Protection  | Logging             | INT-LOG-001     | P1       | Security Review  |
| IF-MOB-001      | Mobile Location           | Flutter             | Android         | P1       | Device           |
| IF-MOB-002      | REST Interface            | Flutter/API         | Backend         | P1       | Integration      |
| IF-MOB-003      | Error Interface           | Flutter             | IF-MOB-002      | P1       | UI               |
| IF-API-001      | JSON Interface            | API                 | IF-MOB-002      | P1       | API              |
| INT-GEO-001     | Geoapify                  | External API        | SEC-DATA-001    | P2       | Integration      |
| INT-ROUTE-001   | GraphHopper               | External API        | SEC-DATA-001    | P2       | Integration      |
| INT-WEATHER-001 | Weather API               | External API        | SEC-DATA-001    | P2       | Integration      |
| INT-TRAFFIC-001 | Traffic API               | External API        | SEC-DATA-001    | P2       | Integration      |
| INT-LOG-001     | Application Logging       | Backend             | None            | P1       | System           |
| PER-001         | API Response Time         | Backend             | Deployment      | P1       | Performance      |
| PER-002         | Local Route Time          | Routing             | FR-ROUTE-006    | P1       | Performance      |
| PER-003         | UI Responsiveness         | Flutter             | Flutter         | P1       | Performance      |
| NFR-REL-001     | External Failure Handling | Backend             | External APIs   | P1       | Failure          |
| NFR-REL-002     | Local Fallback            | Routing             | FR-ROUTE-006    | P1       | Recovery         |
| NFR-REL-003     | Invalid API Response      | Backend             | External APIs   | P1       | Failure          |
| NFR-USE-001     | Navigation Usability      | Flutter             | UI              | P1       | Usability        |
| NFR-USE-002     | Emergency Accessibility   | Flutter             | FR-EMG-001      | P1       | Usability        |
| NFR-USE-003     | Risk Presentation         | Flutter             | FR-RISK-001     | P1       | UI               |
| NFR-MAIN-001    | Modular Backend           | Backend             | None            | P1       | Code Review      |
| NFR-MAIN-002    | Configuration Management  | Backend             | SEC-DATA-001    | P1       | Code Review      |
| DEP-CONFIG-001  | Environment Configuration | Deployment          | None            | P1       | Deployment       |
| DEP-BACKEND-001 | FastAPI Deployment        | Backend             | Backend         | P1       | Deployment       |
| DEP-MOBILE-001  | Android Deployment        | Flutter             | Flutter         | P1       | Device           |
| DEP-CONNECT-001 | ADB Reverse               | Development         | Android         | P1       | Device           |
| TEST-001        | Unit Testing              | QA                  | Code            | P1       | Test             |
| TEST-002        | API Testing               | QA                  | API             | P1       | Test             |
| TEST-003        | Integration Testing       | QA                  | System          | P1       | Test             |
| TEST-004        | Offline Testing           | QA                  | Offline         | P1       | Test             |
| TEST-005        | Failure Testing           | QA                  | System          | P1       | Test             |

---

# 33. Requirement Coverage Matrix

The following matrix maps major project objectives to technical requirements.

| Objective                 | Related Requirements                                |
| ------------------------- | --------------------------------------------------- |
| Secure user access        | FR-AUTH-001, FR-AUTH-002, FR-AUTH-003, SEC-AUTH-001 |
| Location-aware navigation | FR-LOC-001, FR-LOC-002, FR-LOC-003                  |
| Safe routing              | FR-ROUTE-001, FR-ROUTE-003, FR-ROUTE-005            |
| Multiple routing options  | FR-ROUTE-002, FR-ROUTE-004                          |
| Offline operation         | FR-ROUTE-006, FR-SYNC-002, FR-SYNC-003              |
| Online routing            | FR-ROUTE-007                                        |
| Road closure avoidance    | FR-CLOSE-001, FR-CLOSE-004                          |
| Disaster risk assessment  | FR-RISK-001, FR-RISK-002, FR-RISK-003               |
| Community participation   | FR-REPORT-001, FR-REPORT-002                        |
| Report verification       | FR-REPORT-003, FR-REPORT-004                        |
| Emergency assistance      | FR-EMG-001, FR-EMG-002                              |
| Emergency facilities      | FR-FAC-001, FR-FAC-002                              |
| Disaster warnings         | FR-WARN-001, FR-WARN-002                            |
| Weather information       | FR-WEATHER-001                                      |
| Traffic information       | FR-TRAFFIC-001                                      |
| Data synchronization      | FR-SYNC-001                                         |
| Security                  | SEC-AUTH-001 through SEC-LOG-001                    |
| External API integration  | INT-GEO-001 through INT-TRAFFIC-001                 |
| Reliability               | NFR-REL-001 through NFR-REL-003                     |
| Performance               | PER-001 through PER-003                             |
| Maintainability           | NFR-MAIN-001, NFR-MAIN-002                          |
| Android deployment        | DEP-MOBILE-001, DEP-CONNECT-001                     |

---

# 34. Acceptance and Verification Strategy

Each requirement shall be verified using one or more of the following methods:

## Inspection

Used for:

* Code structure
* Configuration
* Documentation
* Security practices

## Demonstration

Used for:

* Flutter UI
* Route visualization
* SOS
* Warning display

## Testing

Used for:

* API behavior
* Authentication
* Routing
* Risk calculation
* Offline operation

## Analysis

Used for:

* Performance
* Route cost
* Risk calculations
* Database behavior

---

# 35. Definition of Done

A requirement shall be considered complete only when:

1. Implementation is completed.
2. Required API/UI behavior is available.
3. Dependencies are functional.
4. Relevant test cases pass.
5. Error handling is implemented.
6. Security requirements are satisfied.
7. Requirement verification is documented.
8. No critical regression is introduced.

---

# 36. Technical Acceptance Baseline

The initial release shall satisfy all **P1 requirements**.

P2 requirements may be implemented as part of the complete project release depending on available external services and development resources.

P3 requirements shall be treated as future enhancements.

The final system shall demonstrate the following complete workflow:

```text
                USER
                  |
                  v
          +---------------+
          | Flutter App   |
          +-------+-------+
                  |
                  v
          +---------------+
          | Authentication|
          +-------+-------+
                  |
                  v
          +---------------+
          | Location      |
          | / Destination |
          +-------+-------+
                  |
                  v
          +---------------+
          | Routing Engine|
          +-------+-------+
                  |
        +---------+---------+
        |         |         |
        v         v         v
     Roads      Risk     Closures
        |         |         |
        +---------+---------+
                  |
                  v
          +---------------+
          | Safe Route    |
          | Recommendation|
          +-------+-------+
                  |
          +-------+-------+
          |               |
          v               v
       Warnings       Facilities
          |
          v
      Emergency/SOS
```

---

# 37. Final Technical Requirement Statement

The **Disaster Aware Routing & Emergency Management System** shall provide a secure, modular, and fault-tolerant mobile and backend platform capable of combining geographic information, road-network data, disaster risks, road closures, incidents, weather, traffic, and emergency-facility information.

The system shall prioritize safety-aware route calculation while maintaining support for normal navigation, emergency operations, community reporting, synchronization, and offline/local functionality.

All mandatory **P1 requirements** defined in this specification shall form the minimum technical baseline for the project implementation and final system validation.

---

**End of Technical Requirements Specification**
