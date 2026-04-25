import type { RequestHandler } from "express";
import { prisma } from "../db.js";
import type { ViewerContext } from "../lib/serialize.js";

declare global {
  namespace Express {
    interface Request {
      viewer?: ViewerContext;
      adaptyProfileId?: string;
    }
  }
}

const HEADER = "x-adapty-profile-id";
// UUID v1–v8, case-insensitive. Reject anything else early so we never query
// the DB with garbage from the wire.
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const ANONYMOUS: ViewerContext = { hasPremiumEntitlement: false };

// Reads X-Adapty-Profile-Id, looks up the cached entitlement, and attaches
// `req.viewer` for downstream handlers. Never calls Adapty — that's the job of
// `POST /v1/me/entitlement/refresh`. Missing/invalid header → anonymous viewer.
export const resolveViewer: RequestHandler = async (req, _res, next) => {
  try {
    const raw = req.header(HEADER);
    if (!raw || !UUID_RE.test(raw)) {
      req.viewer = ANONYMOUS;
      return next();
    }
    req.adaptyProfileId = raw;

    const entitlement = await prisma.entitlement.findUnique({
      where: { adaptyProfileId: raw },
    });
    if (!entitlement || !entitlement.isPremium) {
      req.viewer = ANONYMOUS;
      return next();
    }
    if (
      entitlement.expiresAt &&
      entitlement.expiresAt.getTime() <= Date.now()
    ) {
      req.viewer = ANONYMOUS;
      return next();
    }
    req.viewer = { hasPremiumEntitlement: true };
    next();
  } catch (err) {
    next(err);
  }
};
