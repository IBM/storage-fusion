# User-Specific Token Authentication Guide

## Overview

The enhanced Query Service now supports **user-specific bearer tokens** for authentication. This ensures that queries are executed with the security context of the specific user, not the admin account. This is crucial for proper access control, audit trails, and security compliance.

## Authentication Flow Architecture

### Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    Application Startup                           │
│                                                                   │
│  1. Admin authenticates with OCP/Keycloak credentials           │
│  2. Admin bearer token is obtained and cached                   │
│  3. Domain and user lists are fetched using admin token         │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│              User Selection Phase                                 │
│                                                                   │
│  1. Admin selects a specific user (OCP or Keycloak)             │
│  2. System identifies user type (ocp or keycloak)               │
│  3. User-specific password is prompted                          │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│         User-Specific Authentication                             │
│                                                                   │
│  For OCP Users:                                                  │
│  ├─ Use: oc login <api-url> -u <username> -p <password>        │
│  ├─ Get: oc whoami -t  (get user's token)                       │
│  └─ Cache: Token cached with 24-hour expiry                     │
│                                                                   │
│  For Keycloak Users:                                             │
│  ├─ Use: POST /token with password grant flow                   │
│  ├─ Params: grant_type=password, username, password             │
│  └─ Cache: Token cached with server-provided expiry             │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│        Domain Authorization Check                                │
│                                                                   │
│  1. Check if user is assigned to selected domain                │
│  2. If NOT assigned: Return 403 Forbidden                        │
│  3. If assigned: Proceed to query execution                      │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│        Query Execution with User Token                           │
│                                                                   │
│  1. Use user's bearer token in Authorization header             │
│  2. Send: GET /query?table=<domain>&limit=<limit>               │
│  3. Response: Query results OR 401/403 error                    │
│                                                                   │
│  If 401: User token invalid/expired                             │
│  If 403: User not authorized for domain                         │
│  If 200: Execute LLM with results                               │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│        Audit & Session Logging                                   │
│                                                                   │
│  1. Log: Which user executed query                              │
│  2. Log: With which token (user_type, authentication status)    │
│  3. Log: Domain accessed                                         │
│  4. Save: Session history with authentication details           │
└─────────────────────────────────────────────────────────────────┘
```

## Key Components

### 1. UserAuthenticationManager

Located in `services/user_auth_manager.py`

**Responsibilities:**
- Authenticate OCP users using `oc login`
- Authenticate Keycloak users using password grant flow
- Cache user tokens with expiry tracking
- Handle token refresh
- Provide authorization headers

**Key Methods:**

```python
# Get token for a user (prompts for password if not provided)
token = user_auth_manager.get_user_token(
    username="kumar",
    user_type="keycloak",
    password="user-password"
)

# Get authorization headers ready for API calls
headers = user_auth_manager.get_user_auth_headers(
    username="kumar",
    user_type="keycloak",
    password="user-password"
)

# Check if token is valid
is_valid = user_auth_manager.is_user_token_valid("kumar")

# Get user info
info = user_auth_manager.get_user_info("kumar")
```

### 2. QueryService Updates

**New Method:**
```python
search_result = query_service.query_with_user_token(
    table="production-domain",
    username="kumar",
    user_type="keycloak",
    password="user-password"
)
```

**Response Handling:**

Success (200):
```json
{
  "success": true,
  "data": [...],
  "authenticated_user": "kumar",
  "user_type": "keycloak"
}
```

Unauthorized (401):
```json
{
  "success": false,
  "error": "Invalid or expired user token",
  "status_code": 401,
  "details": "User token is invalid or expired. Please re-authenticate.",
  "user": "kumar"
}
```

Forbidden (403):
```json
{
  "success": false,
  "error": "User does not have permission to access this resource",
  "status_code": 403,
  "details": "User 'kumar' is not added to this domain or does not have access.",
  "user": "kumar"
}
```

## Usage Examples

### Example 1: OCP User Query

```bash
cas> users select
Select user: admin

admin> domains select
Select domain: production

admin@production> query ask
Enter password for OCP user 'admin': ****
✓ User authenticated: admin
[admin@production] Enter your query: Show recent deployments

Processing query with user-specific authentication...
✓ User authenticated: admin
✓ Query executed successfully for user: admin

Getting AI response...
[AI Response shown here]
```

### Example 2: Keycloak User Query (Not in Domain)

```bash
cas> users select
Select user: kumar

kumar> domains select
Select domain: staging

kumar@staging> query ask
Enter password for Keycloak user 'kumar': ****
✓ User authenticated: kumar
✗ Query failed: User does not have permission to access this resource
✗ User 'kumar' is not added to this domain or does not have access.

[Admin needs to add 'kumar' to 'staging' domain first]
```

### Example 3: Keycloak User Query (Added to Domain)

```bash
# First, admin adds user to domain
admin@staging> domains assign
Enter username to assign: kumar
Assign 'kumar' to domain 'staging'? (y/n): y
✓ Assigned kumar to staging

# Then user can query
cas> users select
Select user: kumar

kumar> domains select
Select domain: staging

kumar@staging> query ask
Enter password for Keycloak user 'kumar': ****
✓ User authenticated: kumar
✓ User authenticated: kumar
[kubernetes clusters monitoring]

Getting AI response...
[AI Response shown here]
```

## Authentication Token Types

### OCP Token

**Obtained via:**
```bash
oc login <api-url> -u <username> -p <password>
oc whoami -t
```

**Characteristics:**
- Issued by OpenShift cluster
- Bearer token format
- Typical expiry: 24 hours
- User-specific access rights

**Example:**
```
Authorization: Bearer sha256~mZe...
```

### Keycloak Token

**Obtained via (password grant):**
```bash
POST /realms/master/protocol/openid-connect/token
grant_type=password
client_id=myapp
client_secret=***
username=kumar
password=***
```

**Response:**
```json
{
  "access_token": "eyJh...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "refresh_token": "..."
}
```

**Characteristics:**
- Issued by Keycloak IdP
- JWT token format
- Expiry from server (typically 1 hour)
- Can be refreshed using refresh_token

## Security Considerations

### 1. Password Handling

```python
# CLI prompts for password securely (not echoed)
from getpass import getpass
password = getpass(f"Enter password for {user_type} user '{username}': ")
```

### 2. Token Storage

- Tokens cached **in-memory** during session
- Cleared on application exit
- Never stored on disk
- Tokens associated with user context

### 3. Token Expiry

**OCP:** 24 hours (configurable in OpenShift)
**Keycloak:** Server-configured (typically 1 hour)

Automatic refresh when token expires.

### 4. Authorization Failures

**401 Unauthorized:**
- Token invalid or expired
- Token cache cleared
- User must re-authenticate

**403 Forbidden:**
- User not added to domain
- User lacks permissions
- Admin must grant access

## Configuration

### config.yaml Settings

```yaml
# Keycloak configuration for password grant
keycloak_url: "http://keycloak-server/realms/master/protocol/openid-connect/token"
client_id: "myapp"
client_secret: "some-secret"

# Console URL for OCP
console_url: "https://console-openshift-console.apps.your-cluster.com"

# Request timeout
request_timeout: 30
```

### Keycloak Setup Requirements

1. **Enable Direct Access Grants**
   - In Keycloak Admin Console
   - Select client "myapp"
   - Settings → Direct Access Grants Enabled → ON

2. **Ensure Client Credentials**
   - Get client_id and client_secret
   - Add to config.yaml
   - Ensure credentials have permission for password grant

3. **User Permissions**
   - User must be able to authenticate
   - User must have required roles/permissions
   - User must be added to domain access control list

## Troubleshooting

### OCP Authentication Fails

```bash
# Test manual login
oc login https://api.your-cluster.com:6443 -u <username> -p <password> --insecure-skip-tls-verify

# If fails, check:
# 1. Username and password correct
# 2. OpenShift cluster accessible
# 3. User has valid account in cluster
```

### Keycloak Authentication Fails

```bash
# Test with curl
curl -X POST "http://keycloak-server/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=myapp" \
  -d "client_secret=***" \
  -d "username=kumar" \
  -d "password=***"

# If fails, check:
# 1. Direct Access Grants enabled on client
# 2. Username and password correct in Keycloak
# 3. Client credentials correct
# 4. Keycloak server accessible
```

### Query Returns 403 Forbidden

```bash
# Check if user is added to domain
admin@domain> domains users

# If user not shown, add them:
admin@domain> domains assign
Enter username: kumar
```

### Token Expired During Query

System automatically:
1. Detects 401 response
2. Clears cached token
3. Prompts to re-authenticate
4. Retries query with new token

## Session History Tracking

Queries are logged with authentication details:

```json
{
  "timestamp": "2025-01-10T15:30:45.123456",
  "user": "kumar",
  "query": "Show recent logs",
  "domain": "production",
  "user_type": "keycloak",
  "authenticated": true,
  "authenticated_at": "2025-01-10T15:30:40.654321"
}
```

## Best Practices

1. **Always Select User Before Query**
   - Don't assume admin privileges
   - Explicitly select intended user
   - Verify user authentication succeeds

2. **Add Users to Domains First**
   - Admin must grant access
   - Users cannot query domains they're not added to
   - Proper access control maintained

3. **Review Audit Logs**
   - Check session history for query execution
   - Verify correct user/domain combinations
   - Track who ran what query when

4. **Handle Token Expiry**
   - System handles automatically
   - Long-running sessions may timeout
   - Re-authenticate if needed

5. **Security**
   - Never share user passwords
   - Don't store passwords in logs
   - Use environment variables for automation
   - Enable SSL verification in production

---

**Authentication Flow Ensures:**
- ✅ Proper user identification
- ✅ User-specific access control
- ✅ Audit trail of all queries
- ✅ Secure token management
- ✅ Domain access verification