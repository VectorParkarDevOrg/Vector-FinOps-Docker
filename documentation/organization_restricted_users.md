# How to Create Organization-Restricted Users in OptScale

## Your Use Case
You have one OptScale instance with 2-3 organizations for different clients. You need to give each client credentials that only allow access to their specific organization.

---

## Step-by-Step Guide

### Step 1: Get Your Admin Token
First, sign in as an admin user to get an authentication token.

```bash
curl -X POST https://your-optscale/auth/v2/signin \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@yourcompany.com", "password": "your-password"}'
```

Response includes your `token` for subsequent requests.

---

### Step 2: Find Your Organization UUIDs
List all organizations to get their UUIDs:

```bash
curl -X GET https://your-optscale/restapi/v2/organizations \
  -H "Authorization: Bearer YOUR_TOKEN"
```

Response:
```json
{
  "organizations": [
    {"id": "org-uuid-client-a", "name": "Client A"},
    {"id": "org-uuid-client-b", "name": "Client B"},
    {"id": "org-uuid-client-c", "name": "Client C"}
  ]
}
```

Save each organization's `id` for the next step.

---

### Step 3: Invite Client Users to Their Organization (Recommended Method)

Use the invite system to add users restricted to specific organizations:

```bash
curl -X POST https://your-optscale/restapi/v2/invites \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "invites": {
      "clientA-user@example.com": [
        {
          "scope_id": "org-uuid-client-a",
          "scope_type": "organization",
          "purpose": "optscale_manager"
        }
      ]
    }
  }'
```

**Role Options (`purpose` field):**
| Role | Access Level |
|------|--------------|
| `optscale_manager` | Full org management (recommended for client admins) |
| `optscale_engineer` | Manage own resources, book environments |
| `optscale_member` | Read-only access |

---

### Step 4: Client Accepts the Invite

The client receives an email with an invite link. They:
1. Click the link or go to OptScale
2. Register/sign in with their email
3. Accept the invite

Or programmatically:
```bash
curl -X PATCH https://your-optscale/restapi/v2/invites/INVITE_UUID \
  -H "Authorization: Bearer CLIENT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action": "accept"}'
```

---

### Step 5: Verify User Access

Check that the user is properly assigned to the organization:

```bash
curl -X GET "https://your-optscale/restapi/v2/organizations/ORG_UUID/employees?roles=true" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

---

## Alternative: Via the UI

1. **Sign in** as admin to OptScale web interface
2. **Navigate** to the organization you want to add users to
3. **Go to** Settings -> Users/Employees -> Invite
4. **Enter** the client's email address
5. **Select** their role (Manager, Engineer, or Member)
6. **Send** the invite

The client will receive an email invitation restricted to that specific organization only.

---

## Key Points

- **Users are restricted by organization membership** - they can only see/access organizations where they have an employee record
- **Invites automatically scope users** - when a user accepts an invite for Org A, they only get access to Org A
- **Multiple orgs = multiple invites** - if a user needs access to multiple orgs, invite them to each separately
- **Roles are per-organization** - a user can be a Manager in Org A and a Member in Org B

---

## Quick Reference: API Endpoints

| Action | Method | Endpoint |
|--------|--------|----------|
| Sign in | POST | `/auth/v2/signin` |
| List organizations | GET | `/restapi/v2/organizations` |
| Send invite | POST | `/restapi/v2/invites` |
| Accept invite | PATCH | `/restapi/v2/invites/{id}` |
| List org employees | GET | `/restapi/v2/organizations/{id}/employees` |

---

## Files for Reference (if customization needed)

- Invite handler: `rest_api/rest_api_server/handlers/v2/invites.py`
- Employee controller: `rest_api/rest_api_server/controllers/employee.py`
- Auth assignment: `auth/auth_server/controllers/assignment.py`
