import { PrismaClient } from "@prisma/client";

// Single PrismaClient per process. The `globalThis` cache prevents creating
// duplicate clients on hot-reload (`tsx watch`) in dev.
declare global {
  // eslint-disable-next-line no-var
  var __prisma: PrismaClient | undefined;
}

export const prisma = globalThis.__prisma ?? new PrismaClient();

if (process.env.NODE_ENV !== "production") {
  globalThis.__prisma = prisma;
}

// Prisma returns BigInt for `id` fields. JSON.stringify can't serialize BigInt
// natively, so we coerce to Number at JSON time. iTunes podcast IDs fit safely
// in Number (< 2^53).
(BigInt.prototype as unknown as { toJSON: () => number }).toJSON = function () {
  return Number(this as unknown as bigint);
};
