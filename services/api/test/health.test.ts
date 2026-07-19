import { describe, expect, it, vi } from "vitest";
import { buildApp } from "../src/app.js";
import type { AppConfig } from "../src/config.js";

function fakeConfig(): AppConfig {
  return {
    NODE_ENV: "test",
    PORT: 0,
    LOG_LEVEL: "silent",
    DATABASE_URL: "postgres://user:pass@localhost:5432/db",
    DATABASE_POOL_MAX: 1
  };
}

describe("health routes", () => {
  it("GET /healthz always returns ok without touching the pool", async () => {
    const pool = { query: vi.fn() };
    const app = buildApp({ config: fakeConfig(), pool: pool as never });
    const response = await app.inject({ method: "GET", url: "/healthz" });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ status: "ok" });
    expect(pool.query).not.toHaveBeenCalled();
    await app.close();
  });

  it("GET /readyz returns ready when the DB responds", async () => {
    const pool = { query: vi.fn().mockResolvedValue({ rows: [{ "?column?": 1 }] }) };
    const app = buildApp({ config: fakeConfig(), pool: pool as never });
    const response = await app.inject({ method: "GET", url: "/readyz" });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ status: "ready" });
    await app.close();
  });

  it("GET /readyz returns 503 without dependency detail when the DB is unreachable", async () => {
    const pool = { query: vi.fn().mockRejectedValue(new Error("connection refused at 10.0.0.5:5432")) };
    const app = buildApp({ config: fakeConfig(), pool: pool as never });
    const response = await app.inject({ method: "GET", url: "/readyz" });
    expect(response.statusCode).toBe(503);
    const body: unknown = response.json();
    expect(body).toEqual({ status: "not_ready" });
    expect(JSON.stringify(body)).not.toContain("10.0.0.5");
    await app.close();
  });
});
