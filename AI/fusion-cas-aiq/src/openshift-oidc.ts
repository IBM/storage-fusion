// SPDX-FileCopyrightText: Copyright (c) 2025-2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

/**
 * OpenShift OIDC Provider
 *
 * Authenticates users against the OpenShift built-in OAuth server.
 * Uses next-auth's generic OAuth provider — no extra dependencies needed.
 *
 * Required env vars (set in fusion-config-override.yaml secretEnv / env):
 *   REQUIRE_AUTH=true
 *   OAUTH_ISSUER      — e.g. https://oauth-openshift.apps.<cluster>.example.com
 *   OAUTH_CLIENT_ID   — e.g. system:serviceaccount:ns-aiq:aiq-oauth-proxy
 *   NEXTAUTH_SECRET   — random string: openssl rand -base64 32
 *   NEXTAUTH_URL      — public UI URL: https://aiq-frontend-ns-aiq.apps.<cluster>.example.com
 *
 * No OAUTH_CLIENT_SECRET is required when using the ose-oauth-proxy
 * ServiceAccount flow — the SA token is the credential.
 */

import type { OAuthConfig } from 'next-auth/providers/oauth'
import type { TokenSetParameters } from 'openid-client'
import type { AuthProviderConfig, TokenRefreshResult } from './types'

const PROVIDER_ID = 'openshift'

const issuer = process.env.OAUTH_ISSUER ?? ''
const clientId = process.env.OAUTH_CLIENT_ID ?? ''
const clientSecret = process.env.OAUTH_CLIENT_SECRET ?? ''

/**
 * OpenShift does not publish a standard /.well-known/openid-configuration,
 * so we derive the three endpoints from the issuer URL directly.
 */
const authorization = `${issuer}/oauth/authorize`
const token = `${issuer}/oauth/token`
const userinfoUrl = `${issuer}/apis/user.openshift.io/v1/users/~`

interface OpenShiftProfile {
  sub: string
  name: string
  email?: string
  picture?: string
}

// In NextAuth v4, OAuth providers are plain objects matching OAuthConfig — not factory calls.
export const OpenShiftProvider: OAuthConfig<OpenShiftProfile> = {
  id: PROVIDER_ID,
  name: 'OpenShift',
  type: 'oauth',
  clientId,
  clientSecret,
  authorization: { url: authorization, params: { scope: 'user:info' } },
  token,
  userinfo: {
    url: userinfoUrl,
    // OpenShift returns { metadata: { name }, fullName, ... } — map to NextAuth profile shape
    async request({ tokens }: { tokens: TokenSetParameters }) {
      const res = await fetch(userinfoUrl, {
        headers: { Authorization: `Bearer ${tokens.access_token as string}` },
      })
      const data = (await res.json()) as {
        metadata?: { name?: string }
        fullName?: string
      }
      return {
        sub: data.metadata?.name ?? 'openshift-user',
        name: data.fullName ?? data.metadata?.name ?? 'OpenShift User',
      }
    },
  },
  profile(profile) {
    return {
      id: profile.sub ?? 'openshift-user',
      name: profile.name ?? 'OpenShift User',
      email: null,
      image: null,
    }
  },
}

/**
 * Refresh the access token using the OpenShift token endpoint.
 * OpenShift may not issue a refresh_token depending on cluster config —
 * if absent the session expires and the user must re-login.
 */
export const refreshOpenShiftToken = async (refreshToken: string): Promise<TokenRefreshResult> => {
  const params = new URLSearchParams({
    grant_type: 'refresh_token',
    refresh_token: refreshToken,
    client_id: clientId,
  })
  if (clientSecret) params.set('client_secret', clientSecret)

  const res = await fetch(token, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: params.toString(),
  })

  if (!res.ok) {
    throw new Error(`OpenShift token refresh failed: ${res.status} ${res.statusText}`)
  }

  const data = (await res.json()) as {
    access_token: string
    id_token?: string
    expires_in: number
    refresh_token?: string
  }

  return {
    access_token: data.access_token,
    id_token: data.id_token ?? data.access_token,
    expires_in: data.expires_in ?? 86400,
    refresh_token: data.refresh_token,
  }
}

export const getOpenShiftProviderConfig = (): AuthProviderConfig => ({
  provider: OpenShiftProvider as unknown as Record<string, unknown>,
  providerId: PROVIDER_ID,
  refreshToken: refreshOpenShiftToken,
  requiredEnvVars: ['OAUTH_CLIENT_ID', 'OAUTH_ISSUER'],
})
