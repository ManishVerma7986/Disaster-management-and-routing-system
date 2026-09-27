"""Add idempotency keys for offline report synchronization."""
from alembic import op
import sqlalchemy as sa

revision = "0006_report_client_ids"
down_revision = "0005_persisted_warnings"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    columns = {column["name"] for column in sa.inspect(bind).get_columns("reports")}
    if "client_id" not in columns:
        op.add_column("reports", sa.Column("client_id", sa.String(100), nullable=True))
        op.create_index("ix_reports_client_id", "reports", ["client_id"], unique=True)


def downgrade() -> None:
    op.drop_index("ix_reports_client_id", table_name="reports")
    op.drop_column("reports", "client_id")