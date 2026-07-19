import { z } from "zod";

const EnvSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().int().min(1).max(65535).default(8080),
  LOG_LEVEL: z.enum(["fatal", "error", "warn", "info", "debug", "trace", "silent"]).default("info"),
  DATABASE_URL: z.url(),
  DATABASE_POOL_MAX: z.coerce.number().int().min(1).max(100).default(10),
  WEBSITE_BASE_URL: z.url().default("https://writerflow.app")
});

export type AppConfig = z.infer<typeof EnvSchema>;

/**
 * Parses process.env once at startup. Throws with a field-level message (never
 * the offending value — DATABASE_URL carries a password) if anything is
 * missing/invalid, so a misconfigured deploy fails fast instead of starting
 * with a silently wrong default.
 */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  const result = EnvSchema.safeParse(env);
  if (!result.success) {
    const fields = result.error.issues.map((issue) => issue.path.join(".")).join(", ");
    throw new Error(`Invalid environment configuration for fields: ${fields}`);
  }
  return result.data;
}
