# Keycloak Integration with OptScale - Complete Guide

This document provides a comprehensive guide for integrating Keycloak SSO (Single Sign-On) with OptScale.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Keycloak Configuration](#keycloak-configuration)
5. [OptScale Configuration](#optscale-configuration)
6. [Deployment](#deployment)
7. [Testing](#testing)
8. [Role Mapping](#role-mapping)
9. [Troubleshooting](#troubleshooting)

---

## Overview

The Keycloak integration allows users to authenticate with OptScale using their Keycloak credentials. Features include:

- **Single Sign-On (SSO)** - Users can login with Keycloak credentials
- **PKCE Support** - Enhanced security with Proof Key for Code Exchange
- **Automatic User Creation** - New users are automatically created in OptScale
- **Role Synchronization** - Keycloak roles are mapped to OptScale roles
- **Retry Logic** - Robust error handling with automatic retries

---

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Browser   │────▶│   OptScale  │────▶│  Keycloak   │
│             │◀────│   (ngui)    │◀────│   Server    │
└─────────────┘     └─────────────┘     └─────────────┘
                           │
                           ▼
                    ┌─────────────┐
                    │  OptScale   │
                    │   (auth)    │
                    └─────────────┘
```

**Flow:**
1. User clicks "Keycloak" button on OptScale login page
2. Browser redirects to Keycloak login page
3. User authenticates with Keycloak
4. Keycloak redirects back to OptScale with authorization code
5. OptScale backend exchanges code for tokens
6. User is created/updated in OptScale with mapped roles
7. User is logged into OptScale

---

## Prerequisites

- OptScale deployed on Kubernetes
- Keycloak server (version 18.0 or later recommended)
- Admin access to both OptScale and Keycloak
- Network connectivity between OptScale and Keycloak

---

## Keycloak Configuration

### Step 1: Create or Select a Realm

1. Login to Keycloak Admin Console: `https://your-keycloak-server/admin`
2. Create a new realm or use an existing one
3. Note the **realm name** (e.g., `VECTOR`)

### Step 2: Create an OpenID Connect Client

1. Go to **Clients** → **Create client**

2. **General Settings:**
   | Setting | Value |
   |---------|-------|
   | Client type | OpenID Connect |
   | Client ID | `your-client-id` (e.g., `Vector-FinOps`) |

3. **Capability config:**
   | Setting | Value |
   |---------|-------|
   | Client authentication | ON |
   | Authorization | OFF |

4. **Login settings:**
   | Setting | Value |
   |---------|-------|
   | Valid redirect URIs | `https://your-optscale-url/keycloak-callback` |
   | Valid post logout redirect URIs | `https://your-optscale-url/*` |
   | Web origins | `https://your-optscale-url` |

5. Click **Save**

### Step 3: Get Client Secret

1. Go to **Clients** → your client → **Credentials** tab
2. Copy the **Client secret**

### Step 4: Enable PKCE (Recommended)

1. Go to **Clients** → your client → **Advanced** tab
2. Under **Advanced settings**, set:
   - **Proof Key for Code Exchange Code Challenge Method**: `S256`

### Step 5: Create Roles for OptScale Mapping

1. Go to **Realm roles** → **Create role**
2. Create the following roles:

   | Role Name | Maps to OptScale |
   |-----------|------------------|
   | `optscale-admin` | Manager (highest privilege) |
   | `optscale-manager` | Manager |
   | `optscale-engineer` | Engineer |
   | `optscale-member` | Member (default) |

### Step 6: Assign Roles to Users

1. Go to **Users** → select a user
2. Click **Role mapping** tab
3. Click **Assign role**
4. Select the appropriate role (e.g., `optscale-admin`)
5. Click **Assign**

### Step 7: Ensure Email is Available in Token

1. Go to **Client scopes** → **email**
2. Verify it's included in the client's scopes
3. User's email must be set and verified in Keycloak

---

## OptScale Configuration

### Step 1: Edit user_template.yml

Edit the file: `optscale-deploy/overlay/user_template.yml`

```yaml
# Auth service configuration
auth:
  google_oauth_client_id: ""
  google_oauth_client_secret: ""
  microsoft_oauth_client_id: ""
  keycloak_oauth_client_id: "your-client-id"          # e.g., "Vector-FinOps"
  keycloak_oauth_client_secret: "your-client-secret"  # From Keycloak Credentials tab
  keycloak_server_url: "https://your-keycloak-server" # e.g., "https://keycloak.example.com"
  keycloak_realm: "your-realm"                        # e.g., "VECTOR"

# UI configuration
ngui:
  env:
    build_mode: ""
    google_oauth_client_id: ""
    microsoft_oauth_client_id: ""
    keycloak_url: "https://your-keycloak-server"      # Same as above
    keycloak_realm: "your-realm"                      # Same as above
    keycloak_client_id: "your-client-id"              # Same as above (no secret here!)
```

### Configuration Parameters

| Parameter | Location | Description |
|-----------|----------|-------------|
| `keycloak_oauth_client_id` | auth | Client ID from Keycloak |
| `keycloak_oauth_client_secret` | auth | Client secret from Keycloak |
| `keycloak_server_url` | auth | Keycloak server URL (without `/realms/...`) |
| `keycloak_realm` | auth | Keycloak realm name |
| `keycloak_url` | ngui.env | Keycloak server URL for frontend |
| `keycloak_realm` | ngui.env | Keycloak realm name for frontend |
| `keycloak_client_id` | ngui.env | Client ID for frontend |

---

## Deployment

### For New Installation

```bash
cd ~/optscale/optscale-deploy

# Activate virtual environment
source .venv/bin/activate

# Deploy with your configuration
python runkube.py --with-elk -o overlay/user_template.yml my-optscale local
```

### For Existing Installation (Update Configuration)

```bash
cd ~/optscale/optscale-deploy
source .venv/bin/activate

# Redeploy with updated configuration
python runkube.py --with-elk -o overlay/user_template.yml my-optscale local
```

### Verify Deployment

```bash
# Check pods are running
kubectl get pods | grep -E "auth|ngui"

# Verify Keycloak environment variables in ngui
kubectl exec deployment/ngui -- cat /usr/src/app/ui/build/config.js | grep -i keycloak

# Expected output:
# window.optscale.VITE_KEYCLOAK_URL='https://your-keycloak-server' ;
# window.optscale.VITE_KEYCLOAK_REALM='your-realm' ;
# window.optscale.VITE_KEYCLOAK_CLIENT_ID='your-client-id' ;
```

---

## Testing

### Step 1: Access Login Page

1. Open browser and go to: `https://your-optscale-url/login`
2. You should see the **Keycloak** login button

### Step 2: Test Login

1. Click the **Keycloak** button
2. You'll be redirected to Keycloak login page
3. Enter your Keycloak credentials
4. After successful authentication, you'll be redirected back to OptScale
5. You should now be logged in

### Step 3: Verify in Logs

```bash
# Watch auth logs during login
kubectl logs deployment/auth -f --tail=20

# Look for successful signin:
# INFO:auth.auth_server.controllers.token:Creating Token with parameters {'user_id': '...', 'provider': 'keycloak', 'register': False}
# INFO:tornado.access:201 POST /auth/v2/signin (10.x.x.x) xxxms
```

---

## Role Mapping

### How Role Mapping Works

When a user logs in via Keycloak:

1. **Roles are extracted** from the Keycloak token:
   - `realm_access.roles` - Realm-level roles
   - `resource_access.<client_id>.roles` - Client-level roles
   - `groups` - Group memberships (converted to roles)

2. **Roles are mapped** to OptScale roles:

   | Keycloak Role | OptScale Role | Priority |
   |---------------|---------------|----------|
   | `optscale-admin` | Manager | 3 (highest) |
   | `optscale-manager` | Manager | 3 |
   | `optscale-engineer` | Engineer | 2 |
   | `optscale-member` | Member | 1 |
   | (no matching role) | Member | 1 (default) |

3. **Highest privilege wins** - If user has multiple roles, the highest priority role is assigned

### Example Scenarios

| Keycloak Roles | OptScale Role |
|----------------|---------------|
| `optscale-admin` | Manager |
| `optscale-engineer` | Engineer |
| `optscale-admin`, `optscale-member` | Manager |
| `optscale-engineer`, `optscale-member` | Engineer |
| `some-other-role` | Member |
| (none) | Member |

### Verify Role Assignment

After login, check the logs:

```bash
kubectl logs deployment/auth --tail=50 | grep -i "role sync\|Access granted"

# Example output:
# INFO:auth.auth_server.controllers.keycloak_role_sync:Creating role assignment for user user@example.com: role=Manager (purpose=optscale_manager)
# INFO:auth.auth_server.controllers.base:Access granted: <Assignment type: organization user: user@example.com role: Manager resource: ...>
```

---

## Troubleshooting

### Issue: Keycloak button doesn't appear

**Cause:** Environment variables not set

**Solution:**
```bash
# Check if Keycloak env vars are set
kubectl exec deployment/ngui -- cat /usr/src/app/ui/build/config.js | grep -i keycloak

# If empty, verify user_template.yml and redeploy
```

### Issue: 404 Error on callback

**Cause:** Callback URL routing to wrong service

**Solution:** Ensure the callback URL is `/keycloak-callback` (not `/auth/keycloak/callback`)

Check ingress:
```bash
kubectl get ingress optscale -o yaml | grep -A5 "path:"
```

### Issue: "Authentication failed" error

**Cause:** Various - check logs

**Solution:**
```bash
# Check auth server logs
kubectl logs deployment/auth --tail=100 | grep -i error

# Common issues:
# - Wrong client secret
# - Redirect URI mismatch in Keycloak
# - Network connectivity to Keycloak
```

### Issue: User created but wrong role

**Cause:** Roles not configured in Keycloak or not in token

**Solution:**
1. Verify role exists in Keycloak: **Realm roles** → check for `optscale-*` roles
2. Verify role is assigned to user: **Users** → user → **Role mapping**
3. Verify role is in token: In Keycloak, go to **Clients** → client → **Client scopes** → ensure `roles` mapper is configured

### Issue: Connection timeout to Keycloak

**Cause:** Network issue or Keycloak server down

**Solution:**
```bash
# Test connectivity from auth pod
kubectl exec deployment/auth -- curl -I https://your-keycloak-server/realms/your-realm

# Check if retry logic is working
kubectl logs deployment/auth --tail=50 | grep -i "retry\|connection"
```

### View Detailed Logs

```bash
# Auth service logs
kubectl logs deployment/auth -f

# NGUI logs
kubectl logs deployment/ngui -f

# All logs with Keycloak references
kubectl logs deployment/auth --tail=200 | grep -i keycloak
```

---

## Files Modified for Integration

### Backend (auth service)

| File | Description |
|------|-------------|
| `auth/auth_server/controllers/signin.py` | KeycloakOauth2Provider with PKCE and retry logic |
| `auth/auth_server/controllers/keycloak_role_sync.py` | Role mapping service |
| `auth/auth_server/handlers/v2/signin.py` | API handler with Keycloak support |

### Frontend (ngui)

| File | Description |
|------|-------------|
| `ngui/ui/src/components/KeycloakSignInButton/` | Login button component |
| `ngui/ui/src/containers/KeycloakCallbackContainer/` | OAuth callback handler |
| `ngui/ui/src/pages/KeycloakCallback/` | Callback page |
| `ngui/ui/src/icons/KeycloakIcon/` | Keycloak icon |
| `ngui/ui/src/utils/routes/keycloakCallbackRoute.ts` | Route definition |
| `ngui/ui/src/utils/integrations.ts` | Keycloak configuration |
| `ngui/ui/src/utils/env.ts` | Environment variable schema |
| `ngui/ui/src/utils/constants.ts` | AUTH_PROVIDERS.KEYCLOAK constant |

### GraphQL

| File | Description |
|------|-------------|
| `ngui/ui/src/graphql/queries/auth/auth.graphql` | SignIn mutation with codeVerifier |
| `ngui/server/graphql/typeDefs/auth/auth.ts` | GraphQL schema |
| `ngui/server/graphql/resolvers/auth.ts` | GraphQL resolver |
| `ngui/server/api/auth/client.ts` | Auth API client |

### Deployment

| File | Description |
|------|-------------|
| `optscale-deploy/optscale/templates/auth.yaml` | Auth service Helm template |
| `optscale-deploy/optscale/templates/ngui.yaml` | NGUI service Helm template |
| `optscale-deploy/overlay/user_template.yml` | User configuration |

---

## Quick Reference

### URLs

| Component | URL |
|-----------|-----|
| OptScale Login | `https://your-optscale-url/login` |
| Keycloak Callback | `https://your-optscale-url/keycloak-callback` |
| Keycloak Admin | `https://your-keycloak-server/admin` |
| Keycloak Auth Endpoint | `https://your-keycloak-server/realms/{realm}/protocol/openid-connect/auth` |
| Keycloak Token Endpoint | `https://your-keycloak-server/realms/{realm}/protocol/openid-connect/token` |

### Environment Variables

| Variable | Service | Description |
|----------|---------|-------------|
| `KEYCLOAK_OAUTH_CLIENT_ID` | auth | Client ID |
| `KEYCLOAK_OAUTH_CLIENT_SECRET` | auth | Client secret |
| `KEYCLOAK_SERVER_URL` | auth | Server URL |
| `KEYCLOAK_REALM` | auth | Realm name |
| `VITE_KEYCLOAK_URL` | ngui | Server URL (frontend) |
| `VITE_KEYCLOAK_REALM` | ngui | Realm name (frontend) |
| `VITE_KEYCLOAK_CLIENT_ID` | ngui | Client ID (frontend) |

---

## Support

For issues or questions:
- Check the [Troubleshooting](#troubleshooting) section
- View logs: `kubectl logs deployment/auth` and `kubectl logs deployment/ngui`
- GitHub Issues: https://github.com/hystax/optscale/issues
