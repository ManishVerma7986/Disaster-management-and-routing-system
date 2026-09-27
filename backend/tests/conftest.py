import pytest

from backend.app.models import Role, User
from backend.app.security import hash_password
from backend.app.storage import get_user_by_email, save_user


@pytest.fixture(scope="session", autouse=True)
def provision_test_accounts():
    accounts = (
        User(id="test-user", name="Test User", email="test.user@example.com", password_hash=hash_password("TestUser123!"), role=Role.USER),
        User(id="test-authority", name="Test Authority", email="test.authority@example.com", password_hash=hash_password("TestAuthority123!"), role=Role.AUTHORITY),
    )
    for account in accounts:
        if not get_user_by_email(account.email):
            save_user(account)