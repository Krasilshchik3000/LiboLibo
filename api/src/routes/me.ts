import { Router } from "express";
import { prisma } from "../db.js";
import { asyncHandler } from "../lib/asyncHandler.js";
import {
  AdaptyApiError,
  AdaptyConfigError,
  isAdaptyConfigured,
  resolveEntitlementForProfile,
} from "../lib/adapty.js";

export const meRouter = Router();

const HEADER = "x-adapty-profile-id";
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const REFRESH_COOLDOWN_MS = 5_000;
const lastRefreshAt = new Map<string, number>();

function readProfileId(req: { header: (n: string) => string | undefined }): string | null {
  const raw = req.header(HEADER);
  if (!raw || !UUID_RE.test(raw)) return null;
  return raw;
}

meRouter.post(
  "/me/entitlement/refresh",
  asyncHandler(async (req, res) => {
    const profileId = readProfileId(req);
    if (!profileId) {
      return res
        .status(400)
        .json({ error: "missing_profile_id", message: "X-Adapty-Profile-Id required" });
    }

    if (!isAdaptyConfigured()) {
      return res.status(503).json({
        error: "entitlement_unavailable",
        message: "ADAPTY_SECRET_KEY is not configured on the server",
      });
    }

    const now = Date.now();
    const last = lastRefreshAt.get(profileId);
    if (last && now - last < REFRESH_COOLDOWN_MS) {
      const retryAfterSec = Math.ceil((REFRESH_COOLDOWN_MS - (now - last)) / 1000);
      res.setHeader("Retry-After", String(retryAfterSec));
      return res.status(429).json({ error: "rate_limited" });
    }
    lastRefreshAt.set(profileId, now);

    let resolved;
    try {
      resolved = await resolveEntitlementForProfile(profileId);
    } catch (err) {
      if (err instanceof AdaptyConfigError) {
        return res.status(503).json({ error: "entitlement_unavailable" });
      }
      if (err instanceof AdaptyApiError) {
        // 4xx from Adapty (e.g. profile not found) → treat as no entitlement.
        if (err.status >= 400 && err.status < 500) {
          await prisma.entitlement.upsert({
            where: { adaptyProfileId: profileId },
            create: {
              adaptyProfileId: profileId,
              isPremium: false,
              expiresAt: null,
            },
            update: { isPremium: false, expiresAt: null },
          });
          return res.json({
            is_premium: false,
            expires_at: null,
            checked_at: new Date().toISOString(),
          });
        }
      }
      throw err;
    }

    await prisma.entitlement.upsert({
      where: { adaptyProfileId: profileId },
      create: {
        adaptyProfileId: profileId,
        isPremium: resolved.isPremium,
        expiresAt: resolved.expiresAt,
      },
      update: {
        isPremium: resolved.isPremium,
        expiresAt: resolved.expiresAt,
      },
    });

    res.json({
      is_premium: resolved.isPremium,
      expires_at: resolved.expiresAt ? resolved.expiresAt.toISOString() : null,
      checked_at: new Date().toISOString(),
    });
  }),
);

meRouter.get(
  "/me/entitlement",
  asyncHandler(async (req, res) => {
    const profileId = readProfileId(req);
    if (!profileId) {
      return res.json({ is_premium: false, expires_at: null });
    }
    const entitlement = await prisma.entitlement.findUnique({
      where: { adaptyProfileId: profileId },
    });
    if (!entitlement) {
      return res.json({ is_premium: false, expires_at: null });
    }
    const expired =
      entitlement.expiresAt && entitlement.expiresAt.getTime() <= Date.now();
    res.json({
      is_premium: entitlement.isPremium && !expired,
      expires_at: entitlement.expiresAt ? entitlement.expiresAt.toISOString() : null,
    });
  }),
);
