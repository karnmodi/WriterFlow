import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

describe("APIM inference stream policy", () => {
  const policy = readFileSync(
    resolve(process.cwd(), "../../infra/apim/inference-stream-operation-policy.xml"),
    "utf8"
  );

  it("preserves the client idempotency key and disables response buffering", () => {
    expect(policy).not.toMatch(/set-header\s+name="Idempotency-Key"/);
    expect(policy).not.toContain("context.RequestId");
    expect(policy).toContain('buffer-response="false"');
  });
});
