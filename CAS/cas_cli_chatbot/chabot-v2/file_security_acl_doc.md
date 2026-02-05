# CAS Chatbot - File-Level Security ACL Configuration Guide

## Document Information

**Status:** Technical Documentation  
**Audience:** System Administrators, Security Team, Research Team  

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [IDP Configuration for File-Level Security](#idp-configuration)
4. [CAS Configuration](#cas-configuration)
5. [Chatbot Integration](#chatbot-integration)
6. [Use Cases & Scenarios](#use-cases)
7. [Path-Level ACL Management](#path-level-acl)

---

## Overview

### What is File-Level Security in CAS?

IBM Cloud Application Services (CAS) provides **file-level access control** that integrates with Identity Providers (IDP) like Keycloak to enforce granular security policies. When users query data through the CAS Chatbot, file-level ACLs ensure they only access files they're authorized to view.

### Key Concepts

```
User Authentication (IDP/Keycloak)
    ↓
User Authorization (CAS ACL)
    ↓
File Access Control (POSIX ACL)
    ↓
Query Results (Filtered by ACL)
```

**Components:**
- **IDP (Keycloak)**: Authenticates users and provides identity tokens
- **CAS**: Validates tokens and enforces file-level ACLs 
- **Scale Filesystem**: Stores files with POSIX ACLs using OpenLDAP
- **Chatbot CLI**: User interface that respects all ACL controls

### Reference Documentation

IBM CAS File-Level Security:  
https://www.ibm.com/docs/en/fusion-software/2.11.0?topic=security-configuring-file-level-access-control-in-cas

---

## Architecture

### High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Layer                              │
│                                                                 │
│  User (kumar) → Chatbot CLI → Query Request                     │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          OpenLDAP Directory                             │
│                                                                         │
│                                                                         │
│  Users:                          Groups:                                │
│  ├── uid=kumar,ou=users          ├── cn=data-analysts,ou=groups         │
│  │   uidNumber: 1001             │   gidNumber: 2001                    │
│  │   gidNumber: 2001             │   memberUid: kumar, priya            │
│  │   homeDirectory: /home/kumar  │                                      │
│  │   loginShell: /bin/bash       ├── cn=data-engineers,ou=groups        │
│  │                               │   gidNumber: 2002                    │
│  ├── uid=priya,ou=users          │   memberUid: developer1              │
│  │   uidNumber: 1002             │                                      │
│  │   gidNumber: 2001             └── cn=project-a-team,ou=groups        │
│  │                                    gidNumber: 2003                   │
│  └── uid=developer1,ou=users          memberUid: kumar, developer1      │
│      uidNumber: 1003                                                    │
│      gidNumber: 2002                                                    │
└──────────────────┬───────────────────────────────────────────────────────┘
                   │
                   │ LDAP Sync/Federation
                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          Keycloak IDP                                   │
│                      (Authentication Broker)                            │
│                                                                         │
│  User Federation:                                                       │
│  ├── LDAP Connection                                                    │
│  │   Vendor: OpenLDAP                                                   │
│  │   Connection URL: ldap://openldap:389                                │
│  │   Users DN: ou=users,dc=example,dc=com                               │
│  │   Groups DN: ou=groups,dc=example,dc=com                             │
│  │                                                                      │
│  │   Sync Settings:                                                     │
│  │   ├── Import Users: Yes                                              │
│  │   ├── Sync Registrations: Yes                                        │
│  │   ├── UID Attribute: uidNumber                                       │
│  │   ├── GID Attribute: gidNumber                                       │
│  │   └── Group Membership Attr: memberUid                               │
│  │                                                                       │
│  └── Token Claims (from LDAP):                                          │
│      ├── uid: 1001 (from uidNumber)                                     │
│      ├── gid: 2001 (from gidNumber)                                     │
│      ├── groups: [data-analysts, project-a-team]                        │
│      └── username: kumar (from uid)                                     │
└──────────────────┬───────────────────────────────────────────────────────┘
                   │
┌─────────────────────────────────────────────────────────────────┐
│                    Identity Provider (IDP)                       │
│                        Keycloak                                  │
│                                                                  │
│  1. Authenticate User (username/password)                        │
│  2. Validate Credentials                                         │
│  3. Generate Token with:                                         │
│     - User ID (sub)                                              │
│     - Groups (groups claim)                                      │
│     - Roles (roles claim)                                        │
│     - Custom Attributes (ACL mappings)                           │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                      CAS API Layer                               │
│                                                                  │
│  1. Receive Query Request with Bearer Token                      │
│  2. Validate  Token with IDP                                     │
│  3. Extract User Claims:                                         │
│     - uid: kumar                                                 │
│     - gid: data-analysts                                         │
│     - groups: [team-a, team-b]                                   │
│  4. Map to POSIX Identity:                                       │
│     - UID: 1001                                                  │
│     - GID: 2001                                                  │
│     - Groups: [2001, 2002]                                       │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Scale Filesystem                              │
│                                                                  │
│  Files with POSIX ACLs:                                          │
│  /data/project-a/file1.csv                                       │
│    Owner: user:1001 (kumar)                                      │
│    Group: group:2001 (data-analysts)                             │
│    ACL:                                                          │
│      user:1001:rw-  (kumar can read/write)                       │
│      group:2001:r--  (data-analysts can read)                    │
│      user:1002:---  (other-user cannot access)                   │
│      other::---  (no other access)                               │
│                                                                  │
│  /data/project-b/file2.csv                                       │
│    Owner: user:1002 (other-user)                                 │
│    Group: group:2002 (team-b)                                    │
│    ACL:                                                          │
│      user:1002:rw-                                               │
│      group:2002:r--                                              │
│      user:1001:---  (kumar CANNOT access)                        │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Query Processing                              │
│                                                                  │
│  1. CAS queries Scale with User Context (UID: 1001)              │
│  2. Scale enforces ACLs:                                         │
│     - File1: ✓ Accessible (kumar has permission)                 │
│     - File2: ✗ Denied (kumar lacks permission)                   │
│  3. CAS returns filtered results:                                │
│     - Only files user can access                                 │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Response to User                              │
│                                                                  │
│  Query Results (Filtered by ACL):                                │
│  - /data/project-a/file1.csv ✓                                   │
│  - /data/project-a/file3.csv ✓                                   │
│  (file2.csv not included - no permission)                        │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **User authenticates** via Keycloak (IDP)
2. **Token issued** with user identity and group memberships
3. **Query sent** to CAS API with Bearer token
4. **CAS validates token** and extracts user context
5. **CAS maps** IDP identity to POSIX UID/GID
6. **Scale enforces ACLs** during file access
7. **Filtered results** returned (only accessible files)
8. **Chatbot displays** authorized data only

---

## IDP Configuration

### Step 1: Configure Keycloak Realm

#### 1.1 Create or Configure Realm

```bash
# Access Keycloak Admin Console
http://keycloak-server:8080/admin

# Create realm: cas-users
Realm: cas-users
Display Name: CAS Users
Enabled: ON
```

#### 1.2 Create Groups for File Access

Create groups that map to Scale filesystem groups:

```
Groups:
├── data-analysts (GID: 2001)
│   ├── Description: Analysts with read access to project data
│   └── Members: kumar, priya
│
├── data-engineers (GID: 2002)
│   ├── Description: Engineers with write access
│   └── Members: developer1, developer2
│
├── project-a-team (GID: 2003)
│   ├── Description: Project A team members
│   └── Members: kumar, developer1
│
└── project-b-team (GID: 2004)
    ├── Description: Project B team members
    └── Members: priya, developer2
```

**Configuration:**
```
Keycloak Admin Console → Groups → Create Group

Name: data-analysts
Attributes:
  - gid: 2001
  - description: Data Analysts Group
```

#### 1.3 Create Users

```
Keycloak Admin Console → Users → Add User

Username: kumar
Email: kumar@example.com
First Name: Kumar
Last Name: Singh
Enabled: ON
Email Verified: ON

Groups:
  - data-analysts
  - project-a-team

Attributes:
  - uid: 1001
  - posix_uid: 1001
  - posix_gid: 2001
  - home_directory: /home/kumar
```

### Step 2: Configure Client for CAS

#### 2.1 Create OAuth Client

```
Keycloak Admin Console → Clients → Create

Client ID: cas-client
Client Protocol: openid-connect
Access Type: confidential
Standard Flow Enabled: ON
Direct Access Grants Enabled: ON
Service Accounts Enabled: ON

Valid Redirect URIs:
  - https://cas-api.example.com/*
  - http://localhost:*

Web Origins:
  - https://cas-api.example.com
```

#### 2.2 Configure Client Mappers

**Add Group Membership Mapper:**

```
Client → cas-client → Mappers → Create

Name: groups-mapper
Mapper Type: Group Membership
Token Claim Name: groups
Full group path: OFF
Add to ID token: ON
Add to access token: ON
Add to userinfo: ON
```

**Add UID Mapper:**

```
Name: uid-mapper
Mapper Type: User Attribute
User Attribute: uid
Token Claim Name: uid
Claim JSON Type: String
Add to ID token: ON
Add to access token: ON
Add to userinfo: ON
```

**Add GID Mapper:**

```
Name: gid-mapper
Mapper Type: User Attribute
User Attribute: posix_gid
Token Claim Name: gid
Claim JSON Type: String
Add to ID token: ON
Add to access token: ON
Add to userinfo: ON
```

**Add Groups List Mapper:**

```
Name: group-gids-mapper
Mapper Type: User Attribute
User Attribute: group_gids
Token Claim Name: group_gids
Claim JSON Type: JSON
Add to ID token: ON
Add to access token: ON
```

### Step 3: Configure Group-to-GID Mapping

For each group, add GID attribute:

```
Groups → data-analysts → Attributes

Key: gid
Value: 2001

Key: filesystem_path
Value: /data/analysts

Key: access_level
Value: read
```

### Step 4: Test Token Generation

```bash
# Get token for kumar
curl -X POST "http://keycloak:8080/realms/cas-users/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=cas-client" \
  -d "client_secret=<client-secret>" \
  -d "username=kumar" \
  -d "password=<password>"

# Decode  token to verify claims:
echo "<token>" | cut -d'.' -f2 | base64 -d | jq
```

**Expected Token Claims:**
```json
{
  "sub": "a1b2c3d4-5678-90ab-cdef-1234567890ab",
  "preferred_username": "kumar",
  "email": "kumar@example.com",
  "uid": "1001",
  "gid": "2001",
  "groups": [
    "data-analysts",
    "project-a-team"
  ],
  "group_gids": [
    "2001",
    "2003"
  ]
}
```

---

## CAS Configuration

### Step 1: Enable File-Level Security in CAS

#### 1.1 Configure CAS Identity Provider

```yaml
# /etc/cas/config/cas-config.yaml

security:
  authentication:
    enabled: true
    provider: oidc
    oidc:
      issuer_url: "http://keycloak:8080/realms/cas-users"
      client_id: "cas-client"
      client_secret: "${KEYCLOAK_CLIENT_SECRET}"
      scopes:
        - openid
        - profile
        - email
        - groups
      
      # JWT validation
      jwt_validation:
        enabled: true
        validate_issuer: true
        validate_audience: true
        validate_expiry: true
      
      # User identity mapping
      identity_mapping:
        uid_claim: "uid"
        gid_claim: "gid"
        groups_claim: "groups"
        group_gids_claim: "group_gids"
        username_claim: "preferred_username"
        email_claim: "email"
  
  authorization:
    enabled: true
    mode: "file-level"  # Enable file-level ACL
    
    # POSIX identity mapping
    posix_mapping:
      enabled: true
      uid_base: 1000
      gid_base: 2000
      
      # Map IDP users to POSIX UIDs
      user_mapping:
        - idp_uid: "1001"
          posix_uid: 1001
          username: "kumar"
        
        - idp_uid: "1002"
          posix_uid: 1002
          username: "priya"
      
      # Map IDP groups to POSIX GIDs
      group_mapping:
        - idp_group: "data-analysts"
          posix_gid: 2001
        
        - idp_group: "data-engineers"
          posix_gid: 2002
        
        - idp_group: "project-a-team"
          posix_gid: 2003
        
        - idp_group: "project-b-team"
          posix_gid: 2004
    
    # File access control
    file_acl:
      enabled: true
      enforce_acl: true
      default_permissions: "0750"
      inherit_permissions: true
      
      # ACL enforcement mode
      acl_mode: "strict"  # strict | permissive | audit
      
      # Audit logging
      audit_file_access: true
      audit_log_path: "/var/log/cas/file-access-audit.log"
```

#### 1.2 Configure Scale Integration

```yaml
# /etc/cas/config/cas-config.yaml

storage:
  backend: "scale"
  
  scale:
    filesystem_path: "/gpfs/cas-data"
    mount_point: "/mnt/cas"
    
    # Enable POSIX ACL support
    acl:
      enabled: true
      enforce: true
      default_acl: |
        user::rwx
        group::r-x
        other::---
      
    # AFM (Active File Management) Configuration
    afm:
      enabled: true
      mode: "single-writer"
      
      # S3 backend configuration
      primary_fileset: "/gpfs/cas-data"
      cache_fileset: "/gpfs/cas-data/cache"
      
      # File caching policy
      cache_policy:
        on_demand: true
        prefetch: false
        cache_size_limit: "1TB"
        eviction_policy: "lru"  # Least Recently Used
        
      # File lifecycle
      lifecycle:
        cache_timeout: "7d"  # Files cached for 7 days
        evict_on_close: false
        retain_metadata: true
```

### Step 2: Configure API Endpoints

```yaml
# /etc/cas/config/api-config.yaml

api:
  endpoints:
    query:
      path: "/api/v1/query"
      methods: ["GET", "POST"]
      
      # Authentication required
      authentication:
        required: true
        schemes:
          - bearer
      
      # Authorization
      authorization:
        enabled: true
        check_file_acl: true  # Enforce file-level ACL
      
      # Query parameters
      parameters:
        - name: table
          required: true
          type: string
        
        - name: limit
          required: false
          type: integer
          default: 100
      
      # Response filtering
      response:
        filter_by_acl: true  # Filter results by user ACL
        include_metadata: false
        sanitize_paths: true
```

### Step 3: Apply Configuration

```bash
# Restart CAS services
systemctl restart cas-api
systemctl restart cas-gateway

# Verify configuration
cas-admin config validate
cas-admin config show security.authorization

# Test file access
cas-admin test-access --user kumar --file /gpfs/cas-data/project-a/file1.csv
```

---

## Chatbot Integration

### No Code Changes Required

The CAS Chatbot already supports file-level security through the existing architecture. When properly configured:

1. **User authenticates** with Keycloak via chatbot
2. **Bearer token obtained** contains user identity and groups
3. **Token sent with every query** to CAS API
4. **CAS enforces ACLs** automatically
5. **Filtered results returned** to chatbot
6. **User sees only authorized files**

### Configuration in Chatbot

Update `config.yaml`:

```yaml
# Keycloak configuration (already present)
keycloak:
  enabled: true
  url: "http://keycloak:8080/realms/cas-users/protocol/openid-connect/token"
  client_id: "cas-client"
  client_secret: "${KEYCLOAK_CLIENT_SECRET}"

# CAS API (already present)
cas_url: "https://cas-api.example.com/"

# Users (already present)
users:
  - name: "kumar"
    type: "keycloak"
    provider: "keycloak"
    description: "Data Analyst with limited file access"
```

### Verification

```bash
# Start chatbot
python main.py

# Test as kumar
cas> users select
Select user: kumar

kumar> auth with provider
Enter password: ****
✓ Authentication successful

kumar> domains select
Select domain: project-a

kumar@project-a> query ask
Enter query: List all CSV files

# Result: Only files kumar has permission to access
Files accessible to kumar:
  - /data/project-a/file1.csv ✓
  - /data/project-a/file3.csv ✓
  
# file2.csv not shown (no ACL permission)
```

---

## Use Cases

### Use Case 1: User with Read-Only Access

**Scenario:** Kumar (data analyst) queries project files

**Setup:**
```bash
# File ACL on Scale:
/gpfs/cas-data/project-a/sales-data.csv
  Owner: root
  Group: data-analysts (GID: 2001)
  ACL:
    user::rw-
    group:2001:r--  # data-analysts can read
    other::---
```

**Chatbot Flow:**
```bash
kumar@project-a> query ask
Enter query: Show sales data

# Behind the scenes:
# 1. Kumar's token: uid=1001, gid=2001, groups=[data-analysts]
# 2. CAS maps to POSIX: UID=1001, GID=2001
# 3. Scale checks ACL: group:2001:r-- → ALLOWED
# 4. File contents returned
```

**Result:** ✓ Kumar can read sales-data.csv

---

### Use Case 2: User Without Access

**Scenario:** Kumar tries to access engineering files

**Setup:**
```bash
/gpfs/cas-data/engineering/config.yaml
  Owner: root
  Group: data-engineers (GID: 2002)
  ACL:
    user::rw-
    group:2002:rw-  # data-engineers can read/write
    other::---      # No other access
```

**Chatbot Flow:**
```bash
kumar@engineering> query ask
Enter query: Show configuration files

# Behind the scenes:
# 1. Kumar's token: uid=1001, gid=2001, groups=[data-analysts]
# 2. CAS maps to POSIX: UID=1001, GID=2001
# 3. Scale checks ACL: user:1001 not in ACL, group:2001 not in ACL
# 4. Access DENIED
# 5. File not included in results
```

**Result:** ✗ config.yaml not shown in results

---

### Use Case 3: Multi-Group User Access

**Chatbot Flow:**
```bash
developer1@shared> query ask
Enter query: Get project plan

# Behind the scenes:
# 1. Token: uid=1003, gid=2002, groups=[data-engineers, project-a-team]
# 2. CAS checks: group:2002 → read, group:2003 → read/write
# 3. Access ALLOWED (via either group)
```
---

### Use Case 3: Owner-Only File

**Scenario:** User-specific private files

**Setup:**
```bash
/gpfs/cas-data/users/kumar/private-notes.txt
  Owner: kumar (UID: 1001)
  Group: data-analysts (GID: 2001)
  ACL:
    user:1001:rw-  # Only kumar
    group::---     # No group access
    other::---
```

**Chatbot Flow:**
```bash
# Kumar accessing own file
kumar@users> query ask
Enter query: Show my notes
Result: ✓ private-notes.txt accessible

# Priya trying to access kumar's file
priya@users> query ask
Enter query: Show kumar's notes
Result: ✗ private-notes.txt not in results (access denied)
```

---

### Use Case 4: Dynamic Group Membership

**Scenario:** User added to new group, gains immediate access

**Initial State:**
```bash
User: kumar
  Groups: data-analysts (2001)

File: /gpfs/cas-data/special-project/data.csv
  ACL: group:2005:r-- (special-team only)
```

**Access Test 1:**
```bash
kumar@special-project> query ask
Enter query: List files
Result: ✗ No files shown (no permission)
```

**Admin Action:**
```bash
# Keycloak Admin adds kumar to special-team group
Groups → special-team → Members → Add: kumar
```

**Access Test 2:**
```bash
# Kumar re-authenticates to get new token
kumar> auth with provider
✓ New token with groups: [data-analysts, special-team]

kumar@special-project> query ask
Enter query: List files
Result: ✓ data.csv now visible
```

----

---

## Path-Level ACL

### How Path-Level ACL Works

Path-level ACL controls access to entire directory trees.

#### Path Determination

**1. Hierarchical Inheritance:**
```
/gpfs/cas-data/
  ACL: user::rwx, group::r-x, other::---
  
  ├── project-a/
  │   ACL: user::rwx, group:2003:rwx, other::---
  │   (Inherits from parent, adds project-a-team)
  │   
  │   ├── data/
  │   │   ACL: user::rwx, group:2003:r--, other::---
  │   │   (Inherits from project-a, restricts to read)
  │   │   
  │   │   └── file1.csv
  │   │       ACL: (Inherits from data/)
  │   │       
  │   └── reports/
  │       ACL: user::rwx, group:2003:rw-, other::---
  │       
  └── project-b/
      ACL: user::rwx, group:2004:rwx, other::---
      (Different group, separate access)
```

**2. Effective Permissions:**
```
User: kumar (UID: 1001, Groups: [2003])
Path: /gpfs/cas-data/project-a/data/file1.csv

Permission Check:
1. Check /gpfs/cas-data/ → Allow (group::r-x)
2. Check /gpfs/cas-data/project-a/ → Allow (group:2003:rwx)
3. Check /gpfs/cas-data/project-a/data/ → Allow (group:2003:r--)
4. Check /gpfs/cas-data/project-a/data/file1.csv → Allow (inherited)

Result: ✓ ALLOWED (read permission)
```

#### Path Determination Methods

**Method 1: Filesystem Hierarchy**
```
Path determined by actual filesystem structure:
/gpfs/cas-data/project-a/data/file1.csv
└─ Physical path on Scale filesystem
└─ ACL set at each directory level
└─ Child inherits unless explicitly overridden
```