"""Add optional photo evidence to hazard reports."""

from alembic import op
import sqlalchemy as sa

revision = "0007_report_photo_data"
down_revision = "0006_report_client_ids"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    columns = {column["name"] for column in sa.inspect(bind).get_columns("reports")}
    if "photo_data" not in columns:
        op.add_column("reports", sa.Column("photo_data", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("reports", "photo_data")