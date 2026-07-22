import { afterAll, beforeAll, describe, expect, it } from "vitest";
import pg from "pg";
import { randomBytes } from "node:crypto";
import { resolveOrLinkUserFromEntra } from "../../src/account/identity.js";
import { testEntraIdentity } from "../helpers/testIdentity.js";

const APP_URL =
  process.env["TEST_DATABASE_URL_APP"] ??
  "postgres://writerflow_app:writerflow_app_dev_only@localhost:5432/writerflow";

async function probeReachable(connectionString: string): Promise<boolean> {
  const pool = new pg.Pool({ connectionString, connectionTimeoutMillis: 1500 });
  try {
    await pool.query("SELECT 1");
    return true;
  } catch {
    return false;
  } finally {
    await pool.end();
  }
}

const dbAvailable = await probeReachable(APP_URL);

describe.skipIf(!dbAvailable)("resolveOrLinkUserFromEntra — Microsoft + email OTP coexistence", () => {
  let pool: pg.Pool;

  beforeAll(() => {
    pool = new pg.Pool({ connectionString: APP_URL });
  });

  afterAll(async () => {
    await pool.end();
  });

  it("links a new Entra subject to an existing user when the same issuer+email already exists", async () => {
    const suffix = randomBytes(4).toString("hex");
    const email = `link-${suffix}@example.com`;
    const issuer = "https://writerflow.ciamlogin.com/t/v2.0";

    const microsoft = testEntraIdentity(`ms-sub-${suffix}`, {
      issuer,
      displayName: "Link User",
      email,
      displayClaims: { name: "Link User", email }
    });
    const first = await resolveOrLinkUserFromEntra(pool, microsoft);
    expect(first.kind).toBe("active");
    if (first.kind !== "active") return;
    expect(first.created).toBe(true);
    expect(first.linked).toBe(false);

    const otp = testEntraIdentity(`otp-sub-${suffix}`, {
      issuer,
      displayName: "Link User",
      email,
      displayClaims: { name: "Link User", email }
    });
    const second = await resolveOrLinkUserFromEntra(pool, otp);
    expect(second.kind).toBe("active");
    if (second.kind !== "active") return;
    expect(second.created).toBe(false);
    expect(second.linked).toBe(true);
    expect(second.userId).toBe(first.userId);
    expect(second.organizationId).toBe(first.organizationId);

    const rows = await pool.query<{ subject: string }>(
      `SELECT subject FROM auth_identities WHERE user_id = $1 ORDER BY subject`,
      [first.userId]
    );
    expect(rows.rows.map((r) => r.subject).sort()).toEqual([`ms-sub-${suffix}`, `otp-sub-${suffix}`].sort());
  });

  it("does not link across different emails under the same issuer", async () => {
    const suffix = randomBytes(4).toString("hex");
    const issuer = "https://writerflow.ciamlogin.com/t/v2.0";

    const a = await resolveOrLinkUserFromEntra(
      pool,
      testEntraIdentity(`a-${suffix}`, {
        issuer,
        email: `a-${suffix}@example.com`,
        displayClaims: { email: `a-${suffix}@example.com` }
      })
    );
    const b = await resolveOrLinkUserFromEntra(
      pool,
      testEntraIdentity(`b-${suffix}`, {
        issuer,
        email: `b-${suffix}@example.com`,
        displayClaims: { email: `b-${suffix}@example.com` }
      })
    );
    expect(a.kind).toBe("active");
    expect(b.kind).toBe("active");
    if (a.kind !== "active" || b.kind !== "active") return;
    expect(b.userId).not.toBe(a.userId);
    expect(b.created).toBe(true);
    expect(b.linked).toBe(false);
  });

  it("re-auth with the same subject is idempotent and does not create a second user", async () => {
    const suffix = randomBytes(4).toString("hex");
    const identity = testEntraIdentity(`same-${suffix}`, {
      email: `same-${suffix}@example.com`,
      displayClaims: { email: `same-${suffix}@example.com` }
    });
    const first = await resolveOrLinkUserFromEntra(pool, identity);
    const second = await resolveOrLinkUserFromEntra(pool, identity);
    expect(first.kind).toBe("active");
    expect(second.kind).toBe("active");
    if (first.kind !== "active" || second.kind !== "active") return;
    expect(second.userId).toBe(first.userId);
    expect(second.created).toBe(false);
    expect(second.linked).toBe(false);
  });
});
