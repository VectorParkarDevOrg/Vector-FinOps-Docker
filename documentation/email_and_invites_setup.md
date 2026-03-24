# OptScale Email and Invites Setup Guide

This guide covers how to configure email sending in OptScale and use the invite system to create organization-restricted users.

---

## Table of Contents

1. [Email Configuration (SMTP)](#1-email-configuration-smtp)
2. [Creating Organization-Restricted Users](#2-creating-organization-restricted-users)
3. [API Reference](#3-api-reference)
4. [Troubleshooting](#4-troubleshooting)

---

## 1. Email Configuration (SMTP)

OptScale uses the **Herald** service to send emails. For emails to work, you must configure SMTP settings.

### 1.1 Configuration File

Edit the file: `/optscale-deploy/overlay/user_template.yml`

```yaml
# SMTP server and credentials used for sending emails
smtp:
  server: smtp.example.com       # SMTP server hostname
  email: "OptScale <noreply@example.com>"  # From address (can include display name)
  login: smtp-username           # SMTP login (optional - defaults to email if not set)
  port: 587                      # SMTP port (587 for TLS, 465 for SSL)
  password: smtp-password        # SMTP password or app password
  protocol: TLS                  # TLS or SSL
```

### 1.2 Common SMTP Provider Examples

#### Gmail
```yaml
smtp:
  server: smtp.gmail.com
  email: "OptScale <noreply@yourcompany.com>"
  login: your-account@gmail.com
  port: 587
  password: abcd-efgh-ijkl-mnop   # Gmail App Password (not regular password)
  protocol: TLS
```

> **Note:** For Gmail, you must use an [App Password](https://support.google.com/accounts/answer/185833). Enable 2FA first, then generate an App Password.

#### AWS SES
```yaml
smtp:
  server: email-smtp.us-east-1.amazonaws.com
  email: noreply@yourdomain.com
  login: YOUR_SMTP_USERNAME
  port: 587
  password: YOUR_SMTP_PASSWORD
  protocol: TLS
```

#### SendGrid
```yaml
smtp:
  server: smtp.sendgrid.net
  email: noreply@yourdomain.com
  login: apikey
  port: 587
  password: YOUR_SENDGRID_API_KEY
  protocol: TLS
```

#### Microsoft 365 / Outlook
```yaml
smtp:
  server: smtp.office365.com
  email: noreply@yourdomain.com
  login: your-account@yourdomain.com
  port: 587
  password: your-password
  protocol: TLS
```

#### Custom Mail Server
```yaml
smtp:
  server: mail.yourcompany.com
  email: noreply@yourcompany.com
  login: noreply@yourcompany.com
  port: 587
  password: your-password
  protocol: TLS
```

### 1.3 Apply Configuration

After updating `user_template.yml`, redeploy the cluster:

```bash
cd /optscale-deploy
./runkube.py --with-elk -o overlay/user_template.yml -- <deployment_name> <version>
```

Or restart the Herald service:

```bash
kubectl rollout restart deployment/herald-api
kubectl rollout restart deployment/herald-engine
```

### 1.4 Verify Email Configuration

Check Herald logs for email sending status:

```bash
kubectl logs -l app=herald-engine --tail=100 | grep -i email
```

---

## 2. Creating Organization-Restricted Users

OptScale supports multi-tenancy where users are restricted to specific organizations they're invited to.

### 2.1 Overview

- **Users see only organizations they belong to** - membership is based on employee records
- **Invites scope users automatically** - accepting an invite grants access only to that organization
- **Roles are per-organization** - a user can have different roles in different organizations

### 2.2 Step-by-Step: Invite a User via API

#### Step 1: Get Admin Token

```bash
curl -X POST https://your-optscale/auth/v2/tokens \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@yourcompany.com", "password": "your-password"}'
```

Response:
```json
{
  "token": "YOUR_AUTH_TOKEN",
  "user_id": "uuid",
  "user_email": "admin@yourcompany.com",
  "valid_until": "2026-02-12T10:00:00"
}
```

#### Step 2: List Organizations

```bash
curl -X GET https://your-optscale/restapi/v2/organizations \
  -H "Authorization: Bearer YOUR_AUTH_TOKEN"
```

Response:
```json
{
  "organizations": [
    {"id": "org-uuid-1", "name": "Client A Organization"},
    {"id": "org-uuid-2", "name": "Client B Organization"}
  ]
}
```

#### Step 3: Send Invite

```bash
curl -X POST https://your-optscale/restapi/v2/invites \
  -H "Authorization: Bearer YOUR_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "invites": {
      "newuser@example.com": [
        {
          "scope_id": "org-uuid-1",
          "scope_type": "organization",
          "purpose": "optscale_manager"
        }
      ]
    }
  }'
```

Response:
```json
{
  "invites": [
    {
      "id": "invite-uuid",
      "email": "newuser@example.com",
      "organization": "Client A Organization",
      "invite_assignments": [
        {
          "scope_id": "org-uuid-1",
          "scope_type": "organization",
          "purpose": "optscale_manager"
        }
      ]
    }
  ]
}
```

### 2.3 Available Roles

| Role | Purpose Value | Access Level |
|------|---------------|--------------|
| Manager | `optscale_manager` | Full organization management, invite users, manage settings |
| Engineer | `optscale_engineer` | Manage own resources, book environments, view reports |
| Member | `optscale_member` | Read-only access to organization data |

### 2.4 User Accepts the Invite

**Option A: Email Link (requires SMTP configured)**
- User receives email with invite link
- Clicks link, registers/signs in
- Accepts the invite

**Option B: Direct Link (if email not working)**
```
https://your-optscale/invited?email=newuser@example.com
```

**Option C: API Accept**
```bash
curl -X PATCH https://your-optscale/restapi/v2/invites/INVITE_UUID \
  -H "Authorization: Bearer USER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action": "accept"}'
```

### 2.5 Invite via Web UI

1. Sign in as admin to OptScale
2. Navigate to the target organization
3. Go to **Settings** -> **Users** -> **Invite**
4. Enter user's email address
5. Select role (Manager, Engineer, or Member)
6. Click **Send Invite**

### 2.6 Verify User Access

List employees in an organization:

```bash
curl -X GET "https://your-optscale/restapi/v2/organizations/ORG_UUID/employees?roles=true" \
  -H "Authorization: Bearer YOUR_AUTH_TOKEN"
```

---

## 3. API Reference

### Authentication

| Action | Method | Endpoint | Auth |
|--------|--------|----------|------|
| Get token (password) | POST | `/auth/v2/tokens` | None |
| Get token (OAuth) | POST | `/auth/v2/signin` | None |

### Organizations

| Action | Method | Endpoint | Auth |
|--------|--------|----------|------|
| List organizations | GET | `/restapi/v2/organizations` | Token |
| Get organization | GET | `/restapi/v2/organizations/{id}` | Token |

### Invites

| Action | Method | Endpoint | Auth |
|--------|--------|----------|------|
| Create invite | POST | `/restapi/v2/invites` | Token (Manager) |
| List invites | GET | `/restapi/v2/invites` | Token |
| Get invite | GET | `/restapi/v2/invites/{id}` | Token |
| Accept/Decline | PATCH | `/restapi/v2/invites/{id}` | Token |

### Employees

| Action | Method | Endpoint | Auth |
|--------|--------|----------|------|
| List employees | GET | `/restapi/v2/organizations/{id}/employees` | Token |
| Get employee | GET | `/restapi/v2/employees/{id}` | Token |

---

## 4. Troubleshooting

### 4.1 Emails Not Being Sent

**Symptom:** Invites created successfully but users don't receive emails.

**Check 1: SMTP Configuration**
```bash
# Verify SMTP is configured in user_template.yml
grep -A 7 "^smtp:" /optscale-deploy/overlay/user_template.yml
```

All fields must have values:
- `server` - SMTP hostname
- `email` - From address
- `port` - Usually 587 (TLS) or 465 (SSL)
- `password` - SMTP password
- `protocol` - TLS or SSL

**Check 2: Herald Service Logs**
```bash
kubectl logs -l app=herald-engine --tail=200 | grep -i "email\|smtp\|error"
```

**Check 3: Test SMTP Credentials**
```bash
# Test with Python
python3 -c "
import smtplib
server = smtplib.SMTP('smtp.example.com', 587)
server.starttls()
server.login('user@example.com', 'password')
print('SMTP connection successful')
server.quit()
"
```

**Workaround:** Use direct invite link:
```
https://your-optscale/invited?email=user@example.com
```

### 4.2 Invite Not Appearing for User

**Symptom:** User signs in but doesn't see pending invite.

**Check:** Ensure user signs in with the exact email address the invite was sent to (case-sensitive).

```bash
# List invites for specific email
curl -X GET "https://your-optscale/restapi/v2/invites?email=user@example.com" \
  -H "X-Secret: YOUR_CLUSTER_SECRET"
```

### 4.3 Permission Denied When Creating Invite

**Symptom:** 403 Forbidden error when creating invite.

**Cause:** User must be a Manager in the organization to invite others.

**Check current user's role:**
```bash
curl -X GET "https://your-optscale/restapi/v2/organizations/ORG_UUID/employees?roles=true" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### 4.4 User Can See Multiple Organizations

**Symptom:** User should only see one organization but sees multiple.

**Cause:** User was invited to or created multiple organizations.

**Solution:** Remove employee record from unwanted organizations:
```bash
curl -X DELETE "https://your-optscale/restapi/v2/employees/EMPLOYEE_UUID" \
  -H "Authorization: Bearer ADMIN_TOKEN"
```

---

## 5. Architecture Reference

### Email Flow
```
REST API (invite creation)
    |
    v
HeraldClient.email_send()
    |
    v
Herald API -> RabbitMQ Queue
    |
    v
Herald Engine (consumer)
    |
    v
EmailProcessor -> EmailGenerator -> EmailSender
    |
    v
SMTP Server -> User's Inbox
```

### Key Files

| Component | File Path |
|-----------|-----------|
| Invite Handler | `rest_api/rest_api_server/handlers/v2/invites.py` |
| Invite Controller | `rest_api/rest_api_server/controllers/invite.py` |
| Employee Controller | `rest_api/rest_api_server/controllers/employee.py` |
| Email Sender | `herald/modules/email_sender/sender.py` |
| Email Templates | `herald/modules/email_generator/templates/` |
| SMTP Config | `optscale-deploy/overlay/user_template.yml` |

---

## 6. Quick Reference Commands

```bash
# Get auth token
curl -X POST https://optscale/auth/v2/tokens \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@example.com", "password": "pass"}'

# List organizations
curl -X GET https://optscale/restapi/v2/organizations \
  -H "Authorization: Bearer TOKEN"

# Send invite
curl -X POST https://optscale/restapi/v2/invites \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"invites": {"user@example.com": [{"scope_id": "ORG_UUID", "scope_type": "organization", "purpose": "optscale_manager"}]}}'

# Accept invite
curl -X PATCH https://optscale/restapi/v2/invites/INVITE_UUID \
  -H "Authorization: Bearer USER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action": "accept"}'

# List org employees
curl -X GET "https://optscale/restapi/v2/organizations/ORG_UUID/employees?roles=true" \
  -H "Authorization: Bearer TOKEN"
```
