# Architecture Notes

## Current vertical slice

The FastAPI app exposes authentication, routing, closure, report, audit, and synchronization endpoints. The routing service builds a directed graph from seeded road segments and uses a heap-based shortest-path search. Each edge cost is composed from configured travel time, flood penalty, landslide penalty, and confidence uncertainty. An active closure returns infinite cost and is therefore never enqueued.

## Production boundary

The current seed provider is deliberately replaceable. The target persistence layer is PostgreSQL/PostGIS, with spatial indexes for roads and reports. Provider interfaces should be added before integrating live weather, rainfall, authority feeds, or OSM ingestion. OSM supplies base geography; it does not supply current disaster conditions.

## Data trust

The API labels responses as `PRODUCTION`. Reports begin as `PENDING`; only authority review should promote them into official incidents or closure changes. Offline clients must show synchronization time and stale-data status.
