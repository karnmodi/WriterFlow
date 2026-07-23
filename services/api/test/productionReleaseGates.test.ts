import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

function repositoryFile(path: string): string {
  return readFileSync(resolve(process.cwd(), "../..", path), "utf8");
}

describe("production release gates", () => {
  it("uses GitHub workload identity and immutable image tags", () => {
    const workflow = repositoryFile(".github/workflows/azure-deploy-dev.yml");

    expect(workflow).toContain("id-token: write");
    expect(workflow).toContain("client-id: ${{ vars.AZURE_CLIENT_ID }}");
    expect(workflow).toContain("IMAGE_TAG: ${{ github.sha }}");
    expect(workflow).toContain("environment: ${{ inputs.environment }}");
    expect(workflow).toContain("PROFILE: private-beta-public");
    expect(workflow).not.toContain("PROFILE: production-private");
    expect(workflow).not.toContain("AZURE_CREDENTIALS");
    expect(workflow).not.toMatch(/creds:\s*\$\{\{/);
    expect(workflow).not.toContain("writerflow-api:latest");
  });

  it("runs migrations as a private, least-privilege Container Apps Job", () => {
    const workflow = repositoryFile(".github/workflows/azure-deploy-dev.yml");
    const migrationJob = repositoryFile("infra/bicep/modules/container-app-migrations.bicep");

    expect(workflow).toContain("az containerapp job start");
    expect(workflow).toContain("writerflow-migrations:$IMAGE_TAG");
    expect(migrationJob).toContain("triggerType: 'Manual'");
    expect(migrationJob).toContain("replicaRetryLimit: 0");
    expect(migrationJob).toContain("keyVaultUrl: databaseUrlSecretUri");
  });

  it("provisions metadata-only operational alerts", () => {
    const monitoring = repositoryFile("infra/bicep/modules/monitoring.bicep");

    for (const alert of ["api-5xx", "auth-failures", "api-latency", "sse-disconnects", "ledger-mismatch"]) {
      expect(monitoring).toContain(`name: '${alert}'`);
    }
    expect(monitoring).not.toMatch(/\b(draft|prompt|context|inputText)\b/i);
  });

  it("keeps the beta on Developer APIM without dedicated model capacity", () => {
    const main = repositoryFile("infra/bicep/main.bicep");
    const apim = repositoryFile("infra/bicep/modules/apim.bicep");
    const policy = repositoryFile("infra/apim/api-policy-dev.xml");

    expect(main).toContain("param deployAzureOpenAIModel bool = false");
    expect(main).toContain("deploymentProfile == 'private-beta-public'");
    expect(apim).toContain("developerFallback ? 'Developer' : 'StandardV2'");
    expect(policy).toContain('name="X-WriterFlow-Origin"');
    expect(policy).toContain("{{writerflow-origin-secret}}");
  });
});
