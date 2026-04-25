// HTTP Basic Auth middleware for /admin. Credentials read from env:
// ADMIN_USER, ADMIN_PASSWORD. If either is missing, /admin returns 503
// to make the misconfiguration visible (instead of silently allowing all).

import type { Request, Response, NextFunction } from "express";
import auth from "basic-auth";
import { timingSafeEqual } from "node:crypto";

export function basicAuth(req: Request, res: Response, next: NextFunction): void {
  const expectedUser = process.env.ADMIN_USER;
  const expectedPass = process.env.ADMIN_PASSWORD;
  if (!expectedUser || !expectedPass) {
    res.status(503).type("text/plain").send("admin disabled: ADMIN_USER/ADMIN_PASSWORD not set");
    return;
  }

  const credentials = auth(req);
  if (!credentials || !safeEqual(credentials.name, expectedUser) || !safeEqual(credentials.pass, expectedPass)) {
    res.set("WWW-Authenticate", 'Basic realm="LiboLibo admin"');
    res.status(401).type("text/plain").send("authentication required");
    return;
  }
  next();
}

function safeEqual(a: string, b: string): boolean {
  const ab = Buffer.from(a);
  const bb = Buffer.from(b);
  if (ab.length !== bb.length) return false;
  return timingSafeEqual(ab, bb);
}
