import { z } from "zod";

const EnvSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().int().min(1).max(65535).default(8080),
  LOG_LEVEL: z.enum(["fatal", "error", "warn", "info", "debug", "trace", "silent"]).default("info"),
  DATABASE_URL: z.url(),
  DATABASE_POOL_MAX: z.coerce.number().int().min(1).max(100).default(10),
  WEBSITE_BASE_URL: z.url().default("https://writerflow.aviusolutions.com"),
  APIM_ORIGIN_SECRET: z.string().min(32).optional(),
  // Optional: no Entra External ID tenant exists yet (cloud apply pending).
  // POST /v2/web-session/token returns a clear "not configured" error
  // rather than the app failing to boot when these are unset.
  ENTRA_TENANT_ISSUER: z.url().optional(),
  ENTRA_JWKS_URI: z.url().optional(),
  ENTRA_USERINFO_URI: z.url().optional(),
  ENTRA_WEB_CLIENT_ID: z.string().min(1).optional(),
  JWT_SIGNING_KEY_VAULT_URL: z.url().optional(),
  JWT_SIGNING_KEY_NAME: z.string().min(1).optional(),
  JWT_SIGNING_PREVIOUS_KEY_NAMES: z.string().optional(),
  AZURE_OPENAI_ENDPOINT: z.url().optional(),
  AZURE_OPENAI_DEPLOYMENT: z.string().min(1).optional(),
  AZURE_OPENAI_GRAMMAR_FAST_DEPLOYMENT: z.string().min(1).optional(),
  AZURE_OPENAI_REWRITE_STANDARD_DEPLOYMENT: z.string().min(1).optional(),
  AZURE_OPENAI_PROMPT_ENHANCER_DEPLOYMENT: z.string().min(1).optional(),
  AZURE_OPENAI_PREMIUM_DEPLOYMENT: z.string().min(1).optional(),
  AZURE_OPENAI_FALLBACK_DEPLOYMENT: z.string().min(1).optional(),
  // Optional: Stripe billing (Phase 7). Checkout/Portal return 501 and webhooks
  // return 503 until these are configured in the target environment.
  STRIPE_SECRET_KEY: z.string().min(1).optional(),
  STRIPE_WEBHOOK_SECRET: z.string().min(1).optional()
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
