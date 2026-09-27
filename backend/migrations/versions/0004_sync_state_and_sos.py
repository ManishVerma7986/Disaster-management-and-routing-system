"""Add synchronization versioning and persisted SOS events."""
from alembic import op
import sqlalchemy as sa

revision = "0004_sync_state_and_sos"
down_revision = "0003_incidents_facilities"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    tables = set(sa.inspect(bind).get_table_names())
    if "sync_state" not in tables:
        op.create_table(
            "sync_state",
            sa.Column("key", sa.String(32), primary_key=True),
            sa.Column("version", sa.Integer, nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        )
    if "sos_events" not in tables:
        op.create_table(
            "sos_events",
            sa.Column("id", sa.String(64), primary_key=True),
            sa.Column("user_id", sa.String(64), nullable=False),
            sa.Column("lat", sa.Float, nullable=False),
            sa.Column("lon", sa.Float, nullable=False),
            sa.Column("message", sa.String(300), nullable=False),
            sa.Column("status", sa.String(32), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        )
        op.create_index("sos_events_user_id_idx", "sos_events", ["user_id"])


def downgrade() -> None:
    op.drop_index("sos_events_user_id_idx", table_name="sos_events")
    op.drop_table("sos_events")
    op.drop_table("sync_state")
