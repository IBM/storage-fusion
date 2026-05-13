# Authentication Flow Changes

## Overview
This document describes the new user authentication flow implemented for the CAS CLI Chatbot. The changes ensure that users are prompted for OpenShift credentials at startup, and the bearer token is fetched once during login.

## Changes Made

### 1. New Config Manager Module (`utils/config_manager.py`)
- **Purpose**: Handles interactive configuration setup and credential management
- **Key Features**:
  - Checks if `config.yaml` exists
  - Validates if OC credentials are configured
  - Prompts users for credentials interactively
  - Creates config from sample if needed
  - Allows users to choose between existing config or new credentials

### 2. Updated Main Entry Point (`main.py`)
- **Changes**:
  - Added `ConfigManager` import
  - Calls `config_manager.setup_interactive()` at startup
  - Enhanced authentication verification to check for bearer token
  - Provides clear error messages if token retrieval fails
  - Prevents application from starting if authentication fails

### 3. Enhanced Auth Service (`services/auth_service.py`)
- **Changes**:
  - Added `token_fetch_attempted` flag to track authentication attempts
  - Enhanced `authenticate()` method to fetch bearer token immediately after login
  - Added `has_valid_token()` method for token validation
  - Improved error logging for token retrieval failures
  - Updated `get_token_info()` to include token validity status

### 4. Updated Query Service (`services/query_service.py`)
- **Changes**:
  - Added `_check_bearer_token()` method to validate token before operations
  - Updated all query methods to check token validity:
    - `query_vector_store()`
    - `query_with_filters()`
    - `list_vector_stores()`
    - `get_vector_store_info()`
    - `get_file_content()`
  - Returns clear error messages when token is invalid

### 5. Updated CLI (`cli/chatbot_cli.py`)
- **Changes**:
  - Enhanced `_retrieved_result_valid()` to detect token-related errors
  - Provides user-friendly messages when token is invalid
  - Instructs users to restart and re-authenticate

## New User Flow

### First Time Setup
1. User starts the application: `python main.py`
2. System detects no `config.yaml` exists
3. System prompts for:
   - Console URL (e.g., `https://console-openshift-console.apps.example.com`)
   - OC Username (e.g., `kubeadmin`)
   - OC Password (secure input, not echoed)
4. System creates `config.yaml` with credentials
5. System authenticates with OpenShift
6. System fetches bearer token
7. If successful, application starts
8. If failed, application exits with error message

### Subsequent Runs (Config Exists)
1. User starts the application: `python main.py`
2. System detects `config.yaml` exists
3. System checks if credentials are configured
4. If configured:
   - Displays current configuration
   - Asks: "Use existing configuration? [Y/n]"
   - If Yes: Uses existing credentials
   - If No: Prompts for new credentials
5. System authenticates with OpenShift
6. System fetches bearer token
7. If successful, application starts
8. If failed, application exits with error message

### During Operation
1. All service functions check for valid bearer token before executing
2. If token is invalid:
   - Operation fails with clear error message
   - User is informed they cannot use commands
   - User is instructed to restart and re-authenticate
3. If token is valid:
   - Operation proceeds normally

## Token Management

### Token Lifecycle
- **Fetch**: Token is fetched once during initial authentication
- **Cache**: Token is cached in memory and optionally in cache service
- **Validation**: Token validity is checked before each operation
- **Expiry**: Default token expiry is 24 hours (OCP standard)
- **Refresh**: Token refresh threshold is 5 minutes (configurable)

### Token Validation
The system validates tokens at multiple levels:
1. **Startup**: Verifies token was successfully obtained
2. **Service Layer**: Each service method checks token validity
3. **CLI Layer**: Handles token errors gracefully with user feedback

## Configuration File Structure

### config.yaml
```yaml
# OpenShift Console / Admin Configuration
console_url: "https://console-openshift-console.apps.example.com"
oc_username: "kubeadmin"
oc_password: "your-password"

# Token refresh threshold in seconds (default: 5 minutes)
token_refresh_threshold: 300

# ... other configuration options ...
```

## Error Handling

### Authentication Failures
- **Invalid Credentials**: Clear error message, application exits
- **Token Retrieval Failed**: Specific error message, application exits
- **Network Issues**: Timeout error, application exits

### Runtime Token Issues
- **Token Expired**: Service returns error, CLI displays message
- **Token Invalid**: Service returns error, CLI displays message
- **No Token**: Service returns error, CLI displays message

## Testing the New Flow

### Test Case 1: First Time Setup
```bash
# Remove existing config
rm chatbot/config.yaml

# Start application
cd chatbot
python main.py

# Expected: Prompts for credentials, creates config, authenticates
```

### Test Case 2: Existing Config - Use Existing
```bash
# Ensure config.yaml exists with valid credentials
cd chatbot
python main.py

# Expected: Shows config, asks to use existing, authenticates
# Choose: Y (use existing)
```

### Test Case 3: Existing Config - Use Different
```bash
cd chatbot
python main.py

# Expected: Shows config, asks to use existing
# Choose: n (use different)
# Expected: Prompts for new credentials
```

### Test Case 4: Invalid Credentials
```bash
# Edit config.yaml with invalid password
cd chatbot
python main.py

# Expected: Authentication fails, clear error message, exits
```

### Test Case 5: Token Validation During Operation
```bash
# Start application successfully
cd chatbot
python main.py

# Try to execute a command (e.g., list vector stores)
# Expected: Command executes successfully if token is valid
```

## Benefits

1. **Security**: Credentials are prompted securely (password not echoed)
2. **User Experience**: Clear prompts and error messages
3. **Flexibility**: Users can choose to use existing or new credentials
4. **Reliability**: Token is validated before each operation
5. **Maintainability**: Centralized token management
6. **Error Recovery**: Clear instructions when authentication fails

## Migration Notes

### For Existing Users
- Existing `config.yaml` files will work without changes
- On first run, users will be asked if they want to use existing config
- No data loss or configuration changes unless user chooses to update

### For New Users
- Guided setup process on first run
- Sample config file (`config.yaml.sample`) serves as template
- Clear prompts for all required information

## Troubleshooting

### Issue: "No valid bearer token available"
**Solution**: Restart the application and re-authenticate

### Issue: "Authentication failed"
**Solution**: Check credentials in config.yaml, ensure OC CLI is installed

### Issue: "Failed to retrieve bearer token"
**Solution**: Verify network connectivity, check OpenShift cluster status

### Issue: "Configuration validation failed"
**Solution**: Check config.yaml format, ensure all required fields are present

## Future Enhancements

Potential improvements for future versions:
1. Token refresh mechanism during runtime
2. Multiple credential profiles
3. Encrypted credential storage
4. SSO integration
5. Token expiry notifications
6. Automatic re-authentication on token expiry

## Related Files

- `chatbot/utils/config_manager.py` - Configuration management
- `chatbot/main.py` - Application entry point
- `chatbot/services/auth_service.py` - Authentication service
- `chatbot/services/query_service.py` - Query service with token validation
- `chatbot/cli/chatbot_cli.py` - CLI interface
- `chatbot/config.yaml.sample` - Sample configuration template