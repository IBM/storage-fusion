# OIDC Provider Configuration Guide

This guide explains how to configure various OIDC (OpenID Connect) providers with IBM Fusion Developer Hub.

## Table of Contents

- [Generic OIDC Configuration](#generic-oidc-configuration)
- [Provider-Specific Examples](#provider-specific-examples)
  - [IBM ID](#ibm-id)
  - [Okta](#okta)
  - [Auth0](#auth0)
  - [Keycloak](#keycloak)
  - [Azure AD](#azure-ad)
  - [Google Workspace](#google-workspace)
- [Advanced Configuration](#advanced-configuration)

## Generic OIDC Configuration

The chart supports any OIDC-compliant identity provider through the generic `oidc` configuration:

```yaml
auth:
  providers:
    oidc:
      enabled: true
      providerName: "Your Provider Name"  # Display name in UI
      clientId: "your-client-id"
      clientSecret: "your-client-secret"
      issuer: "https://your-provider.com"
      # Optional configurations
      discoveryUrl: ""  # Override if not standard
      additionalScopes: []  # Extra scopes beyond openid, profile, email
      prompt: "auto"  # auto, login, consent, select_account, none
      signIn:
        resolver: "emailMatchingUserEntityProfileEmail"
```

## Provider-Specific Examples

### IBM ID

IBM's enterprise identity provider for IBM employees and partners.

```yaml
auth:
  providers:
    oidc:
      enabled: true
      providerName: "IBM ID"
      clientId: "your-ibm-client-id"
      clientSecret: "your-ibm-client-secret"
      issuer: "https://login.ibm.com/oidc/endpoint/default"
      signIn:
        resolver: "emailMatchingUserEntityProfileEmail"
```

**Setup Steps:**
1. Register application at IBM Cloud Console
2. Set redirect URI: `https://your-developer-hub.com/api/auth/oidc/handler/frame`
3. Obtain Client ID and Client Secret
4. Configure the values above

**Alternative:** Use the pre-configured `ibmid` provider:
```yaml
auth:
  providers:
    ibmid:
      enabled: true
      clientId: "your-ibm-client-id"
      clientSecret: "your-ibm-client-secret"
```

### Okta

Enterprise identity and access management platform.

```yaml
auth:
  providers:
    oidc:
      enabled: true
      providerName: "Okta"
      clientId: "your-okta-client-id"
      clientSecret: "your-okta-client-secret"
      issuer: "https://your-domain.okta.com"
      additionalScopes: ["groups"]
      signIn:
        resolver: "emailMatchingUserEntityProfileEmail"
```

**Setup Steps:**
1. Go to Okta Admin Console → Applications → Create App Integration
2. Choose "OIDC - OpenID Connect" and "Web Application"
3. Set Sign-in redirect URI: `https://your-developer-hub.com/api/auth/oidc/handler/frame`
4. Set Sign-out redirect URI: `https://your-developer-hub.com`
5. Copy Client ID and Client Secret

### Auth0

Flexible authentication and authorization platform.

```yaml
auth:
  providers:
    oidc:
      enabled: true
      providerName: "Auth0"
      clientId: "your-auth0-client-id"
      clientSecret: "your-auth0-client-secret"
      issuer: "https://your-tenant.auth0.com"
      signIn:
        resolver: "emailMatchingUserEntityProfileEmail"
```

**Setup Steps:**
1. Go to Auth0 Dashboard → Applications → Create Application
2. Choose "Regular Web Applications"
3. Set Allowed Callback URLs: `https://your-developer-hub.com/api/auth/oidc/handler/frame`
4. Set Allowed Logout URLs: `https://your-developer-hub.com`
5. Copy Domain, Client ID, and Client Secret

### Keycloak

Open-source identity and access management solution.

```yaml
auth:
  providers:
    oidc:
      enabled: true
      providerName: "Keycloak"
      clientId: "backstage"
      clientSecret: "your-keycloak-client-secret"
      issuer: "https://keycloak.example.com/realms/your-realm"
      additionalScopes: ["roles"]
      signIn:
        resolver: "emailMatchingUserEntityProfileEmail"
```

**Setup Steps:**
1. Go to Keycloak Admin Console → Clients → Create
2. Set Client ID: `backstage`
3. Set Access Type: `confidential`
4. Set Valid Redirect URIs: `https://your-developer-hub.com/api/auth/oidc/handler/frame`
5. Save and go to Credentials tab to get the secret

### Azure AD

Microsoft's cloud-based identity and access management service.

```yaml
auth:
  providers:
    oidc:
      enabled: true
      providerName: "Microsoft"
      clientId: "your-azure-client-id"
      clientSecret: "your-azure-client-secret"
      issuer: "https://login.microsoftonline.com/your-tenant-id/v2.0"
      additionalScopes: ["User.Read"]
      signIn:
        resolver: "emailMatchingUserEntityProfileEmail"
```

**Setup Steps:**
1. Go to Azure Portal → Azure Active Directory → App registrations → New registration
2. Set Redirect URI: `https://your-developer-hub.com/api/auth/oidc/handler/frame`
3. Go to Certificates & secrets → New client secret
4. Copy Application (client) ID, Directory (tenant) ID, and client secret value

### Google Workspace

Google's enterprise identity provider.

```yaml
auth:
  providers:
    oidc:
      enabled: true
      providerName: "Google"
      clientId: "your-google-client-id.apps.googleusercontent.com"
      clientSecret: "your-google-client-secret"
      issuer: "https://accounts.google.com"
      signIn:
        resolver: "emailMatchingUserEntityProfileEmail"
```

**Setup Steps:**
1. Go to Google Cloud Console → APIs & Services → Credentials
2. Create OAuth 2.0 Client ID (Web application)
3. Add Authorized redirect URI: `https://your-developer-hub.com/api/auth/oidc/handler/frame`
4. Copy Client ID and Client Secret

**Alternative:** Use the pre-configured `google` provider:
```yaml
auth:
  providers:
    google:
      enabled: true
      clientId: "your-google-client-id"
      clientSecret: "your-google-client-secret"
```

## Advanced Configuration

### Custom Discovery URL

If your provider doesn't follow the standard `/.well-known/openid-configuration` path:

```yaml
auth:
  providers:
    oidc:
      enabled: true
      providerName: "Custom Provider"
      clientId: "client-id"
      clientSecret: "client-secret"
      issuer: "https://provider.com"
      discoveryUrl: "https://provider.com/custom/discovery/path"
```

### Additional Scopes

Request additional scopes beyond the default `openid profile email`:

```yaml
auth:
  providers:
    oidc:
      enabled: true
      providerName: "Provider"
      clientId: "client-id"
      clientSecret: "client-secret"
      issuer: "https://provider.com"
      additionalScopes:
        - "groups"
        - "roles"
        - "custom_claim"
```

### Sign-In Resolvers

Choose how to match OIDC users to Backstage entities:

#### Email Matching (Default)
```yaml
signIn:
  resolver: "emailMatchingUserEntityProfileEmail"
```
Matches the email from OIDC token to the user entity's `spec.profile.email`.

#### Email Local Part Matching
```yaml
signIn:
  resolver: "emailLocalPartMatchingUserEntityName"
```
Uses the local part of the email (before @) as the entity name.

#### Preferred Username Matching
```yaml
signIn:
  resolver: "preferredUsernameMatchingUserEntityName"
```
Uses the `preferred_username` claim from the OIDC token.

### Prompt Behavior

Control the authentication prompt behavior:

```yaml
auth:
  providers:
    oidc:
      enabled: true
      prompt: "select_account"  # Options: auto, login, consent, select_account, none
```

- `auto`: Default behavior (recommended)
- `login`: Always prompt for credentials
- `consent`: Always prompt for consent
- `select_account`: Always show account selection
- `none`: No prompts (SSO only)

## Testing Configuration

### 1. Verify Discovery Endpoint

Test that your OIDC provider's discovery endpoint is accessible:

```bash
curl https://your-provider.com/.well-known/openid-configuration
```

### 2. Check Redirect URI

Ensure your redirect URI is correctly configured:
```
https://your-developer-hub.com/api/auth/oidc/handler/frame
```

### 3. Test Authentication Flow

1. Deploy the chart with your configuration
2. Navigate to Developer Hub
3. Click "Sign In"
4. Select your OIDC provider
5. Complete authentication
6. Verify you're logged in

### 4. Debug Issues

Check logs for authentication errors:

```bash
kubectl logs -f deployment/rhdh-fusion -n fusion-developer-hub | grep -i auth
```

## Security Best Practices

1. **Use HTTPS**: Always use HTTPS for production deployments
2. **Secure Secrets**: Store credentials in Kubernetes secrets, not in values files
3. **Rotate Credentials**: Regularly rotate client secrets
4. **Limit Scopes**: Only request necessary scopes
5. **Validate Tokens**: Ensure token validation is enabled
6. **Monitor Access**: Enable audit logging for authentication events

## Troubleshooting

### Common Issues

**Issue: "Invalid redirect URI"**
- Verify the redirect URI in your OIDC provider matches exactly
- Check for trailing slashes or protocol mismatches

**Issue: "Invalid client credentials"**
- Verify Client ID and Client Secret are correct
- Check if credentials have expired or been revoked

**Issue: "Discovery endpoint not found"**
- Verify the issuer URL is correct
- Check if a custom discoveryUrl is needed

**Issue: "User not found after login"**
- Check the sign-in resolver configuration
- Verify user entities exist in the catalog
- Ensure email/username claims match entity data

## Support

For additional help:
- Check the [Backstage Authentication Documentation](https://backstage.io/docs/auth/)
- Review provider-specific documentation
- Open an issue on GitHub

---

**Made with ❤️ by the IBM Fusion Team**