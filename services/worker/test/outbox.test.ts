import { describe, expect, it, vi } from "vitest";
import { claimDueOutboxBatch } from "../src/outbox.js";

describe("claimDueOutboxBatch", () => {
  it("issues a SKIP LOCKED claim query with the requested batch size", async () => {
    const rows = [{ id: "1", organization_id: "org-1", event_type: "usage.reconcile", payload: {}, attempts: 1 }];
    const client = { query: vi.fn().mockResolvedValue({ rows }) };
    const result = await claimDueOutboxBatch(client as never, 25);
    expect(result).toEqual(rows);
    const [sql, params] = client.query.mock.calls[0] as [string, unknown[]];
    expect(sql).toMatch(/FOR UPDATE SKIP LOCKED/);
    expect(sql).toMatch(/status = 'processing'/);
    expect(params).toEqual([25]);
  });
});
