"""Add persistent incident, facility, and weather tables."""
from alembic import op
import sqlalchemy as sa

revision = "0003_incidents_facilities"
down_revision = "0002_closure_windows"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    tables = set(inspector.get_table_names())
    if "incidents" not in tables:
        op.create_table("incidents", sa.Column("id", sa.String(64), primary_key=True), sa.Column("type", sa.String(40), nullable=False), sa.Column("lat", sa.Float, nullable=False), sa.Column("lon", sa.Float, nullable=False), sa.Column("severity", sa.String(16), nullable=False), sa.Column("status", sa.String(16), nullable=False), sa.Column("confidence", sa.Integer, nullable=False), sa.Column("report_ids", sa.JSON, nullable=False), sa.Column("source", sa.String(120), nullable=False), sa.Column("created_at", sa.DateTime(timezone=True), nullable=False))
    if "emergency_facilities" not in tables:
        op.create_table("emergency_facilities", sa.Column("id", sa.String(64), primary_key=True), sa.Column("name", sa.String(160), nullable=False), sa.Column("type", sa.String(40), nullable=False), sa.Column("lat", sa.Float, nullable=False), sa.Column("lon", sa.Float, nullable=False), sa.Column("risk_level", sa.String(16), nullable=False), sa.Column("contact", sa.String(64), nullable=False), sa.Column("source", sa.String(120), nullable=False))
    if "weather_readings" not in tables:
        op.create_table("weather_readings", sa.Column("id", sa.Integer, primary_key=True, autoincrement=True), sa.Column("lat", sa.Float, nullable=False), sa.Column("lon", sa.Float, nullable=False), sa.Column("rainfall_mm", sa.Float, nullable=False), sa.Column("condition", sa.String(120), nullable=False), sa.Column("source", sa.String(120), nullable=False), sa.Column("is_demo", sa.Boolean, nullable=False), sa.Column("observed_at", sa.DateTime(timezone=True), nullable=False))
    if "device_tokens" not in tables:
        op.create_table("device_tokens", sa.Column("token", sa.String(4096), primary_key=True), sa.Column("user_id", sa.String(64), nullable=False), sa.Column("platform", sa.String(20), nullable=False), sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False))
    if bind.dialect.name == "postgresql":
        op.execute("CREATE EXTENSION IF NOT EXISTS postgis")
        op.execute("ALTER TABLE incidents ADD COLUMN IF NOT EXISTS geometry geometry(Point, 4326) GENERATED ALWAYS AS (ST_SetSRID(ST_MakePoint(lon, lat), 4326)) STORED")
        op.execute("ALTER TABLE emergency_facilities ADD COLUMN IF NOT EXISTS geometry geometry(Point, 4326) GENERATED ALWAYS AS (ST_SetSRID(ST_MakePoint(lon, lat), 4326)) STORED")
        op.execute("ALTER TABLE weather_readings ADD COLUMN IF NOT EXISTS geometry geometry(Point, 4326) GENERATED ALWAYS AS (ST_SetSRID(ST_MakePoint(lon, lat), 4326)) STORED")
        op.execute("CREATE INDEX IF NOT EXISTS incidents_geometry_idx ON incidents USING GIST (geometry)")
        op.execute("CREATE INDEX IF NOT EXISTS facilities_geometry_idx ON emergency_facilities USING GIST (geometry)")
        op.execute("CREATE INDEX IF NOT EXISTS weather_geometry_idx ON weather_readings USING GIST (geometry)")


def downgrade() -> None:
    op.drop_table("weather_readings")
    op.drop_table("device_tokens")
    op.drop_table("emergency_facilities")
    op.drop_table("incidents")
