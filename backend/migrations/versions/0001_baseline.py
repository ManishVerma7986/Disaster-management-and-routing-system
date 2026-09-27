"""Create the initial application tables on a fresh database."""
from alembic import op
import sqlalchemy as sa

revision = "0001_baseline"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Keeping this migration executable is important: a new database must not
    # depend on the FastAPI application having been started first.
    op.create_table(
        "roads",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("start_node", sa.String(64), nullable=False),
        sa.Column("end_node", sa.String(64), nullable=False),
        sa.Column("distance_km", sa.Float, nullable=False),
        sa.Column("travel_time_minutes", sa.Float, nullable=False),
        sa.Column("flood_risk", sa.String(16), nullable=False),
        sa.Column("landslide_risk", sa.String(16), nullable=False),
        sa.Column("confidence", sa.Integer, nullable=False),
        sa.Column("geometry", sa.JSON, nullable=False),
        sa.Column("closure_reason", sa.Text, nullable=True),
        sa.Column("closure_severity", sa.String(16), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        if_not_exists=True,
    )
    op.create_table(
        "users",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("email", sa.String(255), nullable=False, unique=True),
        sa.Column("password_hash", sa.Text, nullable=False),
        sa.Column("role", sa.String(16), nullable=False),
        if_not_exists=True,
    )
    op.create_index("ix_users_email", "users", ["email"], if_not_exists=True)
    op.create_table(
        "reports",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("user_id", sa.String(64), nullable=False),
        sa.Column("problem_type", sa.String(40), nullable=False),
        sa.Column("lat", sa.Float, nullable=False),
        sa.Column("lon", sa.Float, nullable=False),
        sa.Column("description", sa.Text, nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("confidence", sa.Integer, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        if_not_exists=True,
    )
    op.create_table(
        "audit_logs",
        sa.Column("id", sa.Integer, primary_key=True, autoincrement=True),
        sa.Column("actor", sa.String(255), nullable=False),
        sa.Column("action", sa.String(64), nullable=False),
        sa.Column("road_id", sa.String(32), nullable=False),
        sa.Column("reason", sa.Text, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        if_not_exists=True,
    )


def downgrade() -> None:
    op.drop_table("audit_logs")
    op.drop_table("reports")
    op.drop_index("ix_users_email", table_name="users")
    op.drop_table("users")
    op.drop_table("roads")
