import base64
import json
import logging
import os
import random
import string
import time
from urllib.parse import urlencode

import jwt
import requests
from requests.exceptions import ConnectionError, Timeout
from cryptography.hazmat.primitives.asymmetric.rsa import RSAPublicNumbers
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization

from google.oauth2 import id_token
from google.auth.transport import requests as google_requests

from auth.auth_server.controllers.base import BaseController
from auth.auth_server.controllers.base_async import BaseAsyncControllerWrapper
from auth.auth_server.controllers.token import TokenController
from auth.auth_server.controllers.user import UserController
from auth.auth_server.exceptions import Err
from auth.auth_server.utils import (
    check_kwargs_is_empty, pop_or_raise, check_string_attribute)
from tools.optscale_exceptions.common_exc import (
    WrongArgumentsException, ForbiddenException)

LOG = logging.getLogger(__name__)


class AzureVerifyTokenError(Exception):
    pass


class KeycloakVerifyTokenError(Exception):
    pass


class InvalidAuthorizationToken(Exception):
    def __init__(self, details):
        super().__init__('Invalid authorization token: ' + details)


class GoogleOauth2Provider:
    DEFAULT_TOKEN_URI = 'https://oauth2.googleapis.com/token'

    def __init__(self):
        self._client_id = os.environ.get('GOOGLE_OAUTH_CLIENT_ID')
        self._client_secret = os.environ.get('GOOGLE_OAUTH_CLIENT_SECRET')

    def client_id(self):
        if not self._client_id:
            raise ForbiddenException(Err.OA0012, [])
        return self._client_id

    def client_secret(self):
        if not self._client_secret:
            raise ForbiddenException(Err.OA0012, [])
        return self._client_secret

    def exchange_token(self, code, redirect_uri):
        request_body = {
            "grant_type": 'authorization_code',
            "client_secret": self.client_secret(),
            "client_id": self.client_id(),
            "code": code,
            'redirect_uri': redirect_uri,
        }
        request = google_requests.Request()
        response = request(
            url=self.DEFAULT_TOKEN_URI,
            method="POST",
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            body=urlencode(request_body).encode("utf-8"),
        )
        response_body = (
            response.data.decode("utf-8")
            if hasattr(response.data, "decode")
            else response.data
        )
        if response.status != 200:
            raise ValueError(response_body)
        response_data = json.loads(response_body)
        return response_data['id_token']

    def verify(self, code, **kwargs):
        try:
            redirect_uri = kwargs.pop('redirect_uri', None)
            token = self.exchange_token(code, redirect_uri)
            token_info = id_token.verify_oauth2_token(
                token, google_requests.Request(), self.client_id())
            if not token_info.get('email_verified', False):
                raise ForbiddenException(Err.OA0012, [])
            email = token_info['email']
            name = token_info.get('name', email)
            return email, name
        except (ValueError, KeyError) as ex:
            LOG.error(str(ex))
            raise ForbiddenException(Err.OA0012, [])


class MicrosoftOauth2Provider:
    def __init__(self):
        self._client_id = os.environ.get('MICROSOFT_OAUTH_CLIENT_ID')
        self.config_url = ("https://login.microsoftonline.com/common/v2.0/."
                           "well-known/openid-configuration")

    def client_id(self):
        if not self._client_id:
            raise ForbiddenException(Err.OA0012, [])
        return self._client_id

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

    def get_token_info(self, token):
        headers = jwt.get_unverified_header(token)
        if not headers:
            raise InvalidAuthorizationToken('missing headers')
        try:
            return headers['kid'], headers['alg']
        except KeyError:
            raise InvalidAuthorizationToken(f'invalid headers: {headers}')

    def get_azure_data(self, tenant_id=None):
        resp = requests.get(self.config_url, timeout=30)
        if not resp.ok:
            raise AzureVerifyTokenError(
                f'Received {resp.status_code} response '
                f'code from {self.config_url}')
        try:
            config_map = resp.json()
        except (ValueError, TypeError, KeyError):
            raise AzureVerifyTokenError(
                f'Received malformed response from {self.config_url}')
        try:
            issuer = config_map['issuer'].format(
                tenantid=tenant_id) if tenant_id else None
            jwks_uri = config_map['jwks_uri']
        except KeyError:
            raise AzureVerifyTokenError(f'Invalid config map: {config_map}')

        resp = requests.get(jwks_uri, timeout=30)
        if not resp.ok:
            raise AzureVerifyTokenError(
                f'Received {resp.status_code} response code from {jwks_uri}')
        try:
            jwks = resp.json()
        except (ValueError, TypeError, KeyError):
            raise AzureVerifyTokenError(
                f'Received malformed response from {jwks_uri}')
        return {
            'issuer': issuer,
            'jwks': jwks,
            'aud': [self.client_id()]
        }

    def get_jwk(self, kid, jwks):
        keys = jwks.get('keys')
        if not isinstance(keys, list):
            raise AzureVerifyTokenError(f'Invalid jwks: {jwks}')
        for jwk in keys:
            if jwk.get('kid') == kid:
                return jwk
        raise InvalidAuthorizationToken('kid not recognized')

    def get_public_key(self, kid, jwks):
        jwk = self.get_jwk(kid, jwks)
        return self.rsa_pem_from_jwk(jwk)

    def verify(self, token, **kwargs):
        try:
            tenant_id = kwargs.pop('tenant_id', None)
            kid, alg = self.get_token_info(token)
            azure_data = self.get_azure_data(tenant_id)
            public_key = self.get_public_key(kid, azure_data['jwks'])

            result = jwt.decode(token, public_key,
                                audience=azure_data['aud'],
                                issuer=azure_data['issuer'],
                                algorithms=[alg])
            email = result['preferred_username']
            name = result.get('name', email)
            return email, name
        except (InvalidAuthorizationToken, AzureVerifyTokenError,
                jwt.PyJWTError) as ex:
            LOG.error(str(ex))
            raise ForbiddenException(Err.OA0012, [])


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


class SignInController(BaseController):
    def __init__(self, db_session, config=None):
        self._user_ctl = None
        self._token_ctl = None
        super().__init__(db_session, config)

    @property
    def user_ctl(self):
        if not self._user_ctl:
            self._user_ctl = UserController(self._session, self._config)
        return self._user_ctl

    @property
    def token_ctl(self):
        if not self._token_ctl:
            self._token_ctl = TokenController(self._session, self._config)
        return self._token_ctl

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

    @staticmethod
    def _get_verifier_class(provider):
        return {
            'google': GoogleOauth2Provider,
            'microsoft': MicrosoftOauth2Provider,
            'keycloak': KeycloakOauth2Provider
        }.get(provider)

    @staticmethod
    def _gen_password():
        return ''.join(random.choice(
            string.digits + string.ascii_letters + string.punctuation
        ) for _ in range(33))

    def signin(self, **kwargs):
        provider, token, ip, tenant_id, redirect_uri, code_verifier = self._get_input(
            **kwargs)
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


class SignInAsyncController(BaseAsyncControllerWrapper):
    def _get_controller_class(self):
        return SignInController
