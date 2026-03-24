# Keycloak Integration - Code Changes

This document shows all code changes made to integrate Keycloak with OptScale. Use this to manually apply changes to a fresh clone from GitHub.

---

## Table of Contents

1. [Backend Changes](#backend-changes)
2. [Frontend Changes](#frontend-changes)
3. [GraphQL Changes](#graphql-changes)
4. [Deployment Changes](#deployment-changes)
5. [New Files Created](#new-files-created)

---

## Backend Changes

### 1. `auth/auth_server/controllers/signin.py`

**ADD** these imports at the top (after existing imports):

```python
import time
from requests.exceptions import ConnectionError, Timeout
```

**ADD** the `KeycloakVerifyTokenError` exception class (after `AzureVerifyTokenError`):

```python
class KeycloakVerifyTokenError(Exception):
    pass
```

**ADD** the entire `KeycloakOauth2Provider` class (after `MicrosoftOauth2Provider` class):

```python
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
            id_token = token_response.get('id_token', access_token)

            kid, alg = self.get_token_info(id_token)
            jwks = self.get_jwks()
            public_key = self.get_public_key(kid, jwks)

            issuer = self._get_realm_url()
            decoded = jwt.decode(
                id_token,
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
```

**MODIFY** the `_get_verifier_class` method in `SignInController` to add Keycloak:

```python
# BEFORE:
@staticmethod
def _get_verifier_class(provider):
    return {
        'google': GoogleOauth2Provider,
        'microsoft': MicrosoftOauth2Provider
    }.get(provider)

# AFTER:
@staticmethod
def _get_verifier_class(provider):
    return {
        'google': GoogleOauth2Provider,
        'microsoft': MicrosoftOauth2Provider,
        'keycloak': KeycloakOauth2Provider
    }.get(provider)
```

**MODIFY** the `_get_input` method to add `code_verifier`:

```python
# BEFORE:
@staticmethod
def _get_input(**input_):
    provider = pop_or_raise(input_, 'provider')
    check_string_attribute('provider', provider)
    token = pop_or_raise(input_, 'token')
    check_string_attribute('token', token, max_length=65536)
    ip = input_.pop('ip', None)
    tenant_id = input_.pop('tenant_id', None)
    redirect_uri = input_.pop('redirect_uri', None)
    check_kwargs_is_empty(**input_)
    return provider, token, ip, tenant_id, redirect_uri

# AFTER:
@staticmethod
def _get_input(**input_):
    provider = pop_or_raise(input_, 'provider')
    check_string_attribute('provider', provider)
    token = pop_or_raise(input_, 'token')
    check_string_attribute('token', token, max_length=65536)
    ip = input_.pop('ip', None)
    tenant_id = input_.pop('tenant_id', None)
    redirect_uri = input_.pop('redirect_uri', None)
    code_verifier = input_.pop('code_verifier', None)
    check_kwargs_is_empty(**input_)
    return provider, token, ip, tenant_id, redirect_uri, code_verifier
```

**MODIFY** the `signin` method to handle Keycloak roles:

```python
# BEFORE:
def signin(self, **kwargs):
    provider, token, ip, tenant_id, redirect_uri = self._get_input(**kwargs)
    verifier_class = self._get_verifier_class(provider)
    if not verifier_class:
        raise WrongArgumentsException(Err.OA0067, [provider])
    verify_result = verifier_class().verify(
        token, tenant_id=tenant_id, redirect_uri=redirect_uri)
    email, display_name = verify_result
    # ... rest of method

# AFTER:
def signin(self, **kwargs):
    provider, token, ip, tenant_id, redirect_uri, code_verifier = self._get_input(**kwargs)
    verifier_class = self._get_verifier_class(provider)
    if not verifier_class:
        raise WrongArgumentsException(Err.OA0067, [provider])
    verify_result = verifier_class().verify(
        token, tenant_id=tenant_id, redirect_uri=redirect_uri,
        code_verifier=code_verifier)

    if provider == 'keycloak':
        email, display_name, keycloak_roles = verify_result
    else:
        email, display_name = verify_result
        keycloak_roles = None

    user = self.user_ctl.get_user_by_email(email)
    register = user is None
    if not user:
        user = self.user_ctl.create(
            email=email, display_name=display_name,
            password=self._gen_password(),
            self_registration=True, token='',
            is_password_autogenerated=True)
    user.verified = True

    if provider == 'keycloak' and keycloak_roles:
        from auth.auth_server.controllers.keycloak_role_sync import (
            KeycloakRoleSyncService)
        role_sync = KeycloakRoleSyncService(self._session, self._config)
        role_sync.sync_roles(user, keycloak_roles)

    token_dict = self.token_ctl.create_token_by_user_id(
        user_id=user.id, ip=ip, provider=provider,
        register=register)
    token_dict['user_email'] = user.email
    return token_dict
```

---

### 2. `auth/auth_server/handlers/v2/signin.py`

**MODIFY** the API documentation in the `post` method:

```python
# BEFORE:
parameters:
-   in: body
    name: body
    required: true
    schema:
        type: object
        properties:
            provider: {type: string, enum: [google, microsoft],
                description: "Third party provider to validate token"}
            token: {type: string,
                description: "Third party token"}
            tenant_id: {type: string, required: false,
                description: "Azure AD tenant id
                    (only for microsoft provider)"}

# AFTER:
parameters:
-   in: body
    name: body
    required: true
    schema:
        type: object
        properties:
            provider: {type: string, enum: [google, microsoft, keycloak],
                description: "Third party provider to validate token"}
            token: {type: string,
                description: "Third party token or authorization code"}
            tenant_id: {type: string, required: false,
                description: "Azure AD tenant id
                    (only for microsoft provider)"}
            redirect_uri: {type: string, required: false,
                description: "Redirect URI used in OAuth flow
                    (required for keycloak provider)"}
            code_verifier: {type: string, required: false,
                description: "PKCE code verifier
                    (only for keycloak provider)"}
```

---

## Frontend Changes

### 3. `ngui/ui/src/utils/env.ts`

**MODIFY** the `envSchema` object to add Keycloak variables:

```typescript
// BEFORE:
const envSchema = Object.freeze({
  VITE_APOLLO_HTTP_BASE: stringWithDefault(),
  VITE_APOLLO_WS_BASE: stringWithDefault(),
  VITE_GOOGLE_OAUTH_CLIENT_ID: stringWithDefault(),
  VITE_ON_INITIALIZE_ORGANIZATION_SETUP_MODE: oneOf(["automatic", "invite-only"], "automatic"),
  VITE_GOOGLE_MAP_API_KEY: stringWithDefault(),
  VITE_GANALYTICS_ID: stringWithDefault(),
  VITE_BASE_URL: stringWithDefault(),
  VITE_FINOPS_IN_PRACTICE_PORTAL_OVERVIEW: oneOf(["enabled", "disabled"], "disabled"),
  VITE_HOTJAR_ID: stringWithDefault(),
  VITE_MICROSOFT_OAUTH_CLIENT_ID: stringWithDefault(),
  VITE_BILLING_INTEGRATION: oneOf(["enabled", "disabled"], "disabled")
});

// AFTER:
const envSchema = Object.freeze({
  VITE_APOLLO_HTTP_BASE: stringWithDefault(),
  VITE_APOLLO_WS_BASE: stringWithDefault(),
  VITE_GOOGLE_OAUTH_CLIENT_ID: stringWithDefault(),
  VITE_ON_INITIALIZE_ORGANIZATION_SETUP_MODE: oneOf(["automatic", "invite-only"], "automatic"),
  VITE_GOOGLE_MAP_API_KEY: stringWithDefault(),
  VITE_GANALYTICS_ID: stringWithDefault(),
  VITE_BASE_URL: stringWithDefault(),
  VITE_FINOPS_IN_PRACTICE_PORTAL_OVERVIEW: oneOf(["enabled", "disabled"], "disabled"),
  VITE_HOTJAR_ID: stringWithDefault(),
  VITE_MICROSOFT_OAUTH_CLIENT_ID: stringWithDefault(),
  VITE_BILLING_INTEGRATION: oneOf(["enabled", "disabled"], "disabled"),
  VITE_KEYCLOAK_URL: stringWithDefault(),
  VITE_KEYCLOAK_REALM: stringWithDefault(),
  VITE_KEYCLOAK_CLIENT_ID: stringWithDefault(),
  VITE_APP_THEME: stringWithDefault()
});
```

---

### 4. `ngui/ui/src/utils/constants.ts`

**ADD** Keycloak to AUTH_PROVIDERS:

```typescript
// BEFORE:
export const AUTH_PROVIDERS = Object.freeze({
  GOOGLE: "google",
  MICROSOFT: "microsoft"
});

// AFTER:
export const AUTH_PROVIDERS = Object.freeze({
  GOOGLE: "google",
  MICROSOFT: "microsoft",
  KEYCLOAK: "keycloak"
});
```

---

### 5. `ngui/ui/src/utils/integrations.ts`

**ADD** Keycloak configuration at the end of the file:

```typescript
// ADD after microsoftOAuthConfiguration:

const parseKeycloakAuthUrl = (authUrl: string | undefined) => {
  if (!authUrl) return { url: undefined, realm: undefined };

  try {
    const match = authUrl.match(/^(https?:\/\/[^/]+)\/realms\/([^/]+)/);
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
```

---

### 6. `ngui/ui/src/translations/en-US/app.json`

**ADD** Keycloak translations:

```json
{
  "keycloak": "Keycloak",
  "signInWithKeycloakIsNotConfigured": "Sign in with Keycloak is not configured"
}
```

---

## GraphQL Changes

### 7. `ngui/ui/src/graphql/queries/auth/auth.graphql`

**MODIFY** the SignIn mutation:

```graphql
# BEFORE:
mutation SignIn($provider: String!, $token: String!, $tenantId: String, $redirectUri: String) {
  signIn(provider: $provider, token: $token, tenantId: $tenantId, redirectUri: $redirectUri) {
    token
    user_id
    user_email
  }
}

# AFTER:
mutation SignIn($provider: String!, $token: String!, $tenantId: String, $redirectUri: String, $codeVerifier: String) {
  signIn(provider: $provider, token: $token, tenantId: $tenantId, redirectUri: $redirectUri, codeVerifier: $codeVerifier) {
    token
    user_id
    user_email
  }
}
```

---

### 8. `ngui/server/graphql/typeDefs/auth/auth.ts`

**MODIFY** the signIn mutation definition:

```typescript
// BEFORE:
signIn(provider: String!, token: String!, tenantId: String, redirectUri: String): Token

// AFTER:
signIn(provider: String!, token: String!, tenantId: String, redirectUri: String, codeVerifier: String): Token
```

---

### 9. `ngui/server/graphql/resolvers/auth.ts`

**MODIFY** the signIn resolver:

```typescript
// BEFORE:
signIn: async (_, { provider, token, tenantId, redirectUri }, { dataSources }) => {
  return dataSources.auth.signIn(provider, token, tenantId, redirectUri);
}

// AFTER:
signIn: async (_, { provider, token, tenantId, redirectUri, codeVerifier }, { dataSources }) => {
  return dataSources.auth.signIn(provider, token, tenantId, redirectUri, codeVerifier);
}
```

---

### 10. `ngui/server/api/auth/client.ts`

**MODIFY** the signIn method:

```typescript
// BEFORE:
async signIn(provider, token, tenantId, redirectUri) {
  const result = await this.post("signin", {
    body: {
      provider,
      token,
      tenant_id: tenantId,
      redirect_uri: redirectUri,
    },
  });

  return {
    token: result.token,
    user_email: result.user_email,
    user_id: result.user_id,
  };
}

// AFTER:
async signIn(provider, token, tenantId, redirectUri, codeVerifier) {
  const result = await this.post("signin", {
    body: {
      provider,
      token,
      tenant_id: tenantId,
      redirect_uri: redirectUri,
      code_verifier: codeVerifier,
    },
  });

  return {
    token: result.token,
    user_email: result.user_email,
    user_id: result.user_id,
  };
}
```

---

### 11. `ngui/ui/src/graphql/__generated__/hooks/auth.ts`

**MODIFY** `MutationSignInArgs`:

```typescript
// BEFORE:
export type MutationSignInArgs = {
  provider: Scalars["String"]["input"];
  redirectUri?: InputMaybe<Scalars["String"]["input"]>;
  tenantId?: InputMaybe<Scalars["String"]["input"]>;
  token: Scalars["String"]["input"];
};

// AFTER:
export type MutationSignInArgs = {
  provider: Scalars["String"]["input"];
  redirectUri?: InputMaybe<Scalars["String"]["input"]>;
  tenantId?: InputMaybe<Scalars["String"]["input"]>;
  token: Scalars["String"]["input"];
  codeVerifier?: InputMaybe<Scalars["String"]["input"]>;
};
```

**MODIFY** `SignInMutationVariables`:

```typescript
// BEFORE:
export type SignInMutationVariables = Exact<{
  provider: Scalars["String"]["input"];
  token: Scalars["String"]["input"];
  tenantId?: InputMaybe<Scalars["String"]["input"]>;
  redirectUri?: InputMaybe<Scalars["String"]["input"]>;
}>;

// AFTER:
export type SignInMutationVariables = Exact<{
  provider: Scalars["String"]["input"];
  token: Scalars["String"]["input"];
  tenantId?: InputMaybe<Scalars["String"]["input"]>;
  redirectUri?: InputMaybe<Scalars["String"]["input"]>;
  codeVerifier?: InputMaybe<Scalars["String"]["input"]>;
}>;
```

**MODIFY** `SignInDocument`:

```typescript
// BEFORE:
export const SignInDocument = gql`
  mutation SignIn($provider: String!, $token: String!, $tenantId: String, $redirectUri: String) {
    signIn(provider: $provider, token: $token, tenantId: $tenantId, redirectUri: $redirectUri) {
      token
      user_id
      user_email
    }
  }
`;

// AFTER:
export const SignInDocument = gql`
  mutation SignIn($provider: String!, $token: String!, $tenantId: String, $redirectUri: String, $codeVerifier: String) {
    signIn(provider: $provider, token: $token, tenantId: $tenantId, redirectUri: $redirectUri, codeVerifier: $codeVerifier) {
      token
      user_id
      user_email
    }
  }
`;
```

---

### 12. `ngui/server/graphql/__generated__/types/auth.ts`

**MODIFY** `MutationSignInArgs`:

```typescript
// BEFORE:
export type MutationSignInArgs = {
  provider: Scalars["String"]["input"];
  redirectUri?: InputMaybe<Scalars["String"]["input"]>;
  tenantId?: InputMaybe<Scalars["String"]["input"]>;
  token: Scalars["String"]["input"];
};

// AFTER:
export type MutationSignInArgs = {
  provider: Scalars["String"]["input"];
  redirectUri?: InputMaybe<Scalars["String"]["input"]>;
  tenantId?: InputMaybe<Scalars["String"]["input"]>;
  token: Scalars["String"]["input"];
  codeVerifier?: InputMaybe<Scalars["String"]["input"]>;
};
```

---

## Deployment Changes

### 13. `optscale-deploy/optscale/templates/auth.yaml`

**ADD** Keycloak environment variables in the `env` section:

```yaml
# ADD these environment variables:
- name: KEYCLOAK_OAUTH_CLIENT_ID
  value: {{ .Values.auth.keycloak_oauth_client_id | default "" | quote }}
- name: KEYCLOAK_OAUTH_CLIENT_SECRET
  value: {{ .Values.auth.keycloak_oauth_client_secret | default "" | quote }}
- name: KEYCLOAK_SERVER_URL
  value: {{ .Values.auth.keycloak_server_url | default "" | quote }}
- name: KEYCLOAK_REALM
  value: {{ .Values.auth.keycloak_realm | default "" | quote }}
```

---

### 14. `optscale-deploy/optscale/templates/ngui.yaml`

**ADD** Keycloak environment variables in the `env` section:

```yaml
# ADD these environment variables:
- name: VITE_KEYCLOAK_URL
  value: {{ .Values.ngui.env.keycloak_url | default "" | quote }}
- name: VITE_KEYCLOAK_REALM
  value: {{ .Values.ngui.env.keycloak_realm | default "" | quote }}
- name: VITE_KEYCLOAK_CLIENT_ID
  value: {{ .Values.ngui.env.keycloak_client_id | default "" | quote }}
```

---

### 15. `optscale-deploy/overlay/user_template.yml`

**ADD** Keycloak configuration:

```yaml
auth:
  google_oauth_client_id: ""
  google_oauth_client_secret: ""
  microsoft_oauth_client_id: ""
  # ADD these lines:
  keycloak_oauth_client_id: ""
  keycloak_oauth_client_secret: ""
  keycloak_server_url: ""
  keycloak_realm: ""

ngui:
  env:
    build_mode: ""
    google_oauth_client_id: ""
    microsoft_oauth_client_id: ""
    # ADD these lines:
    keycloak_url: ""
    keycloak_realm: ""
    keycloak_client_id: ""
```

---

## New Files Created

### 16. `auth/auth_server/controllers/keycloak_role_sync.py` (NEW FILE)

```python
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
```

---

### 17. `ngui/ui/src/components/KeycloakSignInButton/KeycloakSignInButton.tsx` (NEW FILE)

```tsx
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
```

---

### 18. `ngui/ui/src/components/KeycloakSignInButton/index.ts` (NEW FILE)

```typescript
export { default } from "./KeycloakSignInButton";
```

---

### 19. `ngui/ui/src/containers/KeycloakCallbackContainer/KeycloakCallbackContainer.tsx` (NEW FILE)

```tsx
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
```

---

### 20. `ngui/ui/src/containers/KeycloakCallbackContainer/index.ts` (NEW FILE)

```typescript
export { default } from "./KeycloakCallbackContainer";
```

---

### 21. `ngui/ui/src/pages/KeycloakCallback/KeycloakCallback.tsx` (NEW FILE)

```tsx
import KeycloakCallbackContainer from "containers/KeycloakCallbackContainer";

const KeycloakCallback = () => <KeycloakCallbackContainer />;

export default KeycloakCallback;
```

---

### 22. `ngui/ui/src/pages/KeycloakCallback/index.ts` (NEW FILE)

```typescript
export { default } from "./KeycloakCallback";
```

---

### 23. `ngui/ui/src/utils/routes/keycloakCallbackRoute.ts` (NEW FILE)

```typescript
import { lazy } from "react";
import { KEYCLOAK_CALLBACK } from "urls";

export const KEYCLOAK_CALLBACK = "/keycloak-callback";

const KeycloakCallback = lazy(() => import("pages/KeycloakCallback"));

export default {
  key: "keycloak-callback",
  link: KEYCLOAK_CALLBACK,
  component: KeycloakCallback,
  layout: null,
  isTokenRequired: false
};
```

---

### 24. `ngui/ui/src/icons/KeycloakIcon/KeycloakIcon.tsx` (NEW FILE)

```tsx
import SvgIcon from "@mui/material/SvgIcon";

const KeycloakIcon = (props) => (
  <SvgIcon {...props} viewBox="0 0 24 24">
    <path d="M12 2L2 7v10l10 5 10-5V7L12 2zm0 2.18l7.27 3.64v7.27L12 18.73l-7.27-3.64V7.82L12 4.18z" />
    <path d="M12 6.55L7.64 9.09v5.82L12 17.45l4.36-2.54V9.09L12 6.55zm0 1.63l2.73 1.55v3.09L12 14.36l-2.73-1.54V9.73L12 8.18z" />
  </SvgIcon>
);

export default KeycloakIcon;
```

---

### 25. `ngui/ui/src/icons/KeycloakIcon/index.ts` (NEW FILE)

```typescript
export { default } from "./KeycloakIcon";
```

---

## Additional Modifications

### 26. `ngui/ui/src/utils/routes/index.ts`

**ADD** import and export for keycloakCallbackRoute:

```typescript
// ADD import:
import keycloakCallbackRoute from "./keycloakCallbackRoute";

// ADD to routes array:
export default [
  // ... existing routes
  keycloakCallbackRoute,
];
```

---

### 27. `ngui/ui/src/components/OAuthSignIn/OAuthSignIn.tsx`

**ADD** Keycloak button to the OAuth sign-in component:

```tsx
// ADD import:
import KeycloakSignInButton from "components/KeycloakSignInButton";

// ADD in the render (alongside Google and Microsoft buttons):
<KeycloakSignInButton
  handleSignIn={handleSignIn}
  isLoading={isLoading}
  disabled={disabled}
/>
```

---

### 28. `ngui/ui/.env.sample`

**ADD** Keycloak environment variables:

```
VITE_KEYCLOAK_URL=
VITE_KEYCLOAK_REALM=
VITE_KEYCLOAK_CLIENT_ID=
```

---

## Summary

Total files modified: **15**
Total new files created: **10**

After applying all these changes:
1. Rebuild the auth and ngui Docker images
2. Update `user_template.yml` with your Keycloak settings
3. Redeploy OptScale
4. Configure Keycloak client with redirect URI: `https://your-optscale-url/keycloak-callback`
