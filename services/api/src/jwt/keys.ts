import { exportJWK, generateKeyPair, importJWK, type JWK } from "jose";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export interface SigningKey {
  kid: string;
  privateKey: CryptoKey;
  publicJwk: JWK;
}

interface PersistedDevSigningKey {
  kid: string;
  privateJwk: JWK;
  publicJwk: JWK;
}

/**
 * ADR-0012's device-token issuer needs an asymmetric key that supports
 * rollover: sign with exactly one "current" key, but keep publishing
 * recently-retired keys in JWKS long enough for their still-live tokens to
 * finish verifying. This interface is the seam — LocalDevSigningKeyProvider
 * below is dev-only; a KeyVaultSigningKeyProvider (Key Vault sign operation,
 * private key never leaves Key Vault) is Stage 5.1/5.2's Azure-skeleton
 * cloud-apply-pending item, not yet implemented.
 */
export interface SigningKeyProvider {
  getCurrentSigningKey(): Promise<SigningKey>;
  getVerificationKey(kid: string): Promise<CryptoKey | null>;
  getPublicJwks(): Promise<{ keys: JWK[] }>;
  /** When set (Key Vault), signs the ES256 digest externally instead of using privateKey. */
  signDigest?(digest: Uint8Array): Promise<Uint8Array>;
}

const DEV_KEY_PATH = join(dirname(fileURLToPath(import.meta.url)), "../../.dev-signing-key.json");

function persistDevSigningKey(stored: PersistedDevSigningKey): void {
  mkdirSync(dirname(DEV_KEY_PATH), { recursive: true });
  writeFileSync(DEV_KEY_PATH, `${JSON.stringify(stored, null, 2)}\n`, { mode: 0o600 });
}

async function loadPersistedDevSigningKey(): Promise<SigningKey | null> {
  if (!existsSync(DEV_KEY_PATH)) return null;
  try {
    const raw: unknown = JSON.parse(readFileSync(DEV_KEY_PATH, "utf8"));
    if (!raw || typeof raw !== "object") return null;
    const stored = raw as Record<string, unknown>;
    if (typeof stored.kid !== "string" || !stored.privateJwk || !stored.publicJwk) {
      return null;
    }
    const privateJwk = stored.privateJwk as JWK;
    const publicJwk = stored.publicJwk as JWK;
    const privateKey = (await importJWK(privateJwk, "ES256")) as CryptoKey;
    return { kid: stored.kid, privateKey, publicJwk };
  } catch {
    return null;
  }
}

/**
 * Dev-only signing key provider. Persists one ES256 key pair to
 * `services/api/.dev-signing-key.json` so `tsx watch` restarts do not
 * invalidate every locally paired device token. Never used in staging/prod.
 */
export class LocalDevSigningKeyProvider implements SigningKeyProvider {
  private keyPromise: Promise<SigningKey> | null = null;

  private async loadOrGenerate(): Promise<SigningKey> {
    const persisted = await loadPersistedDevSigningKey();
    if (persisted) return persisted;

    const { privateKey, publicKey } = await generateKeyPair("ES256", { extractable: true });
    const publicJwk = await exportJWK(publicKey);
    const kid = createHash("sha256").update(JSON.stringify(publicJwk)).digest("hex").slice(0, 16);
    publicJwk.kid = kid;
    publicJwk.alg = "ES256";
    publicJwk.use = "sig";
    const privateJwk = await exportJWK(privateKey);
    persistDevSigningKey({ kid, privateJwk, publicJwk });
    return { kid, privateKey, publicJwk };
  }

  private async current(): Promise<SigningKey> {
    this.keyPromise ??= this.loadOrGenerate();
    return this.keyPromise;
  }

  async getCurrentSigningKey(): Promise<SigningKey> {
    return this.current();
  }

  async getVerificationKey(kid: string): Promise<CryptoKey | null> {
    const key = await this.current();
    if (key.kid !== kid) return null;
    return importJWK(key.publicJwk, "ES256") as Promise<CryptoKey>;
  }

  async getPublicJwks(): Promise<{ keys: JWK[] }> {
    const key = await this.current();
    return { keys: [key.publicJwk] };
  }
}
