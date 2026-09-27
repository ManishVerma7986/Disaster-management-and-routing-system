CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TYPE risk_level AS ENUM ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL');

CREATE TABLE users (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'USER' CHECK (role IN ('USER', 'AUTHORITY', 'ADMIN')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE roads (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    start_node TEXT NOT NULL,
    end_node TEXT NOT NULL,
    distance_km DOUBLE PRECISION NOT NULL CHECK (distance_km > 0),
    travel_time_minutes DOUBLE PRECISION NOT NULL CHECK (travel_time_minutes > 0),
    flood_risk TEXT NOT NULL CHECK (flood_risk IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    landslide_risk TEXT NOT NULL CHECK (landslide_risk IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    confidence SMALLINT NOT NULL CHECK (confidence BETWEEN 0 AND 100),
    geometry JSONB NOT NULL,
    closure_reason TEXT,
    closure_severity TEXT CHECK (closure_severity IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    closure_start_time TIMESTAMPTZ,
    closure_end_time TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE reports (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id),
    problem_type TEXT NOT NULL,
    lat DOUBLE PRECISION NOT NULL,
    lon DOUBLE PRECISION NOT NULL,
    description TEXT NOT NULL,
    photo_data TEXT,
    status TEXT NOT NULL DEFAULT 'PENDING',
    confidence SMALLINT NOT NULL DEFAULT 50 CHECK (confidence BETWEEN 0 AND 100),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE audit_logs (
    id BIGSERIAL PRIMARY KEY,
    actor TEXT NOT NULL,
    action TEXT NOT NULL,
    road_id TEXT,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE incidents (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    lat DOUBLE PRECISION NOT NULL CHECK (lat BETWEEN -90 AND 90),
    lon DOUBLE PRECISION NOT NULL CHECK (lon BETWEEN -180 AND 180),
    geometry geometry(Point, 4326) GENERATED ALWAYS AS (ST_SetSRID(ST_MakePoint(lon, lat), 4326)) STORED,
    severity TEXT NOT NULL CHECK (severity IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    status TEXT NOT NULL DEFAULT 'ACTIVE',
    confidence SMALLINT NOT NULL CHECK (confidence BETWEEN 0 AND 100),
    report_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
    source TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX incidents_location_idx ON incidents USING GIST (geometry);

CREATE TABLE emergency_facilities (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    lat DOUBLE PRECISION NOT NULL CHECK (lat BETWEEN -90 AND 90),
    lon DOUBLE PRECISION NOT NULL CHECK (lon BETWEEN -180 AND 180),
    geometry geometry(Point, 4326) GENERATED ALWAYS AS (ST_SetSRID(ST_MakePoint(lon, lat), 4326)) STORED,
    risk_level TEXT NOT NULL CHECK (risk_level IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    contact TEXT NOT NULL,
    source TEXT NOT NULL DEFAULT 'AUTHORITY'
);
CREATE INDEX emergency_facilities_location_idx ON emergency_facilities USING GIST (geometry);

CREATE TABLE weather_readings (
    id BIGSERIAL PRIMARY KEY,
    lat DOUBLE PRECISION NOT NULL CHECK (lat BETWEEN -90 AND 90),
    lon DOUBLE PRECISION NOT NULL CHECK (lon BETWEEN -180 AND 180),
    geometry geometry(Point, 4326) GENERATED ALWAYS AS (ST_SetSRID(ST_MakePoint(lon, lat), 4326)) STORED,
    rainfall_mm DOUBLE PRECISION NOT NULL,
    condition TEXT NOT NULL,
    source TEXT NOT NULL,
    observed_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX weather_readings_location_idx ON weather_readings USING GIST (geometry);

CREATE TABLE device_tokens (
    token TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id),
    platform TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX roads_geometry_idx ON roads USING GIN (geometry);
