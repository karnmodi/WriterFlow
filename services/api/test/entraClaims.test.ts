import { describe, expect, it } from "vitest";
import { extractDisplayFromPayload, mergeIdentityDisplay, resolveUserInfoUrl } from "../src/entra/claims.js";
import type { EntraIdentity } from "../src/entra/verifier.js";

describe("entra claims", () => {
  it("resolves CIAM userinfo URL to Microsoft Graph OIDC userinfo", () => {
    expect(
      resolveUserInfoUrl("https://writerflow.ciamlogin.com/tenant-id/v2.0")
    ).toBe("https://graph.microsoft.com/oidc/userinfo");
  });

  it("merges supplemental userinfo into a sparse ID-token identity", () => {
    const identity: EntraIdentity = {
      issuer: "https://writerflow.ciamlogin.com/t/v2.0",
      subject: "user-1",
      displayName: null,
      email: "karan@example.com",
      displayClaims: { email: "karan@example.com" }
    };
    const supplemental = extractDisplayFromPayload({
      givenName: "Karan",
      surname: "Singh"
    });
    const merged = mergeIdentityDisplay(identity, supplemental);
    expect(merged.displayName).toBe("Karan Singh");
    expect(merged.email).toBe("karan@example.com");
    expect(merged.displayClaims.given_name).toBe("Karan");
    expect(merged.displayClaims.family_name).toBe("Singh");
  });
});
