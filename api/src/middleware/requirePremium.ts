import type { RequestHandler } from "express";

// Use AFTER resolveViewer. Rejects with 402 if the viewer doesn't have an
// active premium entitlement. Wiring guard: if req.viewer is undefined,
// resolveViewer wasn't applied — that's a server-side mistake, surface it.
export const requirePremium: RequestHandler = (req, res, next) => {
  if (req.viewer === undefined) {
    return next(
      new Error(
        "requirePremium: req.viewer is undefined — apply resolveViewer first",
      ),
    );
  }
  if (!req.viewer.hasPremiumEntitlement) {
    res.status(402).json({ error: "premium_required" });
    return;
  }
  next();
};
