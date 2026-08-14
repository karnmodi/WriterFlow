export const PROMPT_DELIMITER = "---PROMPT---";
export const CLARIFY_DELIMITER = "---CLARIFY---";

export interface ClarifyQuestion {
  question: string;
  suggestions: string[];
}

export type PromptBuilderOutput =
  | { kind: "prompt"; prompt: string }
  | { kind: "clarify"; questions: ClarifyQuestion[] };

export class InvalidPromptBuilderOutputError extends Error {}

function markerCount(output: string, marker: string): number {
  return output.split(marker).length - 1;
}

function parseQuestions(body: string): ClarifyQuestion[] {
  const questions: ClarifyQuestion[] = [];
  let current: ClarifyQuestion | undefined;
  for (const rawLine of body.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line) continue;
    const questionMatch = /^(?:Q|Question):\s*(.+)$/i.exec(line);
    if (questionMatch?.[1]) {
      current = { question: questionMatch[1].trim(), suggestions: [] };
      questions.push(current);
      continue;
    }
    const suggestionMatch = /^(?:-|•)\s*(.+)$/.exec(line);
    if (suggestionMatch?.[1] && current) current.suggestions.push(suggestionMatch[1].trim());
  }
  return questions.filter((question) => question.question && question.suggestions.length > 0);
}

/** Strict evaluation parser for the released Mac parser's marker contract. */
export function parsePromptBuilderOutput(
  raw: string,
  expectedPhase: "analyze" | "finalize"
): PromptBuilderOutput {
  const output = raw.trim();
  const promptMarkers = markerCount(output, PROMPT_DELIMITER);
  const clarifyMarkers = markerCount(output, CLARIFY_DELIMITER);
  if (promptMarkers + clarifyMarkers !== 1) {
    throw new InvalidPromptBuilderOutputError("Prompt Builder output must contain exactly one marker.");
  }
  if (expectedPhase === "finalize" && clarifyMarkers > 0) {
    throw new InvalidPromptBuilderOutputError("Finalize output cannot ask clarifying questions.");
  }
  const marker = promptMarkers === 1 ? PROMPT_DELIMITER : CLARIFY_DELIMITER;
  if (!output.startsWith(marker)) {
    throw new InvalidPromptBuilderOutputError("Prompt Builder marker must be the first output content.");
  }
  const body = output.slice(marker.length).trim();
  if (!body) throw new InvalidPromptBuilderOutputError("Prompt Builder block cannot be empty.");
  if (marker === PROMPT_DELIMITER) return { kind: "prompt", prompt: body };
  const questions = parseQuestions(body);
  if (questions.length === 0) {
    throw new InvalidPromptBuilderOutputError("Clarify output must contain a question with suggestions.");
  }
  return { kind: "clarify", questions };
}
