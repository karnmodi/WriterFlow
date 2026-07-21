import { NextResponse } from "next/server";

// Liveness/readiness probe for infra/bicep/modules/container-app-website.bicep.
// No dependency checks (database, Entra, etc.) — this route only proves the
// Next.js server process itself is up and serving requests, matching the
// scope of a Container Apps liveness probe. Add dependency checks here only
// if/when this app gains something worth failing readiness on.
export function GET() {
  return NextResponse.json({ status: "ok" });
}
