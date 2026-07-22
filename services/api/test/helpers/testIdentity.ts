import type { EntraIdentity } from "../../src/entra/verifier.js";

/** Minimal EntraIdentity for integration tests — includes display fields. */
export function testEntraIdentity(subject: string, overrides: Partial<EntraIdentity> = {}): EntraIdentity {
  const displayName = overrides.displayName ?? "Test User";
  // Unique per subject so Microsoft/OTP linking tests don't collide across suites.
  const email = overrides.email ?? `${subject.replace(/[^a-zA-Z0-9_-]/g, "_")}@example.com`;
  return {
    issuer: overrides.issuer ?? "https://writerflow.ciamlogin.com/t/v2.0",
    subject,
    displayName,
    email,
    displayClaims: overrides.displayClaims ?? { name: displayName, email }
  };
}
