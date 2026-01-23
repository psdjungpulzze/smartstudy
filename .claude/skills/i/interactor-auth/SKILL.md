---
name: interactor-auth
version: 3.0.0
description: Setup Interactor platform authentication with the Account Server. Use when integrating with Interactor for credential management, AI agents, or workflows. Covers administrator registration, organization management, application OAuth clients, user authentication, token management, and secret rotation.
author: Interactor Integration Guide
requires:
  - Bash (for curl commands and verification scripts)
  - Write (for environment file creation)
  - Read (for verifying configuration)
source_docs:
  - docs/i/account-server-docs/integration-guide.md
---

> **Source Documentation:** `docs/i/account-server-docs/integration-guide.md`
> For the latest API details, read the source documentation in the submodule.

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| 3.0.0 | 2026-01-22 | Major rewrite: Four-tier hierarchical auth (Administrator → Organization → Application/Users), named organizations, MFA support, user management endpoints, updated JWT claims with org context. |
| 1.1.0 | 2026-01-21 | Added: Token revocation, distributed caching, webhook verification, observability, SRE runbook, FAQ. Fixed: Issuer consistency, rate limit scope. |
| 1.0.0 | 2026-01-20 | Initial release |


# Account Server Integration Guide

**Version:** 3.0.0
**Last Updated:** 2026-01-22

---

## Quick Reference

All endpoints use the base URL: `https://auth.interactor.com/api/v1`

### Administrator Endpoints (Public)

| Action | Method | Endpoint | Auth Required |
|--------|--------|----------|---------------|
| Register | POST | `/admin/register` | No |
| Verify Email | GET/POST | `/admin/verify-email` | No |
| Login | POST | `/admin/login` | No |
| MFA Login | POST | `/admin/login/mfa` | No |
| Refresh Token | POST | `/admin/refresh` | No |
| Password Reset Request | POST | `/admin/password/reset-request` | No |
| Password Reset | POST | `/admin/password/reset` | No |

### Administrator Profile Endpoints (Admin JWT)

| Action | Method | Endpoint | Auth Required |
|--------|--------|----------|---------------|
| Get Profile | GET | `/admin` | Admin JWT |
| Update Profile | PATCH | `/admin` | Admin JWT |
| Logout | POST | `/admin/logout` | Admin JWT |
| Change Password | POST | `/admin/password/change` | Admin JWT |
| Enable MFA | POST | `/admin/mfa/enable` | Admin JWT |
| Verify MFA | POST | `/admin/mfa/verify` | Admin JWT |
| Disable MFA | POST | `/admin/mfa/disable` | Admin JWT |

### Organization Endpoints (Admin JWT)

| Action | Method | Endpoint | Auth Required |
|--------|--------|----------|---------------|
| List Orgs | GET | `/admin/orgs` | Admin JWT |
| Create Org | POST | `/admin/orgs` | Admin JWT |
| Get Org | GET | `/admin/orgs/:org_name` | Admin JWT |
| Update Org | PATCH | `/admin/orgs/:org_name` | Admin JWT |
| Delete Org | DELETE | `/admin/orgs/:org_name` | Admin JWT (owner) |

### Application Endpoints (Admin JWT + Org Context)

| Action | Method | Endpoint | Auth Required |
|--------|--------|----------|---------------|
| List Apps | GET | `/admin/orgs/:org_name/applications` | Admin JWT |
| Create App | POST | `/admin/orgs/:org_name/applications` | Admin JWT |
| Get App | GET | `/admin/orgs/:org_name/applications/:id` | Admin JWT |
| Update App | PATCH | `/admin/orgs/:org_name/applications/:id` | Admin JWT |
| Rotate Secret | POST | `/admin/orgs/:org_name/applications/:id/rotate-secret` | Admin JWT |
| Delete App | DELETE | `/admin/orgs/:org_name/applications/:id` | Admin JWT |

### OAuth Endpoint (Public)

| Action | Method | Endpoint | Auth Required |
|--------|--------|----------|---------------|
| Get Token | POST | `/oauth/token` | Client Credentials |

### User Management Endpoints (Admin or App JWT)

| Action | Method | Endpoint | Auth Required |
|--------|--------|----------|---------------|
| List Users | GET | `/orgs/:org_name/users` | Admin or App JWT |
| Create User | POST | `/orgs/:org_name/users` | Admin or App JWT |
| Get User | GET | `/orgs/:org_name/users/:user_id` | Admin or App JWT |
| Update User | PATCH | `/orgs/:org_name/users/:user_id` | Admin or App JWT |
| Delete User | DELETE | `/orgs/:org_name/users/:user_id` | Admin or App JWT |

### User Authentication Endpoints (Public)

| Action | Method | Endpoint | Auth Required |
|--------|--------|----------|---------------|
| User Login | POST | `/users/login` | No |
| User MFA Login | POST | `/users/login/mfa` | No |
| User Refresh | POST | `/users/refresh` | No |

---

## Overview

The Account Server provides a **four-tier hierarchical authentication system** for multi-tenant platforms:

```
Administrator (you sign up here)
    └── Organization (named container, e.g., "acme-corp")
            ├── Applications (your backend services)
            │   └── Get app JWT via OAuth 2.0 client credentials
            └── Users (your end users)
                └── Authenticate with username/password
```

### Key Concepts

- **Administrators** sign up and manage organizations
- **Organizations** are named containers (globally unique names like GitHub usernames)
- **Applications** are M2M OAuth clients for your backend services
- **Users** are end-users of your application

### Who This Guide Is For

This guide is for developers building applications that integrate with the Interactor platform. You'll use Account Server to:

1. **Register as an administrator** and create your first organization
2. **Create applications** that call Interactor APIs
3. **Manage users** for your application

### Base URL

```
Production: https://auth.interactor.com/api/v1
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     YOUR PLATFORM                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌───────────────────┐                                          │
│  │   Administrator   │ ← Admin JWT for management               │
│  │   (Admin Portal)  │                                          │
│  └─────────┬─────────┘                                          │
│            │ manages                                             │
│  ┌─────────┴─────────┐                                          │
│  │   Organization    │ ← Named container (e.g., "acme-corp")    │
│  │   (acme-corp)     │                                          │
│  └─────────┬─────────┘                                          │
│            │                                                     │
│  ┌─────────┴─────────────────────┐                              │
│  │                               │                               │
│  ▼                               ▼                               │
│  ┌───────────────┐    ┌───────────────┐                         │
│  │  Application  │    │     Users     │                         │
│  │  (Backend)    │    │  (End Users)  │                         │
│  │               │    │               │                         │
│  │ App JWT with  │    │ User JWT with │                         │
│  │ org claim     │    │ org claim     │                         │
│  └───────┬───────┘    └───────────────┘                         │
│          │                                                       │
│          │  API calls with App JWT                              │
│          ▼                                                       │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              Interactor / Knowledge Base                   │  │
│  │                                                            │  │
│  │  Validates JWT via JWKS, extracts org from token          │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Quick Start

### 1. Register as an Administrator

When you register, you create both your admin account and your first organization:

```bash
curl -X POST https://auth.interactor.com/api/v1/admin/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@yourcompany.com",
    "password": "SecureP@ssw0rd!",
    "org_name": "your-company"
  }'
```

**Organization Name Requirements:**
- 3-50 characters
- Lowercase letters, numbers, and hyphens only
- Must start with a letter
- Globally unique (like GitHub usernames)

**Password Requirements (Administrator):**
- Minimum 12 characters
- At least one uppercase letter
- At least one lowercase letter
- At least one number
- At least one special character

**Response:**
```json
{
  "message": "Registration successful. Please check your email to verify your account.",
  "admin_id": "adm_abc123",
  "verification_token": "..."
}
```

### 2. Verify Email

Click the verification link in your email, or call:

```bash
curl "https://auth.interactor.com/api/v1/admin/verify-email?token=YOUR_TOKEN"
```

### 3. Login as Administrator

```bash
curl -X POST https://auth.interactor.com/api/v1/admin/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@yourcompany.com",
    "password": "SecureP@ssw0rd!"
  }'
```

**Response:**
```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIs...",
  "refresh_token": "eyJhbGciOiJSUzI1NiIs...",
  "token_type": "Bearer",
  "expires_in": 900
}
```

### 4. Create an Application

Use your admin JWT to create an application within your organization:

```bash
curl -X POST https://auth.interactor.com/api/v1/admin/orgs/your-company/applications \
  -H "Authorization: Bearer <admin_access_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Production Backend",
    "description": "Main production server",
    "scopes": ["interactor:read", "interactor:write"]
  }'
```

**Response:**
```json
{
  "client_id": "app_xyz789",
  "client_secret": "sec_STORE_THIS_SECURELY",
  "name": "Production Backend",
  "scopes": ["interactor:read", "interactor:write"],
  "status": "active",
  "created_at": "2026-01-22T00:00:00Z"
}
```

> **Important:** Save the `client_secret` immediately. It is only shown once!

### 5. Get an Application Token

Your backend uses OAuth 2.0 client credentials to get an access token:

```bash
curl -X POST https://auth.interactor.com/api/v1/oauth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=app_xyz789&client_secret=sec_STORE_THIS_SECURELY"
```

**Response:**
```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIs...",
  "token_type": "Bearer",
  "expires_in": 900,
  "scope": "interactor:read interactor:write"
}
```

The app token contains an `org` claim with your organization name (e.g., `"org": "your-company"`).

### 6. Use the Token to Call APIs

```bash
curl https://core.interactor.com/api/v1/some-endpoint \
  -H "Authorization: Bearer <app_access_token>"
```

---

## User Management

Organizations and applications can create and manage users. Users authenticate with org + username + password and receive their own JWTs.

### Create a User

```bash
curl -X POST https://auth.interactor.com/api/v1/orgs/your-company/users \
  -H "Authorization: Bearer <admin_or_app_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "johndoe",
    "password": "Password123@",
    "email": "john@example.com",
    "metadata": {"department": "Engineering"}
  }'
```

**Password Requirements (User):**
- Minimum 8 characters
- At least one uppercase letter
- At least one lowercase letter
- At least one number
- At least one special character

**Response:**
```json
{
  "user_id": "usr_abc123",
  "username": "johndoe",
  "email": "john@example.com",
  "status": "active",
  "metadata": {"department": "Engineering"},
  "mfa_enabled": false,
  "created_at": "2026-01-22T00:00:00Z"
}
```

### User Login

Users authenticate with org name + username + password:

```bash
curl -X POST https://auth.interactor.com/api/v1/users/login \
  -H "Content-Type: application/json" \
  -d '{
    "org": "your-company",
    "username": "johndoe",
    "password": "Password123@"
  }'
```

**Response:**
```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIs...",
  "refresh_token": "eyJhbGciOiJSUzI1NiIs...",
  "token_type": "Bearer",
  "expires_in": 900
}
```

The user token contains an `org` claim and is valid for ALL applications in that organization.

### List Users

```bash
curl https://auth.interactor.com/api/v1/orgs/your-company/users \
  -H "Authorization: Bearer <admin_or_app_token>"
```

---

## Token Refresh

Access tokens expire after 15 minutes. Use refresh tokens to get new access tokens.

### Administrator Token Refresh

```bash
curl -X POST https://auth.interactor.com/api/v1/admin/refresh \
  -H "Content-Type: application/json" \
  -d '{"refresh_token": "eyJhbGciOiJSUzI1NiIs..."}'
```

### User Token Refresh

```bash
curl -X POST https://auth.interactor.com/api/v1/users/refresh \
  -H "Content-Type: application/json" \
  -d '{"refresh_token": "eyJhbGciOiJSUzI1NiIs..."}'
```

### Application Token Refresh

Applications don't have refresh tokens. Request a new token using client credentials when the current token expires.

---

## JWT Verification

Your applications should validate JWTs locally using the JWKS endpoint. This is fast and doesn't require calling Account Server on every request.

### JWKS Endpoint

```bash
curl https://auth.interactor.com/.well-known/jwks.json
```

### Token Claims by Type

**Administrator Token (`type: "admin"`):**
| Claim | Description |
|-------|-------------|
| `sub` | Administrator ID (`adm_*`) |
| `type` | `"admin"` |
| `email` | Administrator email |
| `scopes` | Granted scopes |

**Application Token (`type: "app"`):**
| Claim | Description |
|-------|-------------|
| `sub` | Client ID (`app_*`) |
| `type` | `"app"` |
| `client_id` | Application client ID |
| `org` | Organization name (e.g., `"your-company"`) |
| `scopes` | Granted scopes |

**User Token (`type: "user"`):**
| Claim | Description |
|-------|-------------|
| `sub` | User ID (`usr_*`) |
| `type` | `"user"` |
| `org` | Organization name (e.g., `"your-company"`) |
| `username` | Username |
| `scopes` | Granted scopes |

### Example: Node.js Verification

```typescript
import jwt from 'jsonwebtoken';
import jwksClient from 'jwks-rsa';

const client = jwksClient({
  jwksUri: 'https://auth.interactor.com/.well-known/jwks.json',
  cache: true,
  rateLimit: true
});

function getKey(header, callback) {
  client.getSigningKey(header.kid, (err, key) => {
    const signingKey = key?.getPublicKey();
    callback(err, signingKey);
  });
}

export function verifyToken(token: string): Promise<any> {
  return new Promise((resolve, reject) => {
    jwt.verify(token, getKey, {
      issuer: 'https://auth.interactor.com'
    }, (err, decoded) => {
      if (err) reject(err);
      else resolve(decoded);
    });
  });
}

// Verify and check token type
const claims = await verifyToken(token);
if (claims.type === 'app') {
  // Application token - use for M2M API calls
  console.log('App:', claims.client_id, 'Org:', claims.org);
} else if (claims.type === 'user') {
  // User token - use for user authentication
  console.log('User:', claims.username, 'Org:', claims.org);
}
```

---

## Multi-Factor Authentication (MFA)

Administrators can enable TOTP-based MFA for additional security.

### Enable MFA

```bash
curl -X POST https://auth.interactor.com/api/v1/admin/mfa/enable \
  -H "Authorization: Bearer <admin_access_token>"
```

**Response:**
```json
{
  "secret": "BASE32SECRET",
  "provisioning_uri": "otpauth://totp/AccountServer:admin@company.com?secret=...&issuer=AccountServer",
  "qr_code": "data:image/png;base64,..."
}
```

Display the QR code for the admin to scan with their authenticator app.

### Verify MFA Setup

```bash
curl -X POST https://auth.interactor.com/api/v1/admin/mfa/verify \
  -H "Authorization: Bearer <admin_access_token>" \
  -H "Content-Type: application/json" \
  -d '{"code": "123456"}'
```

### MFA Login Flow

When MFA is enabled, login returns an MFA challenge:

```json
{
  "mfa_required": true,
  "mfa_token": "mfa_session_xyz"
}
```

Complete the login with the MFA code:

```bash
curl -X POST https://auth.interactor.com/api/v1/admin/login/mfa \
  -H "Content-Type: application/json" \
  -d '{
    "mfa_token": "mfa_session_xyz",
    "code": "123456"
  }'
```

---

## Application Management

### List Applications

```bash
curl https://auth.interactor.com/api/v1/admin/orgs/your-company/applications \
  -H "Authorization: Bearer <admin_access_token>"
```

### Update Application

```bash
curl -X PATCH https://auth.interactor.com/api/v1/admin/orgs/your-company/applications/<id> \
  -H "Authorization: Bearer <admin_access_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Updated Name",
    "description": "Updated description"
  }'
```

### Rotate Client Secret

```bash
curl -X POST https://auth.interactor.com/api/v1/admin/orgs/your-company/applications/<id>/rotate-secret \
  -H "Authorization: Bearer <admin_access_token>"
```

**Response:**
```json
{
  "client_secret": "sec_NEW_SECRET",
  "previous_secret_expires_at": "2026-01-23T00:00:00Z"
}
```

The old secret remains valid for 24 hours to allow for rolling deployments.

### Delete Application

```bash
curl -X DELETE https://auth.interactor.com/api/v1/admin/orgs/your-company/applications/<id> \
  -H "Authorization: Bearer <admin_access_token>"
```

---

## Error Handling

All errors follow a consistent format:

```json
{
  "error": {
    "code": "error_code",
    "message": "Human-readable message"
  }
}
```

### Common Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `invalid_credentials` | 401 | Wrong email/password/username |
| `invalid_token` | 401 | Token is invalid or expired |
| `email_not_verified` | 403 | Administrator email not verified |
| `account_suspended` | 403 | Account has been suspended |
| `forbidden` | 403 | Permission denied |
| `not_found` | 404 | Resource not found |
| `conflict` | 409 | Resource already exists (duplicate) |
| `validation_error` | 422 | Request validation failed |
| `rate_limited` | 429 | Too many requests |

### Rate Limits

| Endpoint | Limit |
|----------|-------|
| `/admin/login` | 5 per minute per IP |
| `/admin/register` | 3 per hour per IP |
| `/users/login` | 10 per minute per IP |
| `/oauth/token` | 30 per minute per client_id |
| Authenticated endpoints | 100 per minute per token |

---

## ID Formats

All public IDs use prefixes for easy identification:

| Entity | Prefix | Example |
|--------|--------|---------|
| Administrator | `adm_` | `adm_Ro5o8o9t-M` |
| Application | `app_` | `app_isfZqMSUgiqf_KKzC3W6` |
| User | `usr_` | `usr_VuUVJd8cE6` |
| Client Secret | `sec_` | `sec_Lajg4iOkZBjmwaAwlaSXTSyULZ9mewcrVE88qNIne09T` |

---

## Best Practices

### Token Management

1. **Cache app tokens**: Don't request a new token for every API call
2. **Refresh proactively**: Refresh tokens before they expire (e.g., when < 60 seconds remaining)
3. **Handle expiration gracefully**: If a request fails with `invalid_token`, refresh and retry

### Secret Storage

1. **Never hardcode secrets**: Use environment variables or secrets managers
2. **Use secret rotation**: Rotate secrets periodically using the rotate endpoint
3. **Use separate apps per environment**: Don't share credentials between dev/staging/production

### User Management

1. **Usernames are per-org**: The same username can exist in different organizations
2. **Store user_id**: Reference users by `user_id`, not username
3. **User JWT is for authentication**: Your app handles authorization based on user claims
4. **User tokens are org-wide**: A user JWT is valid for all apps in the organization

---

## Troubleshooting

### "Invalid credentials" on login

- For administrators: verify email and password are correct, check if email is verified
- For users: ensure you're providing the correct `org` (organization name, not ID)

### "Invalid token" errors

- Access tokens expire after 15 minutes
- Use refresh tokens (admin/user) or client credentials (app) to get new tokens
- Verify you're using the correct token type for the endpoint

### "Token type mismatch"

- `/admin/*` endpoints require admin JWT
- `/admin/orgs/:org_name/*` endpoints require admin JWT with membership in that org
- `/orgs/:org_name/users/*` endpoints accept both admin and app JWT
- `/oauth/token` requires client credentials, not a JWT

### Application token not working

- Verify client_id and client_secret are correct
- Check that the application status is `active`
- Ensure the application has the required scopes

### User login fails

- Users need `org` (name) + `username` + `password`
- Username is unique per organization, not globally
- Check user status is `active`

### "Forbidden" on organization operations

- Verify you're a member of the organization
- Some operations (like delete) require owner role
- Check if the organization exists and is active
