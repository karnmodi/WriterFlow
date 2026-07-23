/** Shared WriterFlow API base URL for website server routes. */
export function writerFlowApiBaseUrl(): string {
  return process.env["WRITERFLOW_API_BASE_URL"] ?? "https://apiwriterflow.aviusolutions.com/v2";
}

interface ApiErrorPayload {
  code?: string;
  requestId?: string;
}

export class WriterFlowAPIRequestError extends Error {
  readonly status: number;
  readonly code: string | undefined;
  readonly requestId: string | undefined;

  constructor(route: string, status: number, payload: ApiErrorPayload) {
    const publicMessage = status === 401
      ? "WriterFlow could not verify this sign-in. Please try again."
      : status === 403
        ? "This account cannot access WriterFlow."
        : status === 429
          ? "Too many attempts. Wait a moment and try again."
          : status >= 500
            ? "WriterFlow's account service is temporarily unavailable."
            : `WriterFlow could not complete ${route}.`;
    const reference = payload.requestId ? ` Reference: ${payload.requestId}.` : "";
    super(`${publicMessage}${reference}`);
    this.name = "WriterFlowAPIRequestError";
    this.status = status;
    this.code = payload.code;
    this.requestId = payload.requestId;
  }
}

async function apiRequestError(route: string, response: Response): Promise<WriterFlowAPIRequestError> {
  const payload = await response.json().catch(() => ({})) as ApiErrorPayload;
  const requestId = payload.requestId ?? response.headers.get("x-request-id") ?? undefined;
  return new WriterFlowAPIRequestError(route, response.status, { ...payload, requestId });
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
    throw await apiRequestError("account sign-in", response);
  }
  return (await response.json()) as { accessToken: string; expiresIn: number };
}

export async function fetchWebMe(accessToken: string): Promise<WebAccountSnapshot | null> {
  const response = await fetch(`${writerFlowApiBaseUrl()}/web/me`, {
    headers: { Authorization: `Bearer ${accessToken}` }
  });
  if (response.status === 401 || response.status === 403) return null;
  if (!response.ok) {
    throw await apiRequestError("account loading", response);
  }
  return (await response.json()) as WebAccountSnapshot;
}

export async function bridgeWebSession(accessToken: string): Promise<string> {
  const response = await fetch(`${writerFlowApiBaseUrl()}/web-session/bridge`, {
    method: "POST",
    headers: { Authorization: `Bearer ${accessToken}` }
  });
  if (!response.ok) {
    throw await apiRequestError("device pairing", response);
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
    throw await apiRequestError("device pairing", response);
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
