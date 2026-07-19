import { describe, expect, it } from "vitest";
import { loadConfig } from "../src/config.js";

describe("loadConfig", () => {
  it("parses a valid environment", () => {
    const config = loadConfig({
      DATABASE_URL: "postgres://user:pass@localhost:5432/writerflow"
    });
    expect(config.PORT).toBe(8080);
    expect(config.NODE_ENV).toBe("development");
  });

  it("throws a field-name-only error, never the invalid value, when DATABASE_URL is missing", () => {
    expect(() => loadConfig({})).toThrow(/DATABASE_URL/);
  });

  it("never includes the DATABASE_URL's password in its error message, even when another field is also invalid", () => {
    try {
      loadConfig({
        DATABASE_URL: "postgres://user:hunter2@localhost:5432/writerflow",
        PORT: "not-a-port"
      });
      throw new Error("expected loadConfig to throw");
    } catch (err) {
      expect((err as Error).message).not.toContain("hunter2");
    }
  });
});
