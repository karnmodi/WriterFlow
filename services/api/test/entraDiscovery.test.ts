import { describe, expect, it } from "vitest";
import { resolveEntraUserInfoEndpoint } from "../src/entra/discovery.js";

describe("resolveEntraUserInfoEndpoint", () => {
  it("uses configured override when set", async () => {
    await expect(
      resolveEntraUserInfoEndpoint("https://tenant.ciamlogin.com/t/v2.0", "https://custom.example/userinfo")
    ).resolves.toBe("https://custom.example/userinfo");
  });

  it("reads userinfo_endpoint from live CIAM discovery for writerflow tenant", async () => {
    const issuer =
      "https://01b8e65a-4311-4a8d-b70c-648164918950.ciamlogin.com/01b8e65a-4311-4a8d-b70c-648164918950/v2.0";
    await expect(resolveEntraUserInfoEndpoint(issuer)).resolves.toBe("https://graph.microsoft.com/oidc/userinfo");
  }, 15_000);
});
