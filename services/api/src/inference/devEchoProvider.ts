import type { InferenceProvider, InferenceProviderRequest, InferenceStreamResult } from "./provider.js";

/**
 * Local-only stand-in used when no Azure model plane is configured. It does no
 * AI work, but applies a deterministic skill-aware rewrite so development runs
 * exercise selection, visible transformation, streaming, and replacement
 * rather than falsely reporting an unchanged echo as a successful rewrite.
 * Chunks output into a few deltas so callers exercise real streaming, not one
 * big `output.delta`.
 * Must never be reachable in a production deployment once a real provider
 * exists — there is no feature flag disabling it because there is nothing
 * to fall back from yet; index.ts is the only place that constructs it.
 */
export class DevEchoProvider implements InferenceProvider {
  stream(request: InferenceProviderRequest): InferenceStreamResult {
    if (request.route === "classifier_fast") {
      const classifier = JSON.stringify({
        skillId: request.envelope.signals.hasVisibleThread ? "reply" : "improve",
        confidence: 0.72,
        complexity: "low",
        includeConversation: request.envelope.signals.hasVisibleThread,
        outputMode: "replace",
        reasonCode: "dev_classifier"
      });
      return {
        deltas: (async function* (): AsyncGenerator<string> { yield await Promise.resolve(classifier); })(),
        usage: Promise.resolve({ inputTokens: 1, outputTokens: Math.ceil(classifier.length / 4) })
      };
    }
    const draft = request.envelope.content.draft;
    const transformed = transformDevelopmentOutput(request);
    const chunkCount = 3;
    const chunkSize = Math.max(1, Math.ceil(transformed.length / chunkCount));
    const chunks: string[] = [];
    for (let i = 0; i < transformed.length; i += chunkSize) {
      chunks.push(transformed.slice(i, i + chunkSize));
    }

    async function* generate(): AsyncGenerator<string> {
      for (const chunk of chunks) {
        // A real provider awaits network I/O per chunk; this microtask hop
        // keeps the interface honestly async without a fake delay.
        await Promise.resolve();
        yield chunk;
      }
    }

    return {
      deltas: generate(),
      usage: Promise.resolve({
        inputTokens: Math.ceil(draft.length / 4),
        outputTokens: Math.ceil(transformed.length / 4)
      })
    };
  }
}

/** Exported for a focused contract test; never used as production prose logic. */
export function transformDevelopmentOutput(request: InferenceProviderRequest): string {
  const selected = request.envelope.content.selectedText?.trim();
  const source = selected || request.envelope.content.draft.trim();
  const normalized = normalize(source);

  switch (request.skillId) {
    case "reply":
      if (!normalized) {
        return "Thank you for the message. I’ve noted the details and will follow up shortly.";
      }
      return visiblyImprove(normalized);
    case "shorten": {
      const concise = normalized
        .replace(/\b(in order to)\b/gi, "to")
        .replace(/\b(at this point in time)\b/gi, "now")
        .replace(/\b(very|really|basically|actually)\b\s*/gi, "")
        .replace(/[ \t]+/g, " ")
        .trim();
      return ensureVisibleChange(normalized, sentenceCase(concise));
    }
    case "expand":
      return visiblyImprove(normalized);
    case "continue":
      return visiblyImprove(normalized);
    case "prompt_enhance":
      return enhanceDevelopmentPrompt(normalized);
    case "custom_adjust": {
      const instruction = request.envelope.mode === "adjust"
        ? request.envelope.task.instruction.trim()
        : request.envelope.task.customInstruction?.trim();
      return applyDevelopmentAdjustment(normalized, instruction);
    }
    case "correct":
    case "improve":
    case "tone_adapt":
    default:
      return visiblyImprove(normalized);
  }
}

function normalize(value: string): string {
  return value
    .replace(/[ \t]+/g, " ")
    .replace(/ *\n */g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function visiblyImprove(value: string): string {
  const revised = sentenceCase(value)
    .replace(/\bcan you\b/gi, "Could you please")
    .replace(/\bi want to\b/gi, "I’d like to")
    .replace(/\bi need you to\b/gi, "I’d appreciate it if you could")
    .replace(/\bthanks\b/gi, "Thank you")
    .replace(/\bhey\b(?=[,\s])/gi, "Hello")
    .replace(/\bgonna\b/gi, "going to")
    .replace(/\bwanna\b/gi, "want to")
    .replace(/\s+-\s+thank you,?\s*/gi, ", thank you. ");
  const punctuated = /[.!?]$/.test(revised) ? revised : `${revised}.`;
  return ensureVisibleChange(value, punctuated);
}

function sentenceCase(value: string): string {
  return value.replace(/(^|[.!?]\s+)([a-z])/g, (_, prefix: string, letter: string) => {
    return `${prefix}${letter.toUpperCase()}`;
  });
}

function ensureVisibleChange(source: string, candidate: string): string {
  if (candidate !== source) return candidate;
  if (!candidate) return "Please add the message you want WriterFlow to improve.";
  // None of the deterministic rewrites changed anything (e.g. the source was
  // already sentence-cased and punctuated with no matching phrases). A dev
  // provider must never report an unchanged echo as a successful rewrite.
  return `${candidate} (reviewed — no changes needed.)`;
}

function applyDevelopmentAdjustment(value: string, instruction?: string): string {
  const normalizedInstruction = instruction?.toLocaleLowerCase() ?? "";
  if (/\b(short|shorter|concise|brief)\b/.test(normalizedInstruction)) {
    return value
      .replace(/\b(in order to)\b/gi, "to")
      .replace(/\b(at this point in time)\b/gi, "now")
      .replace(/\b(very|really|basically|actually)\b\s*/gi, "")
      .replace(/[ \t]+/g, " ")
      .trim();
  }
  return visiblyImprove(value);
}

const developmentPromptRequirements = new Set([
  "Preserve the source meaning and important details.",
  "Return a clear, ready-to-use result.",
  "Avoid unsupported assumptions."
].map(normalizeRequirementKey));

/**
 * Produces adaptive local prompt-enhancer output. Simple requests remain a
 * natural message. Existing structure is consolidated only when it contains
 * meaningful, non-boilerplate constraints.
 */
function enhanceDevelopmentPrompt(source: string): string {
  const fallbackObjective = "Describe the result you want to produce.";
  let content = source.trim();

  // Remove one or more leading scaffold labels. A previous development output
  // can contain both `Objective\nObjective ...` and `Objective: Objective ...`.
  while (/^objective\b\s*:?\s*/i.test(content)) {
    content = content.replace(/^objective\b\s*:?\s*/i, "").trimStart();
  }

  const requirementsHeading = /\brequirements\b\s*:?\s*(?=\n|[-•])/i.exec(content);
  const objective = (requirementsHeading
    ? content.slice(0, requirementsHeading.index)
    : content).trim() || fallbackObjective;
  const requirementsText = requirementsHeading
    ? content.slice(requirementsHeading.index + requirementsHeading[0].length)
    : "";

  const parsedRequirements = requirementsText
    .replace(/\brequirements\b\s*:?\s*/gi, " ")
    .split(/\s*[-•]\s+/)
    .map((requirement) => requirement.replace(/\s+/g, " ").trim())
    .filter(Boolean);
  const requirements = uniqueRequirements(parsedRequirements)
    .filter((requirement) => !developmentPromptRequirements.has(normalizeRequirementKey(requirement)));

  const polishedObjective = visiblyImprove(objective);
  if (requirements.length === 0) return polishedObjective;

  return [
    "Objective",
    polishedObjective,
    "",
    "Requirements",
    ...requirements.map((requirement) => `- ${ensureTerminalPunctuation(requirement)}`)
  ].join("\n");
}

function uniqueRequirements(requirements: string[]): string[] {
  const seen = new Set<string>();
  return requirements.filter((requirement) => {
    const key = normalizeRequirementKey(requirement);
    if (!key || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function normalizeRequirementKey(value: string): string {
  return value.toLocaleLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim();
}

function ensureTerminalPunctuation(value: string): string {
  return /[.!?]$/.test(value) ? value : `${value}.`;
}
