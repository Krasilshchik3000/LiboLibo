import { Router } from "express";
import { prisma } from "../db.js";
import { asyncHandler } from "../lib/asyncHandler.js";

export const devicesRouter = Router();

interface DeviceBody {
  apns_token?: string | null;
}

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

devicesRouter.post(
  "/devices",
  asyncHandler(async (req, res) => {
    const body = (req.body ?? {}) as DeviceBody;
    const device = await prisma.device.create({
      data: {
        apnsToken: body.apns_token ?? null,
      },
    });
    res.status(201).json(toDTO(device));
  }),
);

devicesRouter.patch(
  "/devices/:id",
  asyncHandler(async (req, res) => {
    const rawId = req.params.id;
    if (typeof rawId !== "string" || !UUID_RE.test(rawId)) {
      return res.status(404).json({ error: "not_found" });
    }
    const body = (req.body ?? {}) as DeviceBody;

    try {
      const device = await prisma.device.update({
        where: { id: rawId },
        data: {
          ...(body.apns_token !== undefined && { apnsToken: body.apns_token }),
          lastSeenAt: new Date(),
        },
      });
      res.json(toDTO(device));
    } catch {
      res.status(404).json({ error: "not_found" });
    }
  }),
);

function toDTO(d: {
  id: string;
  apnsToken: string | null;
  createdAt: Date;
  lastSeenAt: Date;
}) {
  return {
    id: d.id,
    apns_token: d.apnsToken,
    created_at: d.createdAt.toISOString(),
    last_seen_at: d.lastSeenAt.toISOString(),
  };
}
