import { describe, it, expect } from "vitest";
import { resolveEntitlementFromProfile } from "../src/lib/adapty.js";

describe("resolveEntitlementFromProfile", () => {
  it("returns premium when access level is active and not expired", () => {
    const future = new Date("2099-01-01T00:00:00.000Z");
    const result = resolveEntitlementFromProfile({
      data: {
        attributes: {
          access_levels: {
            premium: { is_active: true, expires_at: future.toISOString() },
          },
        },
      },
    });
    expect(result.isPremium).toBe(true);
    expect(result.expiresAt?.toISOString()).toBe(future.toISOString());
  });

  it("treats lifetime entitlement (no expires_at) as active", () => {
    const result = resolveEntitlementFromProfile({
      data: {
        attributes: {
          access_levels: {
            premium: { is_active: true, expires_at: null },
          },
        },
      },
    });
    expect(result.isPremium).toBe(true);
    expect(result.expiresAt).toBeNull();
  });

  it("returns not premium when access level is expired", () => {
    const past = new Date("2020-01-01T00:00:00.000Z");
    const result = resolveEntitlementFromProfile({
      data: {
        attributes: {
          access_levels: {
            premium: { is_active: true, expires_at: past.toISOString() },
          },
        },
      },
      // is_active still true in Adapty grace periods, but our `now` says expired.
    }, { now: new Date("2026-04-25T00:00:00.000Z") });
    expect(result.isPremium).toBe(false);
  });

  it("returns not premium when access level has is_active=false", () => {
    const result = resolveEntitlementFromProfile({
      data: {
        attributes: {
          access_levels: {
            premium: { is_active: false, expires_at: null },
          },
        },
      },
    });
    expect(result.isPremium).toBe(false);
  });

  it("returns not premium when there is no access_levels at all", () => {
    expect(resolveEntitlementFromProfile({}).isPremium).toBe(false);
    expect(resolveEntitlementFromProfile({ data: {} }).isPremium).toBe(false);
    expect(
      resolveEntitlementFromProfile({ data: { attributes: {} } }).isPremium,
    ).toBe(false);
  });

  it("respects custom premiumAccessLevel name", () => {
    const result = resolveEntitlementFromProfile(
      {
        data: {
          attributes: {
            access_levels: {
              vip: { is_active: true, expires_at: null },
            },
          },
        },
      },
      { premiumAccessLevel: "vip" },
    );
    expect(result.isPremium).toBe(true);
  });
});
