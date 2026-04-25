import type { Request, Response, NextFunction, RequestHandler } from "express";

// Wraps an async route so rejected promises propagate to Express error
// middleware instead of crashing the process.
export function asyncHandler(
  fn: (req: Request, res: Response, next: NextFunction) => Promise<unknown>,
): RequestHandler {
  return (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}
