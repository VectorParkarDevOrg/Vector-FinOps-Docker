#!/bin/bash

#===============================================================================
# Keycloak Integration Setup Script for OptScale
#===============================================================================
# This script sets up Keycloak SSO integration with OptScale.
# Run this script from the OptScale root directory after cloning from GitHub.
#
# Usage: ./scripts/setup_keycloak_integration.sh
#===============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_header() {
    echo -e "\n${BLUE}=================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=================================================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

#===============================================================================
# Check prerequisites
#===============================================================================
print_header "Checking Prerequisites"

# Check if we're in the OptScale directory
if [ ! -f "optscale-deploy/overlay/user_template.yml" ]; then
    print_error "This script must be run from the OptScale root directory"
    print_info "Expected to find: optscale-deploy/overlay/user_template.yml"
    exit 1
fi

print_success "Running from OptScale root directory"

# Check required directories exist
for dir in "auth/auth_server/controllers" "ngui/ui/src/components" "ngui/ui/src/containers" "ngui/ui/src/pages" "ngui/ui/src/icons" "ngui/ui/src/utils/routes"; do
    if [ ! -d "$dir" ]; then
        print_error "Directory not found: $dir"
        exit 1
    fi
done

print_success "All required directories exist"

#===============================================================================
# Gather configuration from user
#===============================================================================
print_header "Keycloak Configuration"

echo "Please provide your Keycloak configuration details:"
echo ""

# Keycloak Server URL
read -p "Keycloak Server URL (e.g., https://keycloak.example.com): " KEYCLOAK_URL
while [ -z "$KEYCLOAK_URL" ]; do
    print_warning "Keycloak URL is required"
    read -p "Keycloak Server URL: " KEYCLOAK_URL
done
# Remove trailing slash
KEYCLOAK_URL="${KEYCLOAK_URL%/}"

# Keycloak Realm
read -p "Keycloak Realm Name (e.g., master): " KEYCLOAK_REALM
while [ -z "$KEYCLOAK_REALM" ]; do
    print_warning "Keycloak Realm is required"
    read -p "Keycloak Realm Name: " KEYCLOAK_REALM
done

# Keycloak Client ID
read -p "Keycloak Client ID (e.g., optscale): " KEYCLOAK_CLIENT_ID
while [ -z "$KEYCLOAK_CLIENT_ID" ]; do
    print_warning "Keycloak Client ID is required"
    read -p "Keycloak Client ID: " KEYCLOAK_CLIENT_ID
done

# Keycloak Client Secret
read -sp "Keycloak Client Secret: " KEYCLOAK_CLIENT_SECRET
echo ""
while [ -z "$KEYCLOAK_CLIENT_SECRET" ]; do
    print_warning "Keycloak Client Secret is required"
    read -sp "Keycloak Client Secret: " KEYCLOAK_CLIENT_SECRET
    echo ""
done

# OptScale URL
read -p "OptScale URL (e.g., https://optscale.example.com): " OPTSCALE_URL
while [ -z "$OPTSCALE_URL" ]; do
    print_warning "OptScale URL is required"
    read -p "OptScale URL: " OPTSCALE_URL
done
# Remove trailing slash
OPTSCALE_URL="${OPTSCALE_URL%/}"

echo ""
print_header "Configuration Summary"
echo "Keycloak URL:      $KEYCLOAK_URL"
echo "Keycloak Realm:    $KEYCLOAK_REALM"
echo "Keycloak Client:   $KEYCLOAK_CLIENT_ID"
echo "Keycloak Secret:   ********"
echo "OptScale URL:      $OPTSCALE_URL"
echo "Callback URL:      $OPTSCALE_URL/keycloak-callback"
echo ""

read -p "Is this correct? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    print_warning "Setup cancelled. Please run the script again."
    exit 0
fi

#===============================================================================
# Create backend files
#===============================================================================
print_header "Creating Backend Files"

# 1. Create keycloak_role_sync.py
print_info "Creating auth/auth_server/controllers/keycloak_role_sync.py..."

cat > auth/auth_server/controllers/keycloak_role_sync.py << 'KEYCLOAK_ROLE_SYNC_EOF'
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
KEYCLOAK_ROLE_SYNC_EOF

print_success "Created keycloak_role_sync.py"

# 2. Modify signin.py
print_info "Modifying auth/auth_server/controllers/signin.py..."

# Backup original file
cp auth/auth_server/controllers/signin.py auth/auth_server/controllers/signin.py.backup

# Create the modified signin.py
python3 << 'PYTHON_SIGNIN_EOF'
import re

with open('auth/auth_server/controllers/signin.py', 'r') as f:
    content = f.read()

# Add imports
if 'import time' not in content:
    content = content.replace(
        'from urllib.parse import urlencode',
        'import time\nfrom urllib.parse import urlencode'
    )

if 'from requests.exceptions import' not in content:
    content = content.replace(
        'import requests',
        'import requests\nfrom requests.exceptions import ConnectionError, Timeout'
    )

# Add KeycloakVerifyTokenError exception if not exists
if 'class KeycloakVerifyTokenError' not in content:
    content = content.replace(
        'class AzureVerifyTokenError(Exception):',
        '''class AzureVerifyTokenError(Exception):
    pass


class KeycloakVerifyTokenError(Exception):'''
    )

# Add KeycloakOauth2Provider class if not exists
if 'class KeycloakOauth2Provider' not in content:
    keycloak_provider = '''

class KeycloakOauth2Provider:
    TOKEN_ENDPOINT_PATH = '/protocol/openid-connect/token'
    CERTS_ENDPOINT_PATH = '/protocol/openid-connect/certs'
    MAX_RETRIES = 3
    RETRY_BACKOFF = 0.5

    def __init__(self):
        self._client_id = os.environ.get('KEYCLOAK_OAUTH_CLIENT_ID')
        self._client_secret = os.environ.get('KEYCLOAK_OAUTH_CLIENT_SECRET')
        self._server_url = os.environ.get('KEYCLOAK_SERVER_URL')
        self._realm = os.environ.get('KEYCLOAK_REALM')

    def _request_with_retry(self, method, url, max_retries=None, **kwargs):
        """Execute HTTP request with retry logic for transient failures."""
        max_retries = max_retries or self.MAX_RETRIES
        kwargs.setdefault('timeout', 30)
        last_exception = None

        for attempt in range(max_retries):
            try:
                if method == 'GET':
                    resp = requests.get(url, **kwargs)
                elif method == 'POST':
                    resp = requests.post(url, **kwargs)
                else:
                    raise ValueError(f'Unsupported HTTP method: {method}')

                if resp.status_code >= 500:
                    LOG.warning(
                        "Keycloak server error (attempt %d/%d): %s %s",
                        attempt + 1, max_retries, resp.status_code, url
                    )
                    if attempt < max_retries - 1:
                        time.sleep(self.RETRY_BACKOFF * (2 ** attempt))
                        continue
                return resp

            except (ConnectionError, Timeout) as e:
                last_exception = e
                LOG.warning(
                    "Keycloak connection error (attempt %d/%d): %s - %s",
                    attempt + 1, max_retries, url, str(e)
                )
                if attempt < max_retries - 1:
                    time.sleep(self.RETRY_BACKOFF * (2 ** attempt))
                    continue

        if last_exception:
            raise KeycloakVerifyTokenError(
                f'Failed to connect to Keycloak after {max_retries} attempts: '
                f'{str(last_exception)}'
            )
        return resp

    def client_id(self):
        if not self._client_id:
            raise ForbiddenException(Err.OA0012, [])
        return self._client_id

    def client_secret(self):
        if not self._client_secret:
            raise ForbiddenException(Err.OA0012, [])
        return self._client_secret

    def server_url(self):
        if not self._server_url:
            raise ForbiddenException(Err.OA0012, [])
        return self._server_url.rstrip('/')

    def realm(self):
        if not self._realm:
            raise ForbiddenException(Err.OA0012, [])
        return self._realm

    def _get_realm_url(self):
        return f"{self.server_url()}/realms/{self.realm()}"

    def ensure_bytes(self, key):
        if isinstance(key, str):
            key = key.encode('utf-8')
        return key

    def decode_value(self, val):
        decoded = base64.urlsafe_b64decode(self.ensure_bytes(val) + b'==')
        return int.from_bytes(decoded, 'big')

    def rsa_pem_from_jwk(self, jwk):
        return RSAPublicNumbers(
            n=self.decode_value(jwk['n']),
            e=self.decode_value(jwk['e'])
        ).public_key(default_backend()).public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo
        )

    def exchange_code_for_token(self, code, redirect_uri, code_verifier=None):
        token_url = f"{self._get_realm_url()}{self.TOKEN_ENDPOINT_PATH}"
        request_body = {
            'grant_type': 'authorization_code',
            'client_id': self.client_id(),
            'client_secret': self.client_secret(),
            'code': code,
            'redirect_uri': redirect_uri,
        }
        if code_verifier:
            request_body['code_verifier'] = code_verifier

        LOG.debug("Exchanging authorization code for token with Keycloak")
        resp = self._request_with_retry('POST', token_url, data=request_body)
        if not resp.ok:
            error_msg = resp.text[:500] if resp.text else 'Unknown error'
            LOG.error(
                "Keycloak token exchange failed: status=%s, error=%s",
                resp.status_code, error_msg
            )
            raise KeycloakVerifyTokenError(
                f'Token exchange failed: {resp.status_code}')
        try:
            return resp.json()
        except (ValueError, TypeError, KeyError) as e:
            LOG.error("Failed to parse Keycloak token response: %s", str(e))
            raise KeycloakVerifyTokenError(
                'Received malformed token response from Keycloak')

    def get_jwks(self):
        certs_url = f"{self._get_realm_url()}{self.CERTS_ENDPOINT_PATH}"
        LOG.debug("Fetching JWKS from Keycloak: %s", certs_url)
        resp = self._request_with_retry('GET', certs_url)
        if not resp.ok:
            LOG.error(
                "Failed to fetch Keycloak JWKS: status=%s", resp.status_code
            )
            raise KeycloakVerifyTokenError(
                f'Failed to fetch JWKS: {resp.status_code}')
        try:
            return resp.json()
        except (ValueError, TypeError, KeyError) as e:
            LOG.error("Failed to parse Keycloak JWKS response: %s", str(e))
            raise KeycloakVerifyTokenError(
                'Received malformed JWKS response from Keycloak')

    def get_token_info(self, token):
        headers = jwt.get_unverified_header(token)
        if not headers:
            raise InvalidAuthorizationToken('missing headers')
        try:
            return headers['kid'], headers['alg']
        except KeyError:
            raise InvalidAuthorizationToken(f'invalid headers: {headers}')

    def get_jwk(self, kid, jwks):
        keys = jwks.get('keys')
        if not isinstance(keys, list):
            raise KeycloakVerifyTokenError(f'Invalid jwks: {jwks}')
        for jwk in keys:
            if jwk.get('kid') == kid:
                return jwk
        raise InvalidAuthorizationToken('kid not recognized')

    def get_public_key(self, kid, jwks):
        jwk = self.get_jwk(kid, jwks)
        return self.rsa_pem_from_jwk(jwk)

    def _extract_roles(self, decoded_token):
        """
        Extract roles from Keycloak token.
        Looks in realm_access.roles and resource_access.<client_id>.roles
        """
        roles = []
        realm_access = decoded_token.get('realm_access', {})
        roles.extend(realm_access.get('roles', []))

        resource_access = decoded_token.get('resource_access', {})
        client_roles = resource_access.get(self.client_id(), {})
        roles.extend(client_roles.get('roles', []))

        groups = decoded_token.get('groups', [])
        for group in groups:
            group_name = group.lstrip('/')
            roles.append(group_name)

        return list(set(roles))

    def verify(self, code, **kwargs):
        try:
            redirect_uri = kwargs.pop('redirect_uri', None)
            code_verifier = kwargs.pop('code_verifier', None)
            token_response = self.exchange_code_for_token(
                code, redirect_uri, code_verifier)

            access_token = token_response.get('access_token')
            id_token_val = token_response.get('id_token', access_token)

            kid, alg = self.get_token_info(id_token_val)
            jwks = self.get_jwks()
            public_key = self.get_public_key(kid, jwks)

            issuer = self._get_realm_url()
            decoded = jwt.decode(
                id_token_val,
                public_key,
                audience=self.client_id(),
                issuer=issuer,
                algorithms=[alg]
            )

            email = decoded.get('email')
            if not email:
                raise KeycloakVerifyTokenError('No email in token')

            email_verified = decoded.get('email_verified', False)
            if not email_verified:
                raise ForbiddenException(Err.OA0012, [])

            name = decoded.get('name') or decoded.get('preferred_username', email)
            roles = self._extract_roles(decoded)

            return email, name, roles
        except (InvalidAuthorizationToken, KeycloakVerifyTokenError,
                jwt.PyJWTError) as ex:
            LOG.error(str(ex))
            raise ForbiddenException(Err.OA0012, [])

'''
    # Insert before SignInController class
    content = content.replace(
        'class SignInController(BaseController):',
        keycloak_provider + '\nclass SignInController(BaseController):'
    )

# Add keycloak to _get_verifier_class
if "'keycloak': KeycloakOauth2Provider" not in content:
    content = content.replace(
        "'microsoft': MicrosoftOauth2Provider\n        }.get(provider)",
        "'microsoft': MicrosoftOauth2Provider,\n            'keycloak': KeycloakOauth2Provider\n        }.get(provider)"
    )

# Modify _get_input to add code_verifier
if 'code_verifier = input_.pop' not in content:
    content = content.replace(
        "redirect_uri = input_.pop('redirect_uri', None)\n        check_kwargs_is_empty(**input_)\n        return provider, token, ip, tenant_id, redirect_uri",
        "redirect_uri = input_.pop('redirect_uri', None)\n        code_verifier = input_.pop('code_verifier', None)\n        check_kwargs_is_empty(**input_)\n        return provider, token, ip, tenant_id, redirect_uri, code_verifier"
    )

# Modify signin method
if 'code_verifier=code_verifier' not in content:
    # Update the unpacking
    content = content.replace(
        'provider, token, ip, tenant_id, redirect_uri = self._get_input(',
        'provider, token, ip, tenant_id, redirect_uri, code_verifier = self._get_input('
    )

    # Update verify call
    content = content.replace(
        'token, tenant_id=tenant_id, redirect_uri=redirect_uri)',
        'token, tenant_id=tenant_id, redirect_uri=redirect_uri,\n            code_verifier=code_verifier)'
    )

# Add keycloak role handling
if "if provider == 'keycloak':" not in content:
    content = content.replace(
        'email, display_name = verify_result',
        '''if provider == 'keycloak':
            email, display_name, keycloak_roles = verify_result
        else:
            email, display_name = verify_result
            keycloak_roles = None'''
    )

# Add role sync after user creation
if 'KeycloakRoleSyncService' not in content:
    content = content.replace(
        'user.verified = True\n\n        token_dict',
        '''user.verified = True

        if provider == 'keycloak' and keycloak_roles:
            from auth.auth_server.controllers.keycloak_role_sync import (
                KeycloakRoleSyncService)
            role_sync = KeycloakRoleSyncService(self._session, self._config)
            role_sync.sync_roles(user, keycloak_roles)

        token_dict'''
    )

with open('auth/auth_server/controllers/signin.py', 'w') as f:
    f.write(content)

print("signin.py modified successfully")
PYTHON_SIGNIN_EOF

print_success "Modified signin.py"

# 3. Modify signin handler
print_info "Modifying auth/auth_server/handlers/v2/signin.py..."

python3 << 'PYTHON_HANDLER_EOF'
with open('auth/auth_server/handlers/v2/signin.py', 'r') as f:
    content = f.read()

# Update provider enum
content = content.replace(
    "provider: {type: string, enum: [google, microsoft],",
    "provider: {type: string, enum: [google, microsoft, keycloak],"
)

# Add redirect_uri and code_verifier parameters if not present
if 'redirect_uri: {type: string' not in content:
    content = content.replace(
        '''tenant_id: {type: string, required: false,
                        description: "Azure AD tenant id
                            (only for microsoft provider)"}''',
        '''tenant_id: {type: string, required: false,
                        description: "Azure AD tenant id
                            (only for microsoft provider)"}
                    redirect_uri: {type: string, required: false,
                        description: "Redirect URI used in OAuth flow
                            (required for keycloak provider)"}
                    code_verifier: {type: string, required: false,
                        description: "PKCE code verifier
                            (only for keycloak provider)"}'''
    )

with open('auth/auth_server/handlers/v2/signin.py', 'w') as f:
    f.write(content)

print("signin handler modified successfully")
PYTHON_HANDLER_EOF

print_success "Modified signin handler"

#===============================================================================
# Create frontend files
#===============================================================================
print_header "Creating Frontend Files"

# 4. Create KeycloakIcon
print_info "Creating ngui/ui/src/icons/KeycloakIcon..."

mkdir -p ngui/ui/src/icons/KeycloakIcon

cat > ngui/ui/src/icons/KeycloakIcon/KeycloakIcon.tsx << 'KEYCLOAK_ICON_EOF'
import SvgIcon from "@mui/material/SvgIcon";

const KeycloakIcon = (props) => (
  <SvgIcon {...props} viewBox="0 0 24 24">
    <path d="M12 2L2 7v10l10 5 10-5V7L12 2zm0 2.18l7.27 3.64v7.27L12 18.73l-7.27-3.64V7.82L12 4.18z" />
    <path d="M12 6.55L7.64 9.09v5.82L12 17.45l4.36-2.54V9.09L12 6.55zm0 1.63l2.73 1.55v3.09L12 14.36l-2.73-1.54V9.73L12 8.18z" />
  </SvgIcon>
);

export default KeycloakIcon;
KEYCLOAK_ICON_EOF

cat > ngui/ui/src/icons/KeycloakIcon/index.ts << 'EOF'
export { default } from "./KeycloakIcon";
EOF

print_success "Created KeycloakIcon"

# 5. Create KeycloakSignInButton
print_info "Creating ngui/ui/src/components/KeycloakSignInButton..."

mkdir -p ngui/ui/src/components/KeycloakSignInButton

cat > ngui/ui/src/components/KeycloakSignInButton/KeycloakSignInButton.tsx << 'KEYCLOAK_BUTTON_EOF'
import { useCallback, useEffect } from "react";
import ButtonLoader from "components/ButtonLoader";
import KeycloakIcon from "icons/KeycloakIcon";
import { AUTH_PROVIDERS } from "utils/constants";
import { keycloakOAuthConfiguration } from "utils/integrations";

const generateRandomState = () => {
  const array = new Uint8Array(16);
  crypto.getRandomValues(array);
  return Array.from(array, (byte) => byte.toString(16).padStart(2, "0")).join("");
};

const generateCodeVerifier = () => {
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  return Array.from(array, (byte) => byte.toString(16).padStart(2, "0")).join("");
};

const generateCodeChallenge = async (verifier: string) => {
  const encoder = new TextEncoder();
  const data = encoder.encode(verifier);
  const digest = await crypto.subtle.digest("SHA-256", data);
  const base64 = btoa(String.fromCharCode(...new Uint8Array(digest)));
  return base64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

const KeycloakSignInButton = ({ handleSignIn, isLoading, disabled }) => {
  const { url, realm, clientId } = keycloakOAuthConfiguration;

  const environmentNotSet = !url || !realm || !clientId;

  const handleClick = useCallback(async () => {
    if (environmentNotSet) return;

    const state = generateRandomState();
    const codeVerifier = generateCodeVerifier();
    const codeChallenge = await generateCodeChallenge(codeVerifier);

    sessionStorage.setItem("keycloak_oauth_state", state);
    sessionStorage.setItem("keycloak_code_verifier", codeVerifier);

    const redirectUri = `${window.location.origin}/keycloak-callback`;

    const authUrl = new URL(`${url}/realms/${realm}/protocol/openid-connect/auth`);
    authUrl.searchParams.set("client_id", clientId);
    authUrl.searchParams.set("redirect_uri", redirectUri);
    authUrl.searchParams.set("response_type", "code");
    authUrl.searchParams.set("scope", "openid email profile");
    authUrl.searchParams.set("state", state);
    authUrl.searchParams.set("code_challenge", codeChallenge);
    authUrl.searchParams.set("code_challenge_method", "S256");

    window.location.href = authUrl.toString();
  }, [url, realm, clientId, environmentNotSet]);

  useEffect(() => {
    const urlParams = new URLSearchParams(window.location.search);
    const code = urlParams.get("code");
    const state = urlParams.get("state");
    const storedState = sessionStorage.getItem("keycloak_oauth_state");
    const codeVerifier = sessionStorage.getItem("keycloak_code_verifier");

    if (code && state && storedState === state) {
      sessionStorage.removeItem("keycloak_oauth_state");
      sessionStorage.removeItem("keycloak_code_verifier");

      const redirectUri = `${window.location.origin}/keycloak-callback`;

      handleSignIn({
        provider: AUTH_PROVIDERS.KEYCLOAK,
        token: code,
        redirectUri,
        codeVerifier
      });

      window.history.replaceState({}, document.title, window.location.pathname);
    }
  }, [handleSignIn]);

  return (
    <ButtonLoader
      variant="outlined"
      messageId="keycloak"
      size="medium"
      onClick={handleClick}
      startIcon={<KeycloakIcon />}
      isLoading={isLoading}
      disabled={disabled || environmentNotSet}
      fullWidth
      tooltip={{
        show: environmentNotSet,
        messageId: "signInWithKeycloakIsNotConfigured"
      }}
    />
  );
};

export default KeycloakSignInButton;
KEYCLOAK_BUTTON_EOF

cat > ngui/ui/src/components/KeycloakSignInButton/index.ts << 'EOF'
export { default } from "./KeycloakSignInButton";
EOF

print_success "Created KeycloakSignInButton"

# 6. Create KeycloakCallbackContainer
print_info "Creating ngui/ui/src/containers/KeycloakCallbackContainer..."

mkdir -p ngui/ui/src/containers/KeycloakCallbackContainer

cat > ngui/ui/src/containers/KeycloakCallbackContainer/KeycloakCallbackContainer.tsx << 'KEYCLOAK_CALLBACK_EOF'
import { useEffect, useState } from "react";
import { useDispatch } from "react-redux";
import { useNavigate } from "react-router-dom";
import { CircularProgress, Box, Typography } from "@mui/material";
import { initialize } from "containers/InitializeContainer/redux";
import { useSignInMutation } from "graphql/__generated__/hooks/auth";
import { LOGIN, INITIALIZE } from "urls";
import { GA_EVENT_CATEGORIES, trackEvent } from "utils/analytics";
import { AUTH_PROVIDERS } from "utils/constants";
import macaroon from "utils/macaroons";

const KeycloakCallbackContainer = () => {
  const dispatch = useDispatch();
  const navigate = useNavigate();
  const [error, setError] = useState<string | null>(null);
  const [signIn] = useSignInMutation();

  useEffect(() => {
    const handleCallback = async () => {
      const urlParams = new URLSearchParams(window.location.search);
      const code = urlParams.get("code");
      const state = urlParams.get("state");
      const errorParam = urlParams.get("error");
      const errorDescription = urlParams.get("error_description");

      if (errorParam) {
        setError(errorDescription || errorParam);
        return;
      }

      const storedState = sessionStorage.getItem("keycloak_oauth_state");
      const codeVerifier = sessionStorage.getItem("keycloak_code_verifier");

      if (!code) {
        setError("No authorization code received");
        return;
      }

      if (state !== storedState) {
        setError("Invalid state parameter");
        return;
      }

      sessionStorage.removeItem("keycloak_oauth_state");
      sessionStorage.removeItem("keycloak_code_verifier");

      const redirectUri = `${window.location.origin}/keycloak-callback`;

      try {
        const { data } = await signIn({
          variables: {
            provider: AUTH_PROVIDERS.KEYCLOAK,
            token: code,
            redirectUri,
            codeVerifier
          }
        });

        const caveats = macaroon.processCaveats(macaroon.deserialize(data.signIn.token).getCaveats());

        if (caveats.register) {
          trackEvent({ category: GA_EVENT_CATEGORIES.USER, action: "Registered", label: "keycloak" });
        }

        dispatch(initialize({ ...data.signIn, caveats }));
        navigate(INITIALIZE);
      } catch (err: unknown) {
        console.error("Keycloak sign-in error:", err);
        const errorMessage = err instanceof Error ? err.message : String(err);
        if (errorMessage.includes("Network") || errorMessage.includes("fetch")) {
          setError("Unable to connect to authentication server. Please check your network connection.");
        } else if (errorMessage.includes("403") || errorMessage.includes("Forbidden")) {
          setError("Authentication was denied. Please contact your administrator.");
        } else if (errorMessage.includes("401") || errorMessage.includes("Unauthorized")) {
          setError("Invalid credentials. Please try signing in again.");
        } else if (errorMessage.includes("timeout") || errorMessage.includes("Timeout")) {
          setError("Authentication timed out. Please try again.");
        } else {
          setError("Authentication failed. Please try again or contact support.");
        }
      }
    };

    handleCallback();
  }, [dispatch, navigate, signIn]);

  if (error) {
    return (
      <Box
        display="flex"
        flexDirection="column"
        alignItems="center"
        justifyContent="center"
        minHeight="100vh"
        gap={2}
      >
        <Typography color="error" variant="h6">
          Authentication Error
        </Typography>
        <Typography color="textSecondary">{error}</Typography>
        <Typography
          component="a"
          href={LOGIN}
          sx={{ color: "primary.main", textDecoration: "underline", cursor: "pointer" }}
        >
          Return to login
        </Typography>
      </Box>
    );
  }

  return (
    <Box display="flex" flexDirection="column" alignItems="center" justifyContent="center" minHeight="100vh" gap={2}>
      <CircularProgress />
      <Typography>Authenticating with Keycloak...</Typography>
    </Box>
  );
};

export default KeycloakCallbackContainer;
KEYCLOAK_CALLBACK_EOF

cat > ngui/ui/src/containers/KeycloakCallbackContainer/index.ts << 'EOF'
export { default } from "./KeycloakCallbackContainer";
EOF

print_success "Created KeycloakCallbackContainer"

# 7. Create KeycloakCallback page
print_info "Creating ngui/ui/src/pages/KeycloakCallback..."

mkdir -p ngui/ui/src/pages/KeycloakCallback

cat > ngui/ui/src/pages/KeycloakCallback/KeycloakCallback.tsx << 'EOF'
import KeycloakCallbackContainer from "containers/KeycloakCallbackContainer";

const KeycloakCallback = () => <KeycloakCallbackContainer />;

export default KeycloakCallback;
EOF

cat > ngui/ui/src/pages/KeycloakCallback/index.ts << 'EOF'
export { default } from "./KeycloakCallback";
EOF

print_success "Created KeycloakCallback page"

# 8. Create keycloakCallbackRoute
print_info "Creating ngui/ui/src/utils/routes/keycloakCallbackRoute.ts..."

cat > ngui/ui/src/utils/routes/keycloakCallbackRoute.ts << 'EOF'
import { lazy } from "react";

export const KEYCLOAK_CALLBACK = "/keycloak-callback";

const KeycloakCallback = lazy(() => import("pages/KeycloakCallback"));

export default {
  key: "keycloak-callback",
  link: KEYCLOAK_CALLBACK,
  component: KeycloakCallback,
  layout: null,
  isTokenRequired: false
};
EOF

print_success "Created keycloakCallbackRoute"

#===============================================================================
# Modify existing frontend files
#===============================================================================
print_header "Modifying Frontend Files"

# 9. Modify env.ts
print_info "Modifying ngui/ui/src/utils/env.ts..."

python3 << 'PYTHON_ENV_EOF'
with open('ngui/ui/src/utils/env.ts', 'r') as f:
    content = f.read()

# Add Keycloak env vars if not present
if 'VITE_KEYCLOAK_URL' not in content:
    content = content.replace(
        'VITE_BILLING_INTEGRATION: oneOf(["enabled", "disabled"], "disabled")',
        '''VITE_BILLING_INTEGRATION: oneOf(["enabled", "disabled"], "disabled"),
  VITE_KEYCLOAK_URL: stringWithDefault(),
  VITE_KEYCLOAK_REALM: stringWithDefault(),
  VITE_KEYCLOAK_CLIENT_ID: stringWithDefault(),
  VITE_APP_THEME: stringWithDefault()'''
    )

with open('ngui/ui/src/utils/env.ts', 'w') as f:
    f.write(content)

print("env.ts modified successfully")
PYTHON_ENV_EOF

print_success "Modified env.ts"

# 10. Modify constants.ts
print_info "Modifying ngui/ui/src/utils/constants.ts..."

python3 << 'PYTHON_CONSTANTS_EOF'
with open('ngui/ui/src/utils/constants.ts', 'r') as f:
    content = f.read()

# Add KEYCLOAK to AUTH_PROVIDERS if not present
if 'KEYCLOAK: "keycloak"' not in content:
    content = content.replace(
        'MICROSOFT: "microsoft"',
        'MICROSOFT: "microsoft",\n  KEYCLOAK: "keycloak"'
    )

with open('ngui/ui/src/utils/constants.ts', 'w') as f:
    f.write(content)

print("constants.ts modified successfully")
PYTHON_CONSTANTS_EOF

print_success "Modified constants.ts"

# 11. Modify integrations.ts
print_info "Modifying ngui/ui/src/utils/integrations.ts..."

python3 << 'PYTHON_INTEGRATIONS_EOF'
with open('ngui/ui/src/utils/integrations.ts', 'r') as f:
    content = f.read()

# Add Keycloak configuration if not present
if 'keycloakOAuthConfiguration' not in content:
    keycloak_config = '''

const parseKeycloakAuthUrl = (authUrl: string | undefined) => {
  if (!authUrl) return { url: undefined, realm: undefined };

  try {
    const match = authUrl.match(/^(https?:\\/\\/[^/]+)\\/realms\\/([^/]+)/);
    if (match) {
      return { url: match[1], realm: match[2] };
    }
  } catch {
    // Fall through
  }
  return { url: authUrl, realm: undefined };
};

const keycloakUrl = getEnvironmentVariable("VITE_KEYCLOAK_URL");
const keycloakRealm = getEnvironmentVariable("VITE_KEYCLOAK_REALM");
const parsedFromUrl = keycloakUrl && !keycloakRealm ? parseKeycloakAuthUrl(keycloakUrl) : { url: keycloakUrl, realm: keycloakRealm };

export const keycloakOAuthConfiguration = {
  url: parsedFromUrl.url,
  realm: parsedFromUrl.realm,
  clientId: getEnvironmentVariable("VITE_KEYCLOAK_CLIENT_ID")
};
'''
    content = content + keycloak_config

with open('ngui/ui/src/utils/integrations.ts', 'w') as f:
    f.write(content)

print("integrations.ts modified successfully")
PYTHON_INTEGRATIONS_EOF

print_success "Modified integrations.ts"

# 12. Modify translations
print_info "Modifying ngui/ui/src/translations/en-US/app.json..."

python3 << 'PYTHON_TRANSLATIONS_EOF'
import json

with open('ngui/ui/src/translations/en-US/app.json', 'r') as f:
    translations = json.load(f)

# Add Keycloak translations if not present
if 'keycloak' not in translations:
    translations['keycloak'] = 'Keycloak'

if 'signInWithKeycloakIsNotConfigured' not in translations:
    translations['signInWithKeycloakIsNotConfigured'] = 'Sign in with Keycloak is not configured'

with open('ngui/ui/src/translations/en-US/app.json', 'w') as f:
    json.dump(translations, f, indent=2, ensure_ascii=False)

print("translations modified successfully")
PYTHON_TRANSLATIONS_EOF

print_success "Modified translations"

#===============================================================================
# Modify GraphQL files
#===============================================================================
print_header "Modifying GraphQL Files"

# 13. Modify auth.graphql
print_info "Modifying ngui/ui/src/graphql/queries/auth/auth.graphql..."

python3 << 'PYTHON_GRAPHQL_EOF'
with open('ngui/ui/src/graphql/queries/auth/auth.graphql', 'r') as f:
    content = f.read()

# Add codeVerifier to SignIn mutation
if '$codeVerifier: String' not in content:
    content = content.replace(
        'mutation SignIn($provider: String!, $token: String!, $tenantId: String, $redirectUri: String)',
        'mutation SignIn($provider: String!, $token: String!, $tenantId: String, $redirectUri: String, $codeVerifier: String)'
    )
    content = content.replace(
        'signIn(provider: $provider, token: $token, tenantId: $tenantId, redirectUri: $redirectUri)',
        'signIn(provider: $provider, token: $token, tenantId: $tenantId, redirectUri: $redirectUri, codeVerifier: $codeVerifier)'
    )

with open('ngui/ui/src/graphql/queries/auth/auth.graphql', 'w') as f:
    f.write(content)

print("auth.graphql modified successfully")
PYTHON_GRAPHQL_EOF

print_success "Modified auth.graphql"

# 14. Modify server GraphQL typeDefs
print_info "Modifying ngui/server/graphql/typeDefs/auth/auth.ts..."

python3 << 'PYTHON_TYPEDEF_EOF'
with open('ngui/server/graphql/typeDefs/auth/auth.ts', 'r') as f:
    content = f.read()

# Add codeVerifier to signIn mutation
if 'codeVerifier: String' not in content:
    content = content.replace(
        'signIn(provider: String!, token: String!, tenantId: String, redirectUri: String): Token',
        'signIn(provider: String!, token: String!, tenantId: String, redirectUri: String, codeVerifier: String): Token'
    )

with open('ngui/server/graphql/typeDefs/auth/auth.ts', 'w') as f:
    f.write(content)

print("typeDefs modified successfully")
PYTHON_TYPEDEF_EOF

print_success "Modified typeDefs"

# 15. Modify server GraphQL resolver
print_info "Modifying ngui/server/graphql/resolvers/auth.ts..."

python3 << 'PYTHON_RESOLVER_EOF'
with open('ngui/server/graphql/resolvers/auth.ts', 'r') as f:
    content = f.read()

# Add codeVerifier to signIn resolver
if 'codeVerifier' not in content:
    content = content.replace(
        'signIn: async (_, { provider, token, tenantId, redirectUri }, { dataSources }) => {\n      return dataSources.auth.signIn(provider, token, tenantId, redirectUri);',
        'signIn: async (_, { provider, token, tenantId, redirectUri, codeVerifier }, { dataSources }) => {\n      return dataSources.auth.signIn(provider, token, tenantId, redirectUri, codeVerifier);'
    )

with open('ngui/server/graphql/resolvers/auth.ts', 'w') as f:
    f.write(content)

print("resolver modified successfully")
PYTHON_RESOLVER_EOF

print_success "Modified resolver"

# 16. Modify server API client
print_info "Modifying ngui/server/api/auth/client.ts..."

python3 << 'PYTHON_CLIENT_EOF'
with open('ngui/server/api/auth/client.ts', 'r') as f:
    content = f.read()

# Add codeVerifier to signIn method
if 'code_verifier: codeVerifier' not in content:
    content = content.replace(
        'async signIn(provider, token, tenantId, redirectUri) {',
        'async signIn(provider, token, tenantId, redirectUri, codeVerifier) {'
    )
    content = content.replace(
        'redirect_uri: redirectUri,\n      },',
        'redirect_uri: redirectUri,\n        code_verifier: codeVerifier,\n      },'
    )

with open('ngui/server/api/auth/client.ts', 'w') as f:
    f.write(content)

print("client.ts modified successfully")
PYTHON_CLIENT_EOF

print_success "Modified API client"

# 17. Modify generated hooks
print_info "Modifying ngui/ui/src/graphql/__generated__/hooks/auth.ts..."

python3 << 'PYTHON_HOOKS_EOF'
with open('ngui/ui/src/graphql/__generated__/hooks/auth.ts', 'r') as f:
    content = f.read()

# Add codeVerifier to MutationSignInArgs
if 'codeVerifier?: InputMaybe<Scalars["String"]["input"]>;' not in content:
    content = content.replace(
        '''export type MutationSignInArgs = {
  provider: Scalars["String"]["input"];
  redirectUri?: InputMaybe<Scalars["String"]["input"]>;
  tenantId?: InputMaybe<Scalars["String"]["input"]>;
  token: Scalars["String"]["input"];
};''',
        '''export type MutationSignInArgs = {
  provider: Scalars["String"]["input"];
  redirectUri?: InputMaybe<Scalars["String"]["input"]>;
  tenantId?: InputMaybe<Scalars["String"]["input"]>;
  token: Scalars["String"]["input"];
  codeVerifier?: InputMaybe<Scalars["String"]["input"]>;
};'''
    )

# Add codeVerifier to SignInMutationVariables
if 'codeVerifier?: InputMaybe<Scalars["String"]["input"]>;' in content and 'SignInMutationVariables' in content:
    if content.count('codeVerifier') < 3:
        content = content.replace(
            '''export type SignInMutationVariables = Exact<{
  provider: Scalars["String"]["input"];
  token: Scalars["String"]["input"];
  tenantId?: InputMaybe<Scalars["String"]["input"]>;
  redirectUri?: InputMaybe<Scalars["String"]["input"]>;
}>;''',
            '''export type SignInMutationVariables = Exact<{
  provider: Scalars["String"]["input"];
  token: Scalars["String"]["input"];
  tenantId?: InputMaybe<Scalars["String"]["input"]>;
  redirectUri?: InputMaybe<Scalars["String"]["input"]>;
  codeVerifier?: InputMaybe<Scalars["String"]["input"]>;
}>;'''
        )

# Update SignInDocument
if 'codeVerifier: $codeVerifier' not in content:
    content = content.replace(
        'mutation SignIn($provider: String!, $token: String!, $tenantId: String, $redirectUri: String)',
        'mutation SignIn($provider: String!, $token: String!, $tenantId: String, $redirectUri: String, $codeVerifier: String)'
    )
    content = content.replace(
        'signIn(provider: $provider, token: $token, tenantId: $tenantId, redirectUri: $redirectUri)',
        'signIn(provider: $provider, token: $token, tenantId: $tenantId, redirectUri: $redirectUri, codeVerifier: $codeVerifier)'
    )

with open('ngui/ui/src/graphql/__generated__/hooks/auth.ts', 'w') as f:
    f.write(content)

print("hooks/auth.ts modified successfully")
PYTHON_HOOKS_EOF

print_success "Modified generated hooks"

# 18. Modify server generated types
print_info "Modifying ngui/server/graphql/__generated__/types/auth.ts..."

python3 << 'PYTHON_SERVER_TYPES_EOF'
with open('ngui/server/graphql/__generated__/types/auth.ts', 'r') as f:
    content = f.read()

# Add codeVerifier to MutationSignInArgs
if content.count('codeVerifier') == 0:
    content = content.replace(
        '''export type MutationSignInArgs = {
  provider: Scalars["String"]["input"];
  redirectUri?: InputMaybe<Scalars["String"]["input"]>;
  tenantId?: InputMaybe<Scalars["String"]["input"]>;
  token: Scalars["String"]["input"];
};''',
        '''export type MutationSignInArgs = {
  provider: Scalars["String"]["input"];
  redirectUri?: InputMaybe<Scalars["String"]["input"]>;
  tenantId?: InputMaybe<Scalars["String"]["input"]>;
  token: Scalars["String"]["input"];
  codeVerifier?: InputMaybe<Scalars["String"]["input"]>;
};'''
    )

with open('ngui/server/graphql/__generated__/types/auth.ts', 'w') as f:
    f.write(content)

print("server types modified successfully")
PYTHON_SERVER_TYPES_EOF

print_success "Modified server generated types"

#===============================================================================
# Modify deployment files
#===============================================================================
print_header "Modifying Deployment Files"

# 19. Modify auth.yaml template
print_info "Modifying optscale-deploy/optscale/templates/auth.yaml..."

if ! grep -q "KEYCLOAK_OAUTH_CLIENT_ID" optscale-deploy/optscale/templates/auth.yaml; then
    # Find the env section and add Keycloak vars
    python3 << 'PYTHON_AUTH_YAML_EOF'
with open('optscale-deploy/optscale/templates/auth.yaml', 'r') as f:
    content = f.read()

# Add Keycloak env vars after existing env vars
keycloak_env = '''        - name: KEYCLOAK_OAUTH_CLIENT_ID
          value: {{ .Values.auth.keycloak_oauth_client_id | default "" | quote }}
        - name: KEYCLOAK_OAUTH_CLIENT_SECRET
          value: {{ .Values.auth.keycloak_oauth_client_secret | default "" | quote }}
        - name: KEYCLOAK_SERVER_URL
          value: {{ .Values.auth.keycloak_server_url | default "" | quote }}
        - name: KEYCLOAK_REALM
          value: {{ .Values.auth.keycloak_realm | default "" | quote }}
'''

# Find a good place to insert (after MICROSOFT_OAUTH_CLIENT_ID or similar)
if 'MICROSOFT_OAUTH_CLIENT_ID' in content:
    # Insert after Microsoft env var
    lines = content.split('\n')
    new_lines = []
    for i, line in enumerate(lines):
        new_lines.append(line)
        if 'MICROSOFT_OAUTH_CLIENT_ID' in line:
            # Find the value line and insert after
            if i + 1 < len(lines) and 'value:' in lines[i + 1]:
                continue

    # Simple approach: append before the ports section
    content = content.replace('        ports:', keycloak_env + '        ports:')

with open('optscale-deploy/optscale/templates/auth.yaml', 'w') as f:
    f.write(content)

print("auth.yaml modified")
PYTHON_AUTH_YAML_EOF
    print_success "Modified auth.yaml"
else
    print_warning "auth.yaml already contains Keycloak configuration"
fi

# 20. Modify ngui.yaml template
print_info "Modifying optscale-deploy/optscale/templates/ngui.yaml..."

if ! grep -q "VITE_KEYCLOAK_URL" optscale-deploy/optscale/templates/ngui.yaml; then
    python3 << 'PYTHON_NGUI_YAML_EOF'
with open('optscale-deploy/optscale/templates/ngui.yaml', 'r') as f:
    content = f.read()

keycloak_env = '''        - name: VITE_KEYCLOAK_URL
          value: {{ .Values.ngui.env.keycloak_url | default "" | quote }}
        - name: VITE_KEYCLOAK_REALM
          value: {{ .Values.ngui.env.keycloak_realm | default "" | quote }}
        - name: VITE_KEYCLOAK_CLIENT_ID
          value: {{ .Values.ngui.env.keycloak_client_id | default "" | quote }}
'''

# Insert before ports section
content = content.replace('        ports:', keycloak_env + '        ports:')

with open('optscale-deploy/optscale/templates/ngui.yaml', 'w') as f:
    f.write(content)

print("ngui.yaml modified")
PYTHON_NGUI_YAML_EOF
    print_success "Modified ngui.yaml"
else
    print_warning "ngui.yaml already contains Keycloak configuration"
fi

# 21. Update user_template.yml with provided values
print_info "Updating optscale-deploy/overlay/user_template.yml..."

python3 << PYTHON_USER_TEMPLATE_EOF
import re

with open('optscale-deploy/overlay/user_template.yml', 'r') as f:
    content = f.read()

# Update auth section
if 'keycloak_oauth_client_id:' not in content:
    content = content.replace(
        'microsoft_oauth_client_id: ""',
        '''microsoft_oauth_client_id: ""
  keycloak_oauth_client_id: "${KEYCLOAK_CLIENT_ID}"
  keycloak_oauth_client_secret: "${KEYCLOAK_CLIENT_SECRET}"
  keycloak_server_url: "${KEYCLOAK_URL}"
  keycloak_realm: "${KEYCLOAK_REALM}"'''
    )
else:
    # Update existing values
    content = re.sub(r'keycloak_oauth_client_id:.*', 'keycloak_oauth_client_id: "${KEYCLOAK_CLIENT_ID}"', content)
    content = re.sub(r'keycloak_oauth_client_secret:.*', 'keycloak_oauth_client_secret: "${KEYCLOAK_CLIENT_SECRET}"', content)
    content = re.sub(r'keycloak_server_url:.*', 'keycloak_server_url: "${KEYCLOAK_URL}"', content)
    content = re.sub(r'keycloak_realm:.*', 'keycloak_realm: "${KEYCLOAK_REALM}"', content)

# Update ngui section
if 'keycloak_url:' not in content:
    content = content.replace(
        'microsoft_oauth_client_id: ""',
        '''microsoft_oauth_client_id: ""
    keycloak_url: "${KEYCLOAK_URL}"
    keycloak_realm: "${KEYCLOAK_REALM}"
    keycloak_client_id: "${KEYCLOAK_CLIENT_ID}"''',
        1  # Only replace first occurrence (in ngui section)
    )
else:
    # Update existing values in ngui section - need more careful replacement
    pass

with open('optscale-deploy/overlay/user_template.yml', 'w') as f:
    f.write(content)

print("user_template.yml updated")
PYTHON_USER_TEMPLATE_EOF

# Now do the actual substitution
sed -i "s|\${KEYCLOAK_CLIENT_ID}|${KEYCLOAK_CLIENT_ID}|g" optscale-deploy/overlay/user_template.yml
sed -i "s|\${KEYCLOAK_CLIENT_SECRET}|${KEYCLOAK_CLIENT_SECRET}|g" optscale-deploy/overlay/user_template.yml
sed -i "s|\${KEYCLOAK_URL}|${KEYCLOAK_URL}|g" optscale-deploy/overlay/user_template.yml
sed -i "s|\${KEYCLOAK_REALM}|${KEYCLOAK_REALM}|g" optscale-deploy/overlay/user_template.yml

print_success "Updated user_template.yml with your configuration"

# 22. Update .env.sample
print_info "Updating ngui/ui/.env.sample..."

if ! grep -q "VITE_KEYCLOAK_URL" ngui/ui/.env.sample; then
    echo "" >> ngui/ui/.env.sample
    echo "# Keycloak SSO Configuration" >> ngui/ui/.env.sample
    echo "VITE_KEYCLOAK_URL=" >> ngui/ui/.env.sample
    echo "VITE_KEYCLOAK_REALM=" >> ngui/ui/.env.sample
    echo "VITE_KEYCLOAK_CLIENT_ID=" >> ngui/ui/.env.sample
    print_success "Updated .env.sample"
else
    print_warning ".env.sample already contains Keycloak configuration"
fi

#===============================================================================
# Summary
#===============================================================================
print_header "Setup Complete!"

echo -e "${GREEN}Keycloak integration has been set up successfully!${NC}"
echo ""
echo "Configuration applied:"
echo "  Keycloak URL:    $KEYCLOAK_URL"
echo "  Keycloak Realm:  $KEYCLOAK_REALM"
echo "  Keycloak Client: $KEYCLOAK_CLIENT_ID"
echo "  OptScale URL:    $OPTSCALE_URL"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "1. Configure Keycloak Client:"
echo "   - Go to: $KEYCLOAK_URL/admin"
echo "   - Navigate to: Clients → $KEYCLOAK_CLIENT_ID"
echo "   - Set Valid Redirect URI: $OPTSCALE_URL/keycloak-callback"
echo "   - Set Web Origins: $OPTSCALE_URL"
echo ""
echo "2. Create Keycloak Roles (optional, for role mapping):"
echo "   - optscale-admin   → Manager role"
echo "   - optscale-manager → Manager role"
echo "   - optscale-engineer → Engineer role"
echo "   - optscale-member  → Member role"
echo ""
echo "3. Rebuild and Deploy OptScale:"
echo "   cd optscale-deploy"
echo "   source .venv/bin/activate"
echo ""
echo "   # Build images"
echo "   export PATH=\$PATH:/root/bin"
echo "   nerdctl -n k8s.io build --no-cache -t auth:local -f ../auth/Dockerfile .."
echo "   nerdctl -n k8s.io build --no-cache -t ngui:local -f ../ngui/Dockerfile .."
echo ""
echo "   # Deploy"
echo "   python runkube.py --with-elk -o overlay/user_template.yml my-optscale local"
echo ""
echo "4. Test the integration:"
echo "   - Go to: $OPTSCALE_URL/login"
echo "   - Click the Keycloak button"
echo "   - Login with your Keycloak credentials"
echo ""
echo -e "${BLUE}Documentation:${NC}"
echo "  - Full guide: documentation/keycloak_integration.md"
echo "  - Code changes: documentation/keycloak_code_changes.md"
echo ""
