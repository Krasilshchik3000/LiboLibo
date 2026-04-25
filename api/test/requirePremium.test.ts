import { describe, it, expect, vi } from "vitest";
import type { Request, Response, NextFunction } from "express";
import { requirePremium } from "../src/middleware/requirePremium.js";

function makeReq(viewer: Request["viewer"]): Request {
  return { viewer } as unknown as Request;
}

function makeRes(): {
  res: Response;
  status: ReturnType<typeof vi.fn>;
  json: ReturnType<typeof vi.fn>;
} {
  const json = vi.fn();
  const status = vi.fn(() => ({ json }));
  const res = { status } as unknown as Response;
  return { res, status, json };
}

describe("requirePremium", () => {
  it("calls next() when viewer is premium", () => {
    const req = makeReq({ hasPremiumEntitlement: true });
    const { res } = makeRes();
    const next = vi.fn() as unknown as NextFunction;

    requirePremium(req, res, next);

    expect(next).toHaveBeenCalledOnce();
  });

  it("responds 402 premium_required when viewer is not premium", () => {
    const req = makeReq({ hasPremiumEntitlement: false });
    const { res, status, json } = makeRes();
    const next = vi.fn() as unknown as NextFunction;

    requirePremium(req, res, next);

    expect(next).not.toHaveBeenCalled();
    expect(status).toHaveBeenCalledWith(402);
    expect(json).toHaveBeenCalledWith({ error: "premium_required" });
  });

  it("calls next(error) if req.viewer is missing (wiring bug)", () => {
    const req = makeReq(undefined);
    const { res } = makeRes();
    const next = vi.fn() as unknown as NextFunction;

    requirePremium(req, res, next);

    expect(next).toHaveBeenCalledOnce();
    const arg = (next as unknown as { mock: { calls: unknown[][] } }).mock
      .calls[0]?.[0];
    expect(arg).toBeInstanceOf(Error);
  });
});
