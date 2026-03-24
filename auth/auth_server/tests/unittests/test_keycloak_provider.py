import unittest
from unittest.mock import MagicMock, patch
import sys
import os

# Mock the Err module before importing signin
class MockErr:
    OA0012 = 'OA0012'
    OA0067 = 'OA0067'

# Create mock exception classes
class MockForbiddenException(Exception):
    def __init__(self, err_code, args):
        self.err_code = err_code

class MockWrongArgumentsException(Exception):
    def __init__(self, err_code, args):
        self.err_code = err_code

# Mock all the auth.auth_server modules before importing signin
mock_exceptions = MagicMock()
mock_exceptions.Err = MockErr
sys.modules['auth.auth_server.exceptions'] = mock_exceptions

mock_common_exc = MagicMock()
mock_common_exc.ForbiddenException = MockForbiddenException
mock_common_exc.WrongArgumentsException = MockWrongArgumentsException
sys.modules['tools.optscale_exceptions.common_exc'] = mock_common_exc

sys.modules['auth.auth_server.controllers.base'] = MagicMock()
sys.modules['auth.auth_server.controllers.base_async'] = MagicMock()
sys.modules['auth.auth_server.controllers.token'] = MagicMock()
sys.modules['auth.auth_server.controllers.user'] = MagicMock()
sys.modules['auth.auth_server.utils'] = MagicMock()
sys.modules['google.oauth2'] = MagicMock()
sys.modules['google.oauth2.id_token'] = MagicMock()
sys.modules['google.auth'] = MagicMock()
sys.modules['google.auth.transport'] = MagicMock()
sys.modules['google.auth.transport.requests'] = MagicMock()


class TestKeycloakOauth2Provider(unittest.TestCase):

    def setUp(self):
        # Set environment variables for testing
        self.env_patcher = patch.dict(os.environ, {
            'KEYCLOAK_OAUTH_CLIENT_ID': 'test-client',
            'KEYCLOAK_OAUTH_CLIENT_SECRET': 'test-secret',
            'KEYCLOAK_SERVER_URL': 'https://keycloak.example.com',
            'KEYCLOAK_REALM': 'test-realm'
        })
        self.env_patcher.start()

        # Import after mocking and setting env
        from auth.auth_server.controllers.signin import KeycloakOauth2Provider
        self.provider = KeycloakOauth2Provider()

    def tearDown(self):
        self.env_patcher.stop()

    def test_get_realm_url(self):
        """Test realm URL construction."""
        expected = 'https://keycloak.example.com/realms/test-realm'
        self.assertEqual(self.provider._get_realm_url(), expected)

    def test_extract_roles_from_realm_access(self):
        """Test role extraction from realm_access claim."""
        decoded_token = {
            'realm_access': {
                'roles': ['optscale-admin', 'user']
            }
        }
        roles = self.provider._extract_roles(decoded_token)
        self.assertIn('optscale-admin', roles)
        self.assertIn('user', roles)

    def test_extract_roles_from_resource_access(self):
        """Test role extraction from resource_access claim."""
        decoded_token = {
            'resource_access': {
                'test-client': {
                    'roles': ['optscale-engineer']
                }
            }
        }
        roles = self.provider._extract_roles(decoded_token)
        self.assertIn('optscale-engineer', roles)

    def test_extract_roles_from_groups(self):
        """Test role extraction from groups claim."""
        decoded_token = {
            'groups': ['/optscale-member', '/admin/super']
        }
        roles = self.provider._extract_roles(decoded_token)
        self.assertIn('optscale-member', roles)
        self.assertIn('admin/super', roles)

    def test_extract_roles_combined(self):
        """Test role extraction from all sources combined."""
        decoded_token = {
            'realm_access': {
                'roles': ['role1']
            },
            'resource_access': {
                'test-client': {
                    'roles': ['role2']
                }
            },
            'groups': ['/role3']
        }
        roles = self.provider._extract_roles(decoded_token)
        self.assertIn('role1', roles)
        self.assertIn('role2', roles)
        self.assertIn('role3', roles)

    def test_extract_roles_empty_token(self):
        """Test role extraction from empty token."""
        decoded_token = {}
        roles = self.provider._extract_roles(decoded_token)
        self.assertEqual(roles, [])

    def test_extract_roles_deduplication(self):
        """Test that duplicate roles are deduplicated."""
        decoded_token = {
            'realm_access': {
                'roles': ['admin', 'admin']
            },
            'groups': ['/admin']
        }
        roles = self.provider._extract_roles(decoded_token)
        # Count occurrences of 'admin'
        admin_count = sum(1 for r in roles if r == 'admin')
        self.assertEqual(admin_count, 1)

    def test_client_id(self):
        """Test client_id returns configured value."""
        self.assertEqual(self.provider.client_id(), 'test-client')

    def test_server_url_strips_trailing_slash(self):
        """Test server_url strips trailing slash."""
        with patch.dict(os.environ, {
            'KEYCLOAK_OAUTH_CLIENT_ID': 'test-client',
            'KEYCLOAK_OAUTH_CLIENT_SECRET': 'test-secret',
            'KEYCLOAK_SERVER_URL': 'https://keycloak.example.com/',
            'KEYCLOAK_REALM': 'test-realm'
        }):
            from auth.auth_server.controllers.signin import KeycloakOauth2Provider
            provider = KeycloakOauth2Provider()
            self.assertEqual(provider.server_url(), 'https://keycloak.example.com')

    def test_realm(self):
        """Test realm returns configured value."""
        self.assertEqual(self.provider.realm(), 'test-realm')


class TestKeycloakOauth2ProviderNoConfig(unittest.TestCase):

    def test_client_id_raises_when_not_configured(self):
        """Test client_id raises ForbiddenException when not configured."""
        with patch.dict(os.environ, {
            'KEYCLOAK_OAUTH_CLIENT_ID': '',
            'KEYCLOAK_OAUTH_CLIENT_SECRET': '',
            'KEYCLOAK_SERVER_URL': '',
            'KEYCLOAK_REALM': ''
        }, clear=True):
            from auth.auth_server.controllers.signin import KeycloakOauth2Provider
            provider = KeycloakOauth2Provider()
            with self.assertRaises(MockForbiddenException):
                provider.client_id()

    def test_client_secret_raises_when_not_configured(self):
        """Test client_secret raises ForbiddenException when not configured."""
        with patch.dict(os.environ, {
            'KEYCLOAK_OAUTH_CLIENT_ID': '',
            'KEYCLOAK_OAUTH_CLIENT_SECRET': '',
            'KEYCLOAK_SERVER_URL': '',
            'KEYCLOAK_REALM': ''
        }, clear=True):
            from auth.auth_server.controllers.signin import KeycloakOauth2Provider
            provider = KeycloakOauth2Provider()
            with self.assertRaises(MockForbiddenException):
                provider.client_secret()


if __name__ == '__main__':
    unittest.main()
