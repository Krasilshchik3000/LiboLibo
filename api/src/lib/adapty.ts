// Thin client for the Adapty Server API.
//
// Used only by `POST /v1/me/entitlement/refresh` to resolve a profile's premium
// status. Other endpoints read the cached state from the `entitlements` table
// via the `viewer` middleware.
//
// Auth: `Authorization: Api-Key <ADAPTY_SECRET_KEY>` (server-side secret).
// Endpoint path may need to be adjusted once we have keys and verify against
// the current Adapty docs — see step-2.3-premium-adapty.md "open questions".

const DEFAULT_BASE_URL = "https://api.adapty.io/api/v1";
const DEFAULT_PREMIUM_LEVEL = "premium";
const REQUEST_TIMEOUT_MS = 5_000;

export interface AdaptyProfileResponse {
  // We only model the fields we read. Adapty returns more.
  data?: {
    attributes?: {
      // `access_levels` is keyed by access level name (e.g. "premium").
      access_levels?: Record<string, AdaptyAccessLevel>;
    };
  };
}

export interface AdaptyAccessLevel {
  is_active?: boolean;
  expires_at?: string | null;
}

export interface ResolvedEntitlement {
  isPremium: boolean;
  expiresAt: Date | null;
}

export class AdaptyConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AdaptyConfigError";
  }
}

export class AdaptyApiError extends Error {
  status: number;
  body: string;
  constructor(status: number, body: string) {
    super(`Adapty API error: HTTP ${status}`);
    this.name = "AdaptyApiError";
    this.status = status;
    this.body = body;
  }
}

interface AdaptyConfig {
  secretKey: string;
  baseUrl: string;
  premiumAccessLevel: string;
}

function loadConfig(): AdaptyConfig {
  const secretKey = process.env.ADAPTY_SECRET_KEY;
  if (!secretKey) {
    throw new AdaptyConfigError("ADAPTY_SECRET_KEY is not set");
  }
  return {
    secretKey,
    baseUrl: process.env.ADAPTY_API_BASE_URL ?? DEFAULT_BASE_URL,
    premiumAccessLevel:
      process.env.ADAPTY_PREMIUM_ACCESS_LEVEL ?? DEFAULT_PREMIUM_LEVEL,
  };
}

export function isAdaptyConfigured(): boolean {
  return !!process.env.ADAPTY_SECRET_KEY;
}

export async function fetchProfile(
  profileId: string,
): Promise<AdaptyProfileResponse> {
  const config = loadConfig();
  const url = `${config.baseUrl}/server-side-api/profile/${encodeURIComponent(profileId)}`;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const response = await fetch(url, {
      method: "GET",
      headers: {
        Authorization: `Api-Key ${config.secretKey}`,
        Accept: "application/json",
      },
      signal: controller.signal,
    });
    const text = await response.text();
    if (!response.ok) {
      throw new AdaptyApiError(response.status, text);
    }
    return text ? (JSON.parse(text) as AdaptyProfileResponse) : {};
  } finally {
    clearTimeout(timer);
  }
}

// Pure function — easy to unit test without hitting the network.
export function resolveEntitlementFromProfile(
  profile: AdaptyProfileResponse,
  options: { premiumAccessLevel?: string; now?: Date } = {},
): ResolvedEntitlement {
  const levelName =
    options.premiumAccessLevel ??
    process.env.ADAPTY_PREMIUM_ACCESS_LEVEL ??
    DEFAULT_PREMIUM_LEVEL;
  const now = options.now ?? new Date();

  const level = profile.data?.attributes?.access_levels?.[levelName];
  if (!level || level.is_active !== true) {
    return { isPremium: false, expiresAt: null };
  }

  const expiresAt = level.expires_at ? new Date(level.expires_at) : null;
  // Lifetime entitlements come without expires_at — treat as active.
  if (expiresAt && expiresAt.getTime() <= now.getTime()) {
    return { isPremium: false, expiresAt };
  }
  return { isPremium: true, expiresAt };
}

export async function resolveEntitlementForProfile(
  profileId: string,
): Promise<ResolvedEntitlement> {
  const profile = await fetchProfile(profileId);
  return resolveEntitlementFromProfile(profile);
}
