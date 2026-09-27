"""Increase audit log reference length.

Revision ID: 0008_audit_log_reference
Revises: 0007_report_photo_data
"""

from alembic import op
import sqlalchemy as sa


revision = "0008_audit_log_reference"
down_revision = "0007_report_photo_data"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.alter_column(
        "audit_logs",
        "road_id",
        existing_type=sa.String(length=32),
        type_=sa.String(length=64),
        existing_nullable=True,
    )


def downgrade() -> None:
    op.alter_column(
        "audit_logs",
        "road_id",
        existing_type=sa.String(length=64),
        type_=sa.String(length=32),
        existing_nullable=True,
    )