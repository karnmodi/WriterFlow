import { createHash, timingSafeEqual } from "node:crypto";

/** RFC 7636 S256: BASE64URL(SHA256(code_verifier)). */
export function computeS256Challenge(codeVerifier: string): string {
  return createHash("sha256").update(codeVerifier).digest("base64url");
}

export function verifyPkce(codeVerifier: string, expectedChallenge: string): boolean {
  const computed = computeS256Challenge(codeVerifier);
  const computedBuf = Buffer.from(computed);
  const expectedBuf = Buffer.from(expectedChallenge);
  if (computedBuf.length !== expectedBuf.length) return false;
  return timingSafeEqual(computedBuf, expectedBuf);
}
