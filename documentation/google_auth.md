# Configure login with Google, Microsoft, and Keycloak authentication

To enable Google, Microsoft, and Keycloak login on your cluster, follow these instructions.

## Google

1\. Go to https://console.cloud.google.com/apis/credentials.

2\. Open *CREATE CREDENTIALS* → *OAuth Client ID* → *Web application* → in the *Authorized JavaScript origins* section, insert the URL of your OptScale cluster → *Create*.

3\. Copy *Client ID* and *Client secret*.

4\. Go to your `optscale-deploy` repository:

```
$ cd ~/optscale/optscale-deploy/
```

5\. Insert *Client ID* and *Client secret* copied on the third step into the `auth` and `ngui` sections:

-   [optscale-deploy/overlay/user_template.yml#L89](https://github.com/hystax/optscale/blob/integration/optscale-deploy/overlay/user_template.yml#L89), 

-   [optscale-deploy/overlay/user_template.yml#L90](https://github.com/hystax/optscale/blob/integration/optscale-deploy/overlay/user_template.yml#L90),

-   [optscale-deploy/overlay/user_template.yml#L96](https://github.com/hystax/optscale/blob/integration/optscale-deploy/overlay/user_template.yml#L96).

6\. Launch the command to restart the OptScale with the updated overlay:

```
./runkube.py --with-elk -o overlay/user_template.yml -- <deployment name> <version>
```

## Microsoft

1\. Go to your Microsoft account.

2\. *All services* → *App Registrations* → select the application → Manage → *Authentication* → add a platform → *Single-page applications* → add two valid redirect URIs. For example, `https://your-optscale.com/login` and `https://your-optscale.com/register`.

3\. Go to *App Registration* → *Overview* → *Application* → copy *client_id*.

4\. Go to your `optscale-deploy` repository:

```
$ cd ~/optscale/optscale-deploy/
```

5\. Insert *client_id* copied on the third step into the `auth` and `ngui` sections: 

-   [optscale-deploy/overlay/user_template.yml#L97](https://github.com/hystax/optscale/blob/integration/optscale-deploy/overlay/user_template.yml#L97),

-   [optscale-deploy/overlay/user_template.yml#L91](https://github.com/hystax/optscale/blob/integration/optscale-deploy/overlay/user_template.yml#L91).

6\. Launch the command to restart the OptScale with the updated overlay:

```
./runkube.py --with-elk -o overlay/user_template.yml -- <deployment name> <version>
```

## Keycloak

### Prerequisites

- A running Keycloak server (version 18.0 or later recommended)
- Administrative access to Keycloak to create and configure realms and clients

### Step 1: Create or Select a Realm

1\. Log in to your Keycloak Admin Console (typically at `https://your-keycloak-server/admin`).

2\. Create a new realm or use an existing one. Note the realm name (e.g., `optscale`).

### Step 2: Create an OpenID Connect Client

1\. In your realm, go to *Clients* → *Create client*.

2\. Configure the client:
   - **Client type**: OpenID Connect
   - **Client ID**: `optscale` (or your preferred name)
   - **Client authentication**: ON (for confidential client)
   - **Authorization**: OFF (unless you need fine-grained authorization)

3\. Click *Next* and configure access settings:
   - **Valid redirect URIs**: `https://your-optscale.com/auth/keycloak/callback`
   - **Valid post logout redirect URIs**: `https://your-optscale.com/login`
   - **Web origins**: `https://your-optscale.com` or `+` for all valid redirect URIs

4\. Click *Save*.

5\. Go to the *Credentials* tab and copy the **Client secret**.

### Step 3: Configure PKCE (Recommended)

For enhanced security, enable PKCE:

1\. In the client settings, go to *Advanced* → *Advanced settings*.

2\. Set **Proof Key for Code Exchange Code Challenge Method** to `S256`.

### Step 4: Configure Role Mapping (Optional)

OptScale can sync user roles from Keycloak. To enable this:

1\. Create realm roles or client roles with the following names:
   - `optscale-admin` or `optscale-manager` → Maps to OptScale Manager role
   - `optscale-engineer` → Maps to OptScale Engineer role
   - `optscale-member` → Maps to OptScale Member role (default)

2\. Assign these roles to users or groups in Keycloak.

3\. Ensure roles are included in the token:
   - Go to *Client scopes* → `roles` → *Mappers*
   - Verify that `realm roles` and `client roles` mappers are configured to add roles to tokens.

### Step 5: Configure OptScale

1\. Go to your `optscale-deploy` repository:

```
$ cd ~/optscale/optscale-deploy/
```

2\. Edit the `overlay/user_template.yml` file and configure the Keycloak settings:

**In the `auth` section:**

```yaml
auth:
  keycloak_oauth_client_id: "optscale"
  keycloak_oauth_client_secret: "your-client-secret-here"
  keycloak_server_url: "https://your-keycloak-server"
  keycloak_realm: "optscale"
```

**In the `ngui.env` section:**

```yaml
ngui:
  env:
    keycloak_url: "https://your-keycloak-server"
    keycloak_realm: "optscale"
    keycloak_client_id: "optscale"
```

3\. Launch the command to restart OptScale with the updated overlay:

```
./runkube.py --with-elk -o overlay/user_template.yml -- <deployment name> <version>
```

### Troubleshooting

**"Keycloak is not configured" error on login page:**
- Verify that `keycloak_url`, `keycloak_realm`, and `keycloak_client_id` are set in the `ngui.env` section.

**"Authentication failed" after Keycloak login:**
- Check that the redirect URI in Keycloak matches exactly: `https://your-optscale.com/auth/keycloak/callback`
- Verify the client secret is correct in the `auth` section.
- Check Keycloak server logs for detailed error messages.

**Roles not syncing:**
- Ensure roles are configured in Keycloak with the correct names (`optscale-admin`, `optscale-manager`, `optscale-engineer`, `optscale-member`).
- Verify that role mappers are configured to include roles in the access token.
- Check that the user has been assigned the appropriate roles in Keycloak.

**Connection timeout errors:**
- Verify network connectivity between OptScale and Keycloak server.
- Check if Keycloak server is running and accessible.
- Review firewall rules to ensure the required ports are open.

