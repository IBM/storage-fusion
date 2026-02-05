# Updated Authentication Architecture - Complete User-Specific Token Flow

## What's New

This update implements **proper user-specific authentication** for query execution, ensuring that:

1. ✅ Queries are executed with user-specific bearer tokens, NOT admin tokens
2. ✅ Each user must authenticate with their own password
3. ✅ Domain access control is enforced (user must be added to domain)
4. ✅ Audit trail shows which user executed which query
5. ✅ Token expiry is properly handled with re-authentication
6. ✅ Security context is maintained throughout the query lifecycle

## New Components Added

### 1. **UserAuthenticationManager** (`services/user_auth_manager.py`) - NEW FILE

This is the core component managing user-specific authentication.

**Key Features:**
- Authenticates OCP users via `oc login`
- Authenticates Keycloak users via password grant flow
- Caches tokens with expiry tracking
- Handles token refresh and validation
- Provides authorization headers for API calls

**Key Methods:**

```python
# Authenticate OCP user
success, token = auth_mgr.authenticate_ocp_user("admin", password="***")

# Authenticate Keycloak user  
success, token = auth_mgr.authenticate_keycloak_user("kumar", password="***")

# Get or retrieve user token
token = auth_mgr.get_user_token("kumar", "keycloak", password="***")

# Get HTTP headers with user's token
headers = auth_mgr.get_user_auth_headers("kumar", "keycloak", password="***")

# Check if token still valid
is_valid = auth_mgr.is_user_token_valid("kumar")

# Clear token cache
auth_mgr.clear_user_token("kumar")
```

### 2. **Enhanced QueryService** (`services/query_service.py`) - UPDATED

New method: `query_with_user_token()`

**Signature:**
```python
def query_with_user_token(
    self,
    table: Optional[str] = None,
    limit: Optional[int] = None,
    username: Optional[str] = None,  # REQUIRED
    user_type: str = "ocp",  # "ocp" or "keycloak"
    password: Optional[str] = None,  # Will prompt if not provided
    use_cache: bool = True
) -> Dict[str, Any]:
```

**Features:**
- Uses `UserAuthenticationManager` to get user token
- Adds user token to Authorization header
- Handles 401 (token invalid) and 403 (not authorized) responses
- Clears expired tokens automatically
- Caches results per-user per-domain

### 3. **Updated ChatbotCLI** (`cli/chatbot_cli.py`) - UPDATED

**New `cmd_query_ask()` Flow:**

1. **Verify User Selected**
   ```
   if not self.current_user:
       Error: "No user selected"
       return
   ```

2. **Determine User Type**
   ```
   Check if user in ocp_users or keycloak_users
   user_type = "ocp" or "keycloak"
   ```

3. **Prompt for Password**
   ```
   password = getpass(f"Enter password for {user_type} user '{username}': ")
   ```

4. **Authenticate User**
   ```
   success, token = user_auth_manager.authenticate_ocp_user(username, password)
   OR
   success, token = user_auth_manager.authenticate_keycloak_user(username, password)
   ```

5. **Verify Domain Access**
   ```
   domain_users = domain_service.get_assigned_users(domain)
   if user not in domain_users:
       Error: "User is not assigned to this domain"
       return
   ```

6. **Execute Query with User Token**
   ```
   search_result = query_service.query_with_user_token(
       table=domain,
       username=username,
       user_type=user_type,
       password=password
   )
   ```

7. **Handle Response**
   ```
   if status_code == 401:
       Error: "Invalid or expired user token"
   elif status_code == 403:
       Error: "User not authorized for this domain"
   elif status_code == 200:
       Continue to LLM
   ```

8. **Execute LLM and Log Session**
   ```
   llm_service.call_llm(search_result, query)
   session_manager.add_query(user, query, domain, user_type, authenticated=True)
   ```

### 4. **Updated SessionManager** (`cli/middleware.py`) - UPDATED

**Enhanced `add_query()` method:**

```python
def add_query(self, user: str, query: str, domain: Optional[str] = None, 
             answer: str = "", user_type: str = "ocp", authenticated: bool = False):
```

**Session Record Example:**
```json
{
  "timestamp": "2025-01-10T15:30:45.123456",
  "user": "kumar",
  "query": "Show recent deployments",
  "domain": "production",
  "answer": "...",
  "user_type": "keycloak",
  "authenticated": true,
  "authenticated_at": "2025-01-10T15:30:40.654321"
}
```

### 5. **Updated main.py** - UPDATED

**Service Initialization:**

```python
# Initialize User Authentication Manager
services['user_auth'] = UserAuthenticationManager(config=config, logger=logger)

# Pass user_auth_manager to QueryService
services['query'] = QueryService(
    config=config,
    logger=logger,
    cache_service=services['cache'],
    auth_service=services['auth'],
    user_auth_manager=services['user_auth']  # NEW
)
```

## Complete Authentication Flow

### Scenario 1: Admin User Query

```
STEP 1: Application Startup
├─ Admin authenticates with OCP credentials
├─ Admin token obtained: sha256~xyz...
└─ Admin privileges granted

STEP 2: User Selection
├─ Admin selects user: "admin" (self)
├─ User type determined: "ocp"
└─ Ready for query

STEP 3: Query Execution
├─ Password prompted: getpass("Enter password for OCP user 'admin': ")
├─ User authenticates via oc login
├─ User token obtained: sha256~admin-token...
├─ Domain access verified: admin in ["admin", "developer"]
├─ Query API called with user token:
│  Authorization: Bearer sha256~admin-token...
│  GET /query?table=production&limit=5
├─ Response: 200 OK with data
├─ LLM called with results
└─ Session logged: {user: "admin", authenticated: true, user_type: "ocp"}
```

### Scenario 2: Keycloak User Query (Authorized)

```
STEP 1: Application Startup
├─ Admin authenticates to Keycloak (client credentials)
├─ Admin token obtained: eyJhbGc...
└─ Admin privileges granted

STEP 2: User Selection
├─ Admin selects user: "kumar"
├─ User type determined: "keycloak" (found in idp users)
└─ Ready for query

STEP 3: Query Execution
├─ Password prompted: getpass("Enter password for Keycloak user 'kumar': ")
├─ User authenticates via Keycloak password grant:
│  POST /token
│  grant_type=password
│  username=kumar
│  password=***
├─ User token obtained: eyJhbGc...kumar-token...
├─ Domain "staging" selected
├─ Domain access verified: kumar in ["admin", "kumar", "dev-lead"]
├─ Query API called with user token:
│  Authorization: Bearer eyJhbGc...kumar-token...
│  GET /query?table=staging&limit=5
├─ Response: 200 OK with data
├─ LLM called with results
└─ Session logged: {user: "kumar", authenticated: true, user_type: "keycloak"}
```

### Scenario 3: Keycloak User Query (NOT Authorized)

```
STEP 1-2: Same as Scenario 2

STEP 3: Query Execution
├─ Password prompted: getpass("Enter password for Keycloak user 'kumar': ")
├─ User authenticates via Keycloak password grant
├─ User token obtained: eyJhbGc...kumar-token...
├─ Domain "production" selected
├─ Domain access verified: kumar NOT in ["admin", "prod-lead"]
├─ ERROR: "User 'kumar' is not assigned to this domain"
├─ Query NOT executed
├─ User must be added to domain by admin first
└─ Session logged: {user: "kumar", authenticated: false, error: "Not authorized for domain"}
```

### Scenario 4: Token Expiry During Query

```
STEP 1: User authenticated
├─ Token obtained with expiry: 1 hour
└─ Query executing...

STEP 2: Query After Token Expiry
├─ Query API called: Authorization: Bearer eyJ...expired...
├─ Response: 401 Unauthorized
├─ System action:
│  ├─ Logs: "User token expired"
│  ├─ Clears: Cached token for user
│  ├─ Prompts: "Password for re-authentication"
│  └─ Retries: Query with new token
├─ New token obtained: eyJhbGc...fresh-token...
├─ Query retried: Success 200 OK
└─ Session logged: {user: "kumar", authenticated: true, token_refreshed: true}
```

## API Response Codes and Handling

### 200 OK - Query Successful

```json
{
  "success": true,
  "data": [
    {
      "id": "pod-1",
      "