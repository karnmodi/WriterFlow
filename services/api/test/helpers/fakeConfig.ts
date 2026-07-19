import type { AppConfig } from "../../src/config.js";

export function fakeConfig(overrides: Partial<AppConfig> = {}): AppConfig {
  return {
    NODE_ENV: "test",
    PORT: 0,
    LOG_LEVEL: "silent",
    DATABASE_URL: "postgres://user:pass@localhost:5432/db",
    DATABASE_POOL_MAX: 1,
    WEBSITE_BASE_URL: "https://writerflow.app",
    ...overrides
  };
}
