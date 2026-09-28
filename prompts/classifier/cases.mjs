const applications = [
  ["gmail", "email"],
  ["outlook", "email"],
  ["slack", "work_message"],
  ["whatsapp", "personal_message"],
  ["notes", "other"],
  ["linkedin", "work_message"],
  ["chatgpt", "llm_chat"],
  ["claude", "llm_chat"],
  ["cursor", "code"],
  ["notion", "other"],
  ["generic", "other"]
];

const scenarios = [
  { id: "empty_thread", exact: "reply", acceptable: ["reply"], thread: true, draft: "", context: "required", risk: "replace" },
  { id: "short_thread", exact: "reply", acceptable: ["reply", "continue"], thread: true, draft: "Sounds good", context: "required", risk: "replace" },
  { id: "drafted_thread", exact: "reply", acceptable: ["reply", "improve"], thread: true, draft: "Thanks for the update. I reviewed the plan and the timeline works well for our whole team next week.", context: "required", risk: "replace" },
  { id: "unfinished_thread", exact: "continue", acceptable: ["continue", "reply"], thread: true, draft: "Thanks for the update. I reviewed the proposal and would like to confirm the final schedule because", context: "required", risk: "replace" },
  { id: "rough_prompt", exact: "prompt_enhance", acceptable: ["prompt_enhance", "improve"], thread: false, draft: "make launch plan include risks owners dates", context: "optional", risk: "replace" },
  { id: "grammar", exact: "correct", acceptable: ["correct", "improve"], thread: false, draft: "Their going to send it tommorow.", context: "none", risk: "replace" },
  { id: "shorten", exact: "shorten", acceptable: ["shorten", "improve"], thread: false, draft: "Make this shorter: the project remains on track and is proceeding according to the current plan.", context: "none", risk: "replace" },
  { id: "expand", exact: "expand", acceptable: ["expand", "improve"], thread: false, draft: "Expand this update with useful detail.", context: "optional", risk: "replace" },
  { id: "tone", exact: "tone_adapt", acceptable: ["tone_adapt", "improve"], thread: false, draft: "Make this warmer but still professional.", context: "optional", risk: "replace" },
  { id: "neutral", exact: "improve", acceptable: ["improve", "correct"], thread: false, draft: "Here is the latest project update for the team.", context: "optional", risk: "replace" },
  { id: "constraint_heavy", exact: "expand", acceptable: ["expand", "improve"], thread: false, draft: "Must include owner, date, risk, and next step. Keep every fact and do not invent details. ".repeat(12), context: "optional", risk: "replace", composition: true }
];

export const cases = applications.flatMap(([app, appCategory]) =>
  scenarios.flatMap((scenario) => [0, 1, 2].map((variant) => {
    const promptDestination = appCategory === "llm_chat" || appCategory === "code";
    const exact = promptDestination ? "prompt_enhance" : scenario.exact;
    const acceptable = promptDestination
      ? ["prompt_enhance", "improve"]
      : scenario.acceptable;
    return {
      id: `${app}.${scenario.id}.${variant + 1}`,
      app,
      appCategory,
      destinationKind: promptDestination ? (appCategory === "code" ? "code" : "prompt") : scenario.thread ? "reply" : "document",
      composeSurface: scenario.thread ? "thread_reply" : "editor",
      draft: variant === 0 ? scenario.draft : variant === 1 ? `${scenario.draft} ` : scenario.draft.replaceAll("project", "work"),
      hasVisibleThread: scenario.thread,
      exactSkill: exact,
      acceptableSkills: acceptable,
      outputMode: "replace",
      requiredContext: scenario.context,
      executionEligibility: scenario.composition ? ["direct", "composed"] : ["direct"],
      destructiveRisk: scenario.risk
    };
  }))
);

if (cases.length < 300) throw new Error(`Expected at least 300 cases, found ${cases.length}`);
