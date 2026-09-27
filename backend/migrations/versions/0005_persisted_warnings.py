"""Add persisted authority warnings."""
from alembic import op
import sqlalchemy as sa

revision = "0005_persisted_warnings"
down_revision = "0004_sync_state_and_sos"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    if "warnings" not in sa.inspect(bind).get_table_names():
        op.create_table(
            "warnings",
            sa.Column("id", sa.String(64), primary_key=True),
            sa.Column("title", sa.String(120), nullable=False),
            sa.Column("description", sa.String(500), nullable=False),
            sa.Column("lat", sa.Float, nullable=False),
            sa.Column("lon", sa.Float, nullable=False),
            sa.Column("radius_km", sa.Float, nullable=False),
            sa.Column("severity", sa.String(16), nullable=False),
            sa.Column("status", sa.String(16), nullable=False),
            sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("source", sa.String(120), nullable=False),
        )


def downgrade() -> None:
    op.drop_table("warnings")
