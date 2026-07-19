import { createHash, randomBytes, randomInt } from "node:crypto";

/** Opaque, single-use, high-entropy — device_code and refresh tokens. */
export function generateOpaqueToken(): string {
  return randomBytes(32).toString("base64url");
}

export function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

// Crockford-ish alphabet minus visually ambiguous characters (0/O, 1/I/L, and
// U to avoid accidental profanity) — short, human-typed, read aloud/entered
// at writerflow.app/pair. Not itself a secret (Docs/v2-threat-model.md
// "user_code guessing" is mitigated by short expiry + APIM rate limiting on
// /device/token, not by user_code entropy alone).
const USER_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTVWXYZ23456789";

function pickChar(): string {
  const char = USER_CODE_ALPHABET[randomInt(USER_CODE_ALPHABET.length)];
  if (char === undefined) throw new Error("unreachable: randomInt result out of alphabet bounds");
  return char;
}

export function generateUserCode(): string {
  const group = (): string => Array.from({ length: 4 }, pickChar).join("");
  return `${group()}-${group()}`;
}
