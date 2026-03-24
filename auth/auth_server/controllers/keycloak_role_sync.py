import logging
from sqlalchemy import and_

from auth.auth_server.models.models import Role, RolePurpose, Assignment, Type

LOG = logging.getLogger(__name__)


class KeycloakRoleSyncService:
    """
    Service for synchronizing Keycloak roles/groups to OptScale roles.

    Role mapping (highest priority first):
    - optscale-admin, optscale-manager -> RolePurpose.optscale_manager
    - optscale-engineer -> RolePurpose.optscale_engineer
    - optscale-member (or any other) -> RolePurpose.optscale_member
    """

    ROLE_PRIORITY = {
        RolePurpose.optscale_manager: 3,
        RolePurpose.optscale_engineer: 2,
        RolePurpose.optscale_member: 1,
    }

    KEYCLOAK_ROLE_MAPPING = {
        'optscale-admin': RolePurpose.optscale_manager,
        'optscale-manager': RolePurpose.optscale_manager,
        'optscale-engineer': RolePurpose.optscale_engineer,
        'optscale-member': RolePurpose.optscale_member,
    }

    def __init__(self, db_session, config=None):
        self._session = db_session
        self._config = config

    def _map_to_optscale_role(self, keycloak_roles):
        """
        Map Keycloak roles to OptScale role purpose.
        Returns the highest privilege role from the list.
        """
        if not keycloak_roles:
            return RolePurpose.optscale_member

        matched_purposes = []
        for role in keycloak_roles:
            role_lower = role.lower()
            if role_lower in self.KEYCLOAK_ROLE_MAPPING:
                matched_purposes.append(self.KEYCLOAK_ROLE_MAPPING[role_lower])

        if not matched_purposes:
            return RolePurpose.optscale_member

        return max(matched_purposes, key=lambda p: self.ROLE_PRIORITY.get(p, 0))

    def _get_role_by_purpose(self, purpose):
        """Get the OptScale role by purpose."""
        role = self._session.query(Role).filter(
            and_(
                Role.deleted.is_(False),
                Role.purpose == purpose
            )
        ).first()
        return role

    def _get_organization_type(self):
        """Get the organization type for assignments."""
        org_type = self._session.query(Type).filter(
            and_(
                Type.deleted.is_(False),
                Type.name == 'organization'
            )
        ).first()
        return org_type

    def _get_existing_assignment(self, user, role, org_type):
        """Check if user already has this role assignment."""
        assignment = self._session.query(Assignment).filter(
            and_(
                Assignment.deleted.is_(False),
                Assignment.user_id == user.id,
                Assignment.role_id == role.id,
                Assignment.type_id == org_type.id
            )
        ).first()
        return assignment

    def _get_user_role_assignments(self, user):
        """Get all role assignments for a user with purpose-based roles."""
        assignments = self._session.query(Assignment).join(Role).filter(
            and_(
                Assignment.deleted.is_(False),
                Assignment.user_id == user.id,
                Role.purpose.isnot(None)
            )
        ).all()
        return assignments

    def sync_roles(self, user, keycloak_roles):
        """
        Synchronize Keycloak roles to OptScale for the given user.
        This is called on each login to ensure roles stay in sync.
        """
        if not keycloak_roles:
            LOG.debug("No Keycloak roles to sync for user %s", user.email)
            return

        target_purpose = self._map_to_optscale_role(keycloak_roles)
        target_role = self._get_role_by_purpose(target_purpose)

        if not target_role:
            LOG.warning(
                "No OptScale role found for purpose %s, skipping role sync",
                target_purpose
            )
            return

        org_type = self._get_organization_type()
        if not org_type:
            LOG.warning("Organization type not found, skipping role sync")
            return

        existing_assignment = self._get_existing_assignment(
            user, target_role, org_type)

        if existing_assignment:
            LOG.debug(
                "User %s already has role %s assigned",
                user.email, target_role.name
            )
            return

        LOG.info(
            "Creating role assignment for user %s: role=%s (purpose=%s)",
            user.email, target_role.name, target_purpose
        )

        assignment = Assignment(
            user=user,
            role=target_role,
            type_=org_type,
            resource_id=None
        )
        self._session.add(assignment)
        self._session.flush()

        LOG.info(
            "Role sync completed for user %s with role %s",
            user.email, target_role.name
        )
