"""Add temporal closure columns for existing installations."""
from alembic import op
import sqlalchemy as sa

revision = "0002_closure_windows"
down_revision = "0001_baseline"
branch_labels = None
depends_on = None


def upgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    columns = {column["name"] for column in inspector.get_columns("roads")}
    if "closure_start_time" not in columns:
        op.add_column("roads", sa.Column("closure_start_time", sa.DateTime(timezone=True), nullable=True))
    if "closure_end_time" not in columns:
        op.add_column("roads", sa.Column("closure_end_time", sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    op.drop_column("roads", "closure_end_time")
    op.drop_column("roads", "closure_start_time")