import { cases } from "./cases.mjs";

function deterministicBaseline(testCase) {
  if (testCase.destinationKind === "prompt" || testCase.destinationKind === "code") return "prompt_enhance";
  if (testCase.hasVisibleThread) {
    const draft = testCase.draft.trim();
    const complete = draft.length >= 20
      && /[.!?]["')\]]?$/.test(draft)
      && !/\b(and|but|because|so|to|with|for|that)[.!?]?["')\]]?$/i.test(draft);
    return draft.length >= 80 && !complete ? "continue" : "reply";
  }
  return "improve";
}

let exact = 0;
let acceptable = 0;
let highConfidence = 0;
let highConfidenceAcceptable = 0;
for (const testCase of cases) {
  const predicted = deterministicBaseline(testCase);
  if (predicted === testCase.exactSkill) exact += 1;
  if (testCase.acceptableSkills.includes(predicted)) acceptable += 1;
  const isHighConfidence = testCase.hasVisibleThread
    || testCase.destinationKind === "prompt"
    || testCase.destinationKind === "code";
  if (isHighConfidence) {
    highConfidence += 1;
    if (testCase.acceptableSkills.includes(predicted)) highConfidenceAcceptable += 1;
  }
}

const percent = (value, total) => Number(((value / total) * 100).toFixed(2));
const result = {
  datasetVersion: "phase6-synthetic-v2",
  cases: cases.length,
  applications: new Set(cases.map((item) => item.app)).size,
  deterministicExactPercent: percent(exact, cases.length),
  deterministicAcceptablePercent: percent(acceptable, cases.length),
  highConfidenceRuleCases: highConfidence,
  highConfidenceAcceptablePercent: percent(highConfidenceAcceptable, highConfidence),
  menuChoiceBaseline: "oracle only; user explicitly chooses a named action",
  recommendationEngineBaseline: "not comparable without sending the synthetic drafts to its legacy model",
  rolloutGateMet: false,
  note: "Synthetic harness validates schemas/rules. Auto rollout still requires measured classifier and shadow-cohort gates."
};

if (result.highConfidenceAcceptablePercent < 95) {
  throw new Error(`High-confidence acceptable precision regressed: ${result.highConfidenceAcceptablePercent}%`);
}
process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
