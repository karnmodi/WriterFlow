import { exportJWK, generateKeyPair, importJWK, type JWK } from "jose";
import { createHash } from "node:crypto";

export interface SigningKey {
  kid: string;
  privateKey: CryptoKey;
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
}

/**
 * Generates one ES256 key pair per process start and keeps it in memory
 * only — never persisted, never Key Vault. Every dev-server restart mints a
 * new kid, which invalidates every previously issued token; that's expected
 * and fine for local development, and is exactly why this must never run in
 * staging/prod (CLAUDE.md Golden Rule 5's "no publisher-owned/shared
 * reusable service credential" concern is about the client, but a
 * server-side signing key that isn't Key Vault-backed is its own real risk
 * for a deployed environment — this class only exists for `npm run dev`).
 */
export class LocalDevSigningKeyProvider implements SigningKeyProvider {
  private keyPromise: Promise<SigningKey> | null = null;

  private async loadOrGenerate(): Promise<SigningKey> {
    const { privateKey, publicKey } = await generateKeyPair("ES256", { extractable: true });
    const publicJwk = await exportJWK(publicKey);
    const kid = createHash("sha256").update(JSON.stringify(publicJwk)).digest("hex").slice(0, 16);
    publicJwk.kid = kid;
    publicJwk.alg = "ES256";
    publicJwk.use = "sig";
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
