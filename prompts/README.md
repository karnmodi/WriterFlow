# Server prompt resources

WriterFlow's cloud prompt policy is versioned and compiled only by `services/api`.
Released Mac clients continue to send the existing inference envelope; they never load
these resources and never choose a provider prompt path.

## Startup and compilation

`PromptCompiler.load()` parses `manifest.yaml`, validates its closed mappings, resolves
only `.md` files beneath this directory, strips authoring comments, rejects missing or
empty assets, and caches every declared asset before the API accepts traffic. Request
compilation performs no filesystem reads.

The compiler creates a typed `PromptPlan` before rendering. It deterministically selects
the canonical source, conversation budget, tone precedence, Reply destination class,
Prompt Builder phase/mode, logical route, output mode, and prompt version. Unknown site
labels select the reviewed default and can never become resource paths.

## Trust boundaries

Reviewed system policy, explicit user instructions, optional personalization, source,
and conversation remain distinct sections. All request-controlled text is JSON-string
encoded inside named untrusted-data tags; delimiter characters are escaped so content
cannot close a tag or select policy. Prompt and user content must never be logged.

## Versioning and evaluation

Every behavior-changing release updates the manifest version and every affected intent
`promptVersion` atomically. `prompts/evals/cases.jsonl` is the 160-case synthetic quality
slice. Local compiler, parser, injection, privacy, and corpus gates run through
`npm run check`. Authenticated APIM evaluation uses:

```bash
node scripts/eval/prompt-quality-live.mjs \
  --label candidate \
  --output build/prompt-evals/candidate.json \
  --api-base https://wfprod-apim-dev.azure-api.net/v2-prompt-candidate
```

The runner paces requests, retries provider-capacity failures, resumes completed cases,
writes evidence incrementally with mode `0600`, and revokes its temporary device. Use
`scripts/eval/analyze-prompt-quality.mjs` only after complete baseline and candidate
runs; its deterministic checks do not replace the blinded human review.

For a zero-traffic Container Apps revision, `scripts/cloud/apim-prompt-candidate.sh`
creates a temporary authenticated APIM path with the production JWT, origin-secret, and
unbuffered SSE policies. Remove that path after evaluation.
