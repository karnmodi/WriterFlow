/** Shared WriterFlow API base URL for website server routes. */
export function writerFlowApiBaseUrl(): string {
  return process.env["WRITERFLOW_API_BASE_URL"] ?? "https://apiwriterflow.aviusolutions.com/v2";
}

export interface WebAccountSnapshot {
  userId: string;
  organizationId: string;
  displayName: string | null;
  email: string | null;
  entitlement: {
    plan: string;
    monthlyUnitsIncluded: number;
    monthlyUnitsUsed: number;
    features: string[];
  };
  privacy: {
    personalizationSyncEnabled: boolean;
    consentVersion: string;
  };
}

export async function mintWebAccountToken(body: {
  idToken: string;
  accessToken?: string;
}): Promise<{ accessToken: string; expiresIn: number }> {
  const response = await fetch(`${writerFlowApiBaseUrl()}/web-account/token`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body)
  });
  if (!response.ok) {
    throw new Error(`web-account/token failed (${response.status})`);
  }
  return (await response.json()) as { accessToken: string; expiresIn: number };
}

export async function fetchWebMe(accessToken: string): Promise<WebAccountSnapshot | null> {
  const response = await fetch(`${writerFlowApiBaseUrl()}/web/me`, {
    headers: { Authorization: `Bearer ${accessToken}` }
  });
  if (response.status === 401 || response.status === 403) return null;
  if (!response.ok) {
    throw new Error(`web/me failed (${response.status})`);
  }
  return (await response.json()) as WebAccountSnapshot;
}

export async function bridgeWebSession(accessToken: string): Promise<string> {
  const response = await fetch(`${writerFlowApiBaseUrl()}/web-session/bridge`, {
    method: "POST",
    headers: { Authorization: `Bearer ${accessToken}` }
  });
  if (!response.ok) {
    throw new Error(`web-session/bridge failed (${response.status})`);
  }
  const body = (await response.json()) as { accessToken: string };
  return body.accessToken;
}

export async function mintPairingBridge(body: {
  idToken: string;
  accessToken?: string;
}): Promise<string> {
  const response = await fetch(`${writerFlowApiBaseUrl()}/web-session/token`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body)
  });
  if (!response.ok) {
    throw new Error(`web-session/token failed (${response.status})`);
  }
  const parsed = (await response.json()) as { accessToken: string };
  return parsed.accessToken;
}

export async function approveDevice(userCode: string, webSessionToken: string): Promise<Response> {
  return fetch(`${writerFlowApiBaseUrl()}/device/approve`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${webSessionToken}`
    },
    body: JSON.stringify({ userCode })
  });
}
