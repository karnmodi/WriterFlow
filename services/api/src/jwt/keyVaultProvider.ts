import { DefaultAzureCredential } from "@azure/identity";
import { CryptographyClient, KeyClient, type JsonWebKey } from "@azure/keyvault-keys";
import { importJWK, type JWK } from "jose";
import { createHash, generateKeyPairSync } from "node:crypto";
import type { SigningKey, SigningKeyProvider } from "./keys.js";

/** Azure Key Vault returns JsonWebKey — jose's exportJWK expects Web Crypto CryptoKey. */
function coerceBase64url(value: string | Uint8Array): string {
  return typeof value === "string" ? value : Buffer.from(value).toString("base64url");
}

export function jwkFromAzureKeyVault(key: JsonWebKey): JWK {
  if (key.kty !== "EC" || key.crv !== "P-256") {
    throw new Error(`Unsupported Key Vault key type ${key.kty ?? "unknown"}/${key.crv ?? "unknown"}`);
  }
  if (!key.x || !key.y) {
    throw new Error("Key Vault EC key is missing x/y coordinates");
  }
  return {
    kty: "EC",
    crv: "P-256",
    x: coerceBase64url(key.x),
    y: coerceBase64url(key.y)
  };
}

export function parsePreviousKeyNames(value: string | undefined, currentKeyName: string): string[] {
  return [...new Set(
    (value ?? "")
      .split(",")
      .map((name) => name.trim())
      .filter((name) => name.length > 0 && name !== currentKeyName)
  )];
}

/**
 * Production JWT signing via Azure Key Vault (Stage 5.1/5.2 cloud apply).
 * Private key never leaves Key Vault — ES256 signatures use CryptographyClient.
 */
export class KeyVaultSigningKeyProvider implements SigningKeyProvider {
  private readonly vaultUrl: string;
  private readonly keyName: string;
  private readonly previousKeyNames: readonly string[];
  private readonly cachedPublicKeys = new Map<string, { kid: string; publicJwk: JWK }>();
  private cryptoClientPromise: Promise<CryptographyClient> | null = null;

  constructor(vaultUrl: string, keyName: string, previousKeyNames: readonly string[] = []) {
    this.vaultUrl = vaultUrl.replace(/\/$/, "");
    this.keyName = keyName;
    this.previousKeyNames = previousKeyNames.filter((name) => name && name !== keyName);
  }

  private async getCryptoClient(): Promise<CryptographyClient> {
    this.cryptoClientPromise ??= (async () => {
      const credential = new DefaultAzureCredential();
      const keyClient = new KeyClient(this.vaultUrl, credential);
      const key = await keyClient.getKey(this.keyName);
      if (!key.id) throw new Error(`Key Vault key '${this.keyName}' has no id`);
      return new CryptographyClient(key.id, credential);
    })();
    return this.cryptoClientPromise;
  }

  private async loadPublicJwk(keyName: string): Promise<{ kid: string; publicJwk: JWK }> {
    const cached = this.cachedPublicKeys.get(keyName);
    if (cached) return cached;
    const credential = new DefaultAzureCredential();
    const keyClient = new KeyClient(this.vaultUrl, credential);
    const key = await keyClient.getKey(keyName);
    if (!key.key) throw new Error(`Key Vault key '${keyName}' has no public material`);
    const publicJwk = jwkFromAzureKeyVault(key.key);
    const kid = createHash("sha256").update(JSON.stringify(publicJwk)).digest("hex").slice(0, 16);
    publicJwk.kid = kid;
    publicJwk.alg = "ES256";
    publicJwk.use = "sig";
    const loaded = { kid, publicJwk };
    this.cachedPublicKeys.set(keyName, loaded);
    return loaded;
  }

  async getCurrentSigningKey(): Promise<SigningKey> {
    const { kid, publicJwk } = await this.loadPublicJwk(this.keyName);
    // Placeholder private key — issuer uses signDigest() instead.
    const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
    return { kid, privateKey: privateKey as unknown as CryptoKey, publicJwk };
  }

  async signDigest(digest: Uint8Array): Promise<Uint8Array> {
    const crypto = await this.getCryptoClient();
    const result = await crypto.sign("ES256", digest);
    return new Uint8Array(result.result);
  }

  async getVerificationKey(kid: string): Promise<CryptoKey | null> {
    for (const keyName of [this.keyName, ...this.previousKeyNames]) {
      const loaded = await this.loadPublicJwk(keyName);
      if (kid === loaded.kid) {
        return importJWK(loaded.publicJwk, "ES256") as Promise<CryptoKey>;
      }
    }
    return null;
  }

  async getPublicJwks(): Promise<{ keys: JWK[] }> {
    const keys = await Promise.all(
      [this.keyName, ...this.previousKeyNames].map(async (keyName) => {
        const { publicJwk } = await this.loadPublicJwk(keyName);
        return publicJwk;
      })
    );
    return { keys };
  }
}

/** Select signing provider from environment — dev file key vs Key Vault. */
export async function createSigningKeyProvider(env: NodeJS.ProcessEnv): Promise<SigningKeyProvider> {
  const vaultUrl = env["JWT_SIGNING_KEY_VAULT_URL"];
  const keyName = env["JWT_SIGNING_KEY_NAME"];
  if (vaultUrl && keyName) {
    const previousKeyNames = parsePreviousKeyNames(env["JWT_SIGNING_PREVIOUS_KEY_NAMES"], keyName);
    return new KeyVaultSigningKeyProvider(vaultUrl, keyName, previousKeyNames);
  }
  const { LocalDevSigningKeyProvider } = await import("./keys.js");
  return new LocalDevSigningKeyProvider();
}
