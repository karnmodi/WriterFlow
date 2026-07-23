"use client";

import { useEffect, useState } from "react";

import { CheckIcon } from "@/components/Icons";
import { rewriteDemoTypingDuration } from "@/lib/rewrite-demo";

type DemoApp = "Cursor" | "Microsoft Teams";

const cursorRough =
  "i need build a dashboard for our support team. its nextjs and maybe use charts, data comes from api but not ready so mock it. need tickets by status and agent workload and maybe alerts when SLA close. dark mode also. should feel fast, mobile too. dont know best layout. use shadcn probly and make filters work and loading/error states, also dont change our auth stuff";

const cursorPolished = `Build a responsive support-operations dashboard in our existing Next.js application.

Context
• The dashboard is for support leads monitoring ticket health and team workload.
• The production API is not ready, so create typed mock data behind a replaceable data-service interface.
• Preserve the existing authentication and routing behavior.

Requirements
1. Show ticket totals grouped by status, priority, and SLA risk.
2. Visualise ticket volume trends and workload by agent.
3. Highlight tickets approaching an SLA breach with clear, accessible alerts.
4. Add working filters for date range, status, priority, and assigned agent.
5. Include useful loading, empty, and recoverable error states.
6. Support light and dark themes and responsive desktop/mobile layouts.

Implementation
Use the project’s existing shadcn/ui components and design tokens. Keep charts accessible with labels and non-colour indicators. Structure the code into reusable dashboard, chart, filter, and data-service modules.`;

const teamsRough =
  "hey team quick update on the client portal release, think we need move it to friday. security review found a couple permission issues and qa still checking the billing flow. nothing major but thursday feels risky. can everyone update their tickets today and tell me if friday 2pm works, also maya can you send the revised test report before tomorrow morning thanks";
const teamsPolished =
  "Hello team,\n\nI recommend moving the client portal launch to Friday at 2:00 p.m. Security is resolving two permission issues, and QA is completing its billing-flow checks.\n\nPlease update your tickets today and confirm whether the new launch time works. Maya, please share the revised test report by tomorrow morning.\n\nThank you.";

const stageCopy = [
  ["Write naturally", "Start with the thought as it comes. WriterFlow notices active typing without reading secure fields."],
  ["Use your shortcut", "The selected global shortcut opens WriterFlow without moving focus away from the input."],
  ["Confirm the direction", "Your chosen mode and preferences become active beside the text you are editing."],
  ["Build the rewrite", "WriterFlow organises the context, fills clarity gaps, and preserves the original intent."],
  ["Review before replacing", "The original remains untouched while the complete improved version is shown."],
  ["Continue in place", "After approval, the polished version replaces the rough input in the same application."],
];

const stageDurations = [3600, 1500, 1700, 1800, 3000, 3600];

export function RewriteStudio() {
  const [demoApp, setDemoApp] = useState<DemoApp>("Cursor");
  const [stage, setStage] = useState(0);
  const [typedLength, setTypedLength] = useState(0);

  const rough = demoApp === "Cursor" ? cursorRough : teamsRough;
  const polished = demoApp === "Cursor" ? cursorPolished : teamsPolished;
  const shortcut = "⌃⌥ Space";

  useEffect(() => {
    if (stage === 0) {
      const charactersPerTick = demoApp === "Cursor" ? 5 : 2;
      const stageDuration = rewriteDemoTypingDuration(rough.length, charactersPerTick);
      const typing = window.setInterval(() => {
        setTypedLength((current) => Math.min(current + charactersPerTick, rough.length));
      }, 42);
      const next = window.setTimeout(() => {
        setTypedLength(rough.length);
        setStage(1);
      }, stageDuration);
      return () => {
        window.clearInterval(typing);
        window.clearTimeout(next);
      };
    }

    const next = window.setTimeout(() => {
      if (stage === 5) {
        setTypedLength(0);
        setStage(0);
      } else {
        setStage((current) => current + 1);
      }
    }, stageDurations[stage]);
    return () => window.clearTimeout(next);
  }, [demoApp, rough.length, stage]);

  function reset(nextApp = demoApp) {
    setDemoApp(nextApp);
    setStage(0);
    setTypedLength(0);
  }

  function jumpToStage(nextStage: number) {
    setTypedLength(nextStage === 0 ? 0 : rough.length);
    setStage(nextStage);
  }

  return (
    <div className="workflow-demo" aria-label="Automatic WriterFlow product workflow">
      <div className="workflow-progress" aria-label={`Current step ${stage + 1}`}>
        {stageCopy.map(([title], index) => (
          <button
            aria-current={index === stage ? "step" : undefined}
            aria-label={`Show ${["Write", "Activate", "Options", "Process", "Preview", "Replace"][index]} stage`}
            className={index <= stage ? "is-complete" : ""}
            key={title}
            onClick={() => jumpToStage(index)}
            type="button"
          >
            <span>{index < stage ? <CheckIcon className="size-3.5" /> : index + 1}</span>
            <small>{["Write", "Activate", "Options", "Process", "Preview", "Replace"][index]}</small>
          </button>
        ))}
      </div>

      <div className="workflow-layout">
        <aside className="workflow-guide">
          <span className="guide-kicker">{demoApp} workflow</span>
          <div className="guide-stage" key={stage}>
            <span className="guide-number">0{stage + 1}</span>
            <h3>{stageCopy[stage][0]}</h3>
            <p>{stageCopy[stage][1]}</p>
          </div>
          <div className="guide-controls">
            <label className="sidebar-app-select">
              <span>Example app</span>
              <select onChange={(event) => reset(event.target.value as DemoApp)} value={demoApp}>
                <option>Cursor</option>
                <option>Microsoft Teams</option>
              </select>
            </label>
            <div className={`shortcut-callout ${stage === 1 ? "is-active" : ""}`}>
              <span>Selected activation shortcut</span>
              <div>{shortcut.split(" ").map((key) => <kbd key={key}>{key}</kbd>)}</div>
            </div>
          </div>
          <p className="workflow-auto-note">Runs automatically · Select any stage above to replay it</p>
        </aside>

        {demoApp === "Cursor" ? (
          <CursorWindow
            polished={polished}
            rough={rough}
            selectedAction="Prompt Builder"
            stage={stage}
            typedLength={typedLength}
          />
        ) : (
          <TeamsWindow
            polished={polished}
            rough={rough}
            selectedAction="Formal"
            stage={stage}
            typedLength={typedLength}
          />
        )}
      </div>
    </div>
  );
}

type WindowProps = {
  polished: string;
  rough: string;
  selectedAction: "Formal" | "Prompt Builder";
  stage: number;
  typedLength: number;
};

function WriterFlowPanel({ polished, selectedAction, stage }: WindowProps) {
  return (
    <>
      <div className={`mac-action-popover ${stage === 2 ? "is-visible" : ""}`}>
        {["Elaborate", "Formal", "Casual", "Fix Grammar", "Reply", "Prompt Builder"].map((action, index) => (
          <div className={action === selectedAction ? "selected" : ""} key={action}>
            <kbd>{index + 1}</kbd>
            <span>{action}</span>
            {action === selectedAction ? <small>Selected</small> : null}
          </div>
        ))}
        <hr />
        <div><kbd>7</kbd><span>Custom…</span></div>
      </div>

      <div className={`mac-preview-card ${stage >= 3 && stage <= 4 ? "is-visible" : ""}`}>
        <header>
          <div>
            <strong>{selectedAction}</strong>
            <span>{stage === 3 ? "Understanding your brief…" : "Review before replacing"}</span>
          </div>
          {stage === 3 ? <i className="mac-spinner" /> : null}
          <button aria-label="Close preview" type="button">×</button>
        </header>
        <section>
          {selectedAction === "Prompt Builder" ? <small>PROMPT</small> : null}
          <div className={stage === 3 ? "is-streaming" : ""}>
            {stage === 3 ? "Thinking…" : polished}
          </div>
        </section>
        <footer>
          <button aria-label="Retry" type="button">↻</button>
          <span />
          <button aria-label="Copy" type="button">▣</button>
          <button className="prominent" aria-label="Replace" type="button">↵</button>
        </footer>
      </div>
    </>
  );
}

function WaveIcon({ busy = false }: { busy?: boolean }) {
  return (
    <span className={`native-wave-icon ${busy ? "is-busy" : ""}`} aria-hidden="true">
      <svg viewBox="0 0 28 28">
        {[9, 14, 19].map((y, index) => (
          <g key={y}>
            <path className="wave-border" d={`M3 ${y} Q9 ${y - 1.8 + index * 0.35} 14 ${y} T25 ${y}`} />
            <path className="wave-fill" d={`M3 ${y} Q9 ${y - 1.8 + index * 0.35} 14 ${y} T25 ${y}`} />
          </g>
        ))}
      </svg>
      <i className="native-busy-spinner" />
    </span>
  );
}

function ActiveMark({ stage }: { stage: number }) {
  return (
    <div className={`active-wave-mark ${stage >= 0 ? "is-visible" : ""}`} aria-label="WriterFlow is active">
      <WaveIcon busy={stage === 3} />
    </div>
  );
}

function ReplacementResult({ app, failed = false, stage }: { app: string; failed?: boolean; stage: number }) {
  return (
    <div
      aria-live="polite"
      className={`mac-result-card ${failed ? "is-error" : "is-success"} ${stage === 5 ? "is-visible" : ""}`}
    >
      <span>{failed ? "!" : <CheckIcon className="size-4" />}</span>
      <div>
        <strong>{failed ? "Couldn’t replace text" : "Text replaced"}</strong>
        <small>{failed ? "Your original text is unchanged." : `Updated directly in ${app}.`}</small>
      </div>
    </div>
  );
}

function CursorWindow(props: WindowProps) {
  const { polished, rough, stage, typedLength } = props;
  return (
    <div className="teams-window cursor-window">
      <div className="cursor-titlebar">
        <span className="cursor-traffic"><i /><i /><i /></span>
        <span>release_plan.md — WriterFlow</span>
        <small>Agents Window ↗</small>
      </div>
      <div className="cursor-body">
        <nav className="cursor-rail"><span>▱</span><span>⌕</span><span>⑂</span><span>◇</span><span className="active">✦</span></nav>
        <aside className="cursor-files">
          <strong>EXPLORER</strong>
          <span>⌄ WRITERFLOW</span>
          <span>&nbsp;&nbsp;› build</span>
          <span>&nbsp;&nbsp;⌄ Docs</span>
          <span>&nbsp;&nbsp;&nbsp;&nbsp;release-plan.md</span>
          <span>&nbsp;&nbsp;› infra</span>
          <span>&nbsp;&nbsp;› prompts</span>
          <span>&nbsp;&nbsp;› services</span>
          <span>&nbsp;&nbsp;⌄ website</span>
          <span>&nbsp;&nbsp;&nbsp;&nbsp;page.tsx</span>
          <span>&nbsp;&nbsp;&nbsp;&nbsp;globals.css</span>
        </aside>
        <main className="cursor-workspace">
          <div className="editor-tabs">
            <span>page.tsx <i>×</i></span>
            <span className="active">release-plan.md <i>×</i></span>
          </div>
          <div className="cursor-document" aria-hidden="true">
            <small>Docs › release-plan.md</small>
            <h3>Private beta release plan</h3>
            <h4>Connection path</h4>
            <div className="document-flow"><span>Mac app</span><i>→</i><span>API edge</span><i>→</i><span>WriterFlow API</span></div>
            <ul>
              <li>Preserve the production endpoint and existing sign-in flow.</li>
              <li>Verify streaming, sanitised failures, and responsive states.</li>
              <li>Keep reusable credentials out of public client artifacts.</li>
            </ul>
          </div>
          <div className="cursor-terminal" aria-hidden="true">
            <header><span>Problems</span><span>Output</span><span>Debug Console</span><b>Terminal</b><i>＋</i></header>
            <pre>› npm run check{"\n"}✓ lint passed{"\n"}✓ typecheck passed{"\n"}› writerflow dev --watch{"\n"}ready on localhost:3000{"\n"}writerflow % <em /></pre>
          </div>
        </main>
        <aside className="cursor-agent-pane">
          <header><strong>New Agent</strong><span>Claude</span><i>＋</i></header>
          <div className={`cursor-composer ${stage === 5 ? "is-replaced" : ""}`}>
            <div className="cursor-input-label"><span>Prompt</span><small>{stage === 5 ? "Ready to send" : "Drafting"}</small></div>
            <pre aria-live="polite">
              {stage === 5 ? polished : rough.slice(0, typedLength)}
              {stage >= 0 && stage < 5 ? <i className="typing-caret" /> : null}
            </pre>
            <footer><span>@ Add context</span><button aria-label="Send prompt" type="button">↑</button></footer>
          </div>
          <div className="cursor-agent-note">WriterFlow turns the rough idea into a structured build brief without changing its intent.</div>
        </aside>
      </div>
      <ActiveMark stage={stage} />
      <WriterFlowPanel {...props} />
      <ReplacementResult app="Cursor" stage={stage} />
    </div>
  );
}

function TeamsWindow(props: WindowProps) {
  const { polished, rough, stage, typedLength } = props;
  return (
    <div className="teams-window">
      <div className="teams-titlebar">
        <div className="teams-app-mark">T</div><span>Microsoft Teams</span>
        <div className="teams-search">Search</div><div className="teams-avatar">KM</div>
      </div>
      <div className="teams-body">
        <nav className="teams-rail"><span>●</span><span>▢</span><span className="active">◫</span><span>◇</span></nav>
        <aside className="teams-sidebar">
          <strong>Chat</strong><div className="teams-filter">Search chats</div><small>PINNED</small>
          <div className="teams-chat active"><i>PT</i><span><b>Product team</b><em>Alex: Looks good</em></span></div>
          <div className="teams-chat"><i>MS</i><span><b>Maya Singh</b><em>You: Thanks!</em></span></div>
        </aside>
        <main className="teams-conversation">
          <header className="conversation-header">
            <div className="conversation-avatar">PT</div><div><strong>Product team</strong><span>8 members</span></div>
          </header>
          <div className="message-stream">
            <div className="teams-message"><span className="person-avatar maya">MS</span><div><b>Maya Singh</b><small>10:26</small><p>The regression suite is complete, but QA is still validating the billing workflow and documenting two edge cases.</p></div></div>
            <div className="teams-message"><span className="person-avatar alex">AL</span><div><b>Alex Morgan</b><small>10:31</small><p>Security also flagged two permission issues during the final review. The fixes are in progress and should be ready for verification this afternoon.</p></div></div>
            <div className="teams-message"><span className="person-avatar maya">MS</span><div><b>Maya Singh</b><small>10:34</small><p>Would you like us to keep Thursday’s release window, or move it to Friday so both checks can be completed?</p></div></div>
          </div>
          <div className={`teams-composer ${stage === 5 ? "is-replaced" : ""}`}>
            <div className="composer-tools"><span>A</span><span>⌕</span><span>☺</span><span>GIF</span></div>
            <p aria-live="polite">{stage === 5 ? polished : rough.slice(0, typedLength)}{stage >= 0 && stage < 5 ? <i className="typing-caret" /> : null}</p>
            <div className="composer-footer"><span>Format &nbsp; Attach &nbsp; Loop</span><button aria-label="Send message" type="button">➤</button></div>
          </div>
        </main>
      </div>
      <ActiveMark stage={stage} />
      <WriterFlowPanel {...props} />
      <ReplacementResult app="Microsoft Teams" stage={stage} />
    </div>
  );
}
