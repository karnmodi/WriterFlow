import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { load as loadYaml } from "js-yaml";
import { z } from "zod";
import {
  LogicalRouteSchema,
  OutputModeHintSchema,
  SkillIdSchema,
  WritingActionSchema,
  type LogicalRoute,
  type OutputModeHint,
  type SkillId,
  type WritingAction
} from "@writerflow/shared";

const SkillManifestSchema = z.strictObject({
  id: SkillIdSchema,
  label: z.string().min(1).max(64),
  version: z.string().min(1),
  action: WritingActionSchema,
  route: LogicalRouteSchema,
  requiredSignals: z.array(z.string().min(1).max(64)).max(12),
  contextRequirement: z.enum(["none", "optional", "required"]),
  promptResource: z.string().min(1).max(256),
  guardrails: z.array(z.string().min(1).max(300)).min(1).max(12),
  directEligible: z.boolean(),
  includeConversation: z.boolean(),
  allowComposed: z.boolean(),
  outputModes: z.array(OutputModeHintSchema).min(1),
  maxOutputTokens: z.number().int().min(32).max(8192),
  confidenceThreshold: z.number().min(0).max(1),
  evalTags: z.array(z.string().min(1).max(64)).min(1).max(12),
  directive: z.string().min(1).max(1000)
});

const SkillRegistrySchema = z.strictObject({
  version: z.string().min(1),
  skills: z.array(SkillManifestSchema).min(1)
});

export interface SkillManifest {
  id: SkillId;
  label: string;
  version: string;
  action: WritingAction;
  route: LogicalRoute;
  requiredSignals: string[];
  contextRequirement: "none" | "optional" | "required";
  promptResource: string;
  guardrails: string[];
  directEligible: boolean;
  includeConversation: boolean;
  allowComposed: boolean;
  outputModes: OutputModeHint[];
  maxOutputTokens: number;
  confidenceThreshold: number;
  evalTags: string[];
  directive: string;
}

function defaultSkillsPath(): string {
  const candidates = [
    process.env["PROMPTS_DIR"],
    path.join(process.cwd(), "prompts"),
    path.join(process.cwd(), "..", "..", "prompts")
  ].filter((candidate): candidate is string => Boolean(candidate));
  const root = candidates.find((candidate) => existsSync(path.join(candidate, "skills.yaml")));
  return path.join(root ?? candidates[0] ?? path.join(process.cwd(), "prompts"), "skills.yaml");
}

export class SkillRegistry {
  readonly version: string;
  private readonly manifests: ReadonlyMap<SkillId, SkillManifest>;

  private constructor(version: string, manifests: ReadonlyMap<SkillId, SkillManifest>) {
    this.version = version;
    this.manifests = manifests;
  }

  static load(filePath = defaultSkillsPath()): SkillRegistry {
    const parsed = SkillRegistrySchema.parse(loadYaml(readFileSync(filePath, "utf8")));
    const manifests = new Map<SkillId, SkillManifest>();
    for (const manifest of parsed.skills) {
      if (manifests.has(manifest.id)) throw new Error(`Duplicate skill id: ${manifest.id}`);
      manifests.set(manifest.id, manifest);
    }
    for (const id of SkillIdSchema.options) {
      if (!manifests.has(id)) throw new Error(`Missing required skill manifest: ${id}`);
    }
    return new SkillRegistry(parsed.version, manifests);
  }

  get(id: SkillId): SkillManifest {
    const manifest = this.manifests.get(id);
    if (!manifest) throw new Error(`Unknown skill id: ${id}`);
    return manifest;
  }

  all(): readonly SkillManifest[] {
    return [...this.manifests.values()];
  }
}
