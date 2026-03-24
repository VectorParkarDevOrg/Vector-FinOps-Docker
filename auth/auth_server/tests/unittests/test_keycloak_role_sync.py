import unittest
from unittest.mock import MagicMock, patch, PropertyMock
import sys

# Mock sqlalchemy before importing
sys.modules['sqlalchemy'] = MagicMock()

# Mock the auth module dependencies before importing
sys.modules['auth.auth_server.models.models'] = MagicMock()

# Create mock RolePurpose enum
class MockRolePurpose:
    optscale_member = 'optscale_member'
    optscale_engineer = 'optscale_engineer'
    optscale_manager = 'optscale_manager'


# Patch RolePurpose in the models mock
sys.modules['auth.auth_server.models.models'].RolePurpose = MockRolePurpose


class TestKeycloakRoleSyncService(unittest.TestCase):

    def setUp(self):
        # Import after mocking
        from auth.auth_server.controllers.keycloak_role_sync import KeycloakRoleSyncService
        self.mock_session = MagicMock()
        self.service = KeycloakRoleSyncService(self.mock_session)

    def test_map_to_optscale_role_admin(self):
        """Test that optscale-admin maps to manager role."""
        roles = ['optscale-admin']
        result = self.service._map_to_optscale_role(roles)
        self.assertEqual(result, MockRolePurpose.optscale_manager)

    def test_map_to_optscale_role_manager(self):
        """Test that optscale-manager maps to manager role."""
        roles = ['optscale-manager']
        result = self.service._map_to_optscale_role(roles)
        self.assertEqual(result, MockRolePurpose.optscale_manager)

    def test_map_to_optscale_role_engineer(self):
        """Test that optscale-engineer maps to engineer role."""
        roles = ['optscale-engineer']
        result = self.service._map_to_optscale_role(roles)
        self.assertEqual(result, MockRolePurpose.optscale_engineer)

    def test_map_to_optscale_role_member(self):
        """Test that optscale-member maps to member role."""
        roles = ['optscale-member']
        result = self.service._map_to_optscale_role(roles)
        self.assertEqual(result, MockRolePurpose.optscale_member)

    def test_map_to_optscale_role_highest_privilege(self):
        """Test that highest privilege role is selected when user has multiple."""
        roles = ['optscale-member', 'optscale-engineer', 'optscale-admin']
        result = self.service._map_to_optscale_role(roles)
        self.assertEqual(result, MockRolePurpose.optscale_manager)

    def test_map_to_optscale_role_unknown_defaults_to_member(self):
        """Test that unknown roles default to member."""
        roles = ['unknown-role', 'some-other-role']
        result = self.service._map_to_optscale_role(roles)
        self.assertEqual(result, MockRolePurpose.optscale_member)

    def test_map_to_optscale_role_empty_list_defaults_to_member(self):
        """Test that empty role list defaults to member."""
        roles = []
        result = self.service._map_to_optscale_role(roles)
        self.assertEqual(result, MockRolePurpose.optscale_member)

    def test_map_to_optscale_role_none_defaults_to_member(self):
        """Test that None defaults to member."""
        result = self.service._map_to_optscale_role(None)
        self.assertEqual(result, MockRolePurpose.optscale_member)

    def test_map_to_optscale_role_case_insensitive(self):
        """Test that role mapping is case insensitive."""
        roles = ['OPTSCALE-ADMIN']
        result = self.service._map_to_optscale_role(roles)
        self.assertEqual(result, MockRolePurpose.optscale_manager)

        roles = ['OptScale-Engineer']
        result = self.service._map_to_optscale_role(roles)
        self.assertEqual(result, MockRolePurpose.optscale_engineer)

    def test_map_to_optscale_role_mixed_roles(self):
        """Test with mix of known and unknown roles."""
        roles = ['unknown', 'optscale-engineer', 'another-unknown']
        result = self.service._map_to_optscale_role(roles)
        self.assertEqual(result, MockRolePurpose.optscale_engineer)


if __name__ == '__main__':
    unittest.main()
