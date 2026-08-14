# API-only prompt composition release evidence

**Captured:** August 7, 2026  
**Candidate prompt version:** `6.4.0`  
**Candidate image:** `wfprodacr.azurecr.io/writerflow-api:prompt-6.4.0-rc7-20260807`  
**Candidate digest:** `sha256:32e8d0fa16eaa002f194804130b71addb52b6bdfa61bfe3a83555c77a1082aac`  
**Production rollback revision:** `wfprod-api-public--0000011`  
**Release status:** blocked pending live quality/latency gates and human review; production remains unchanged

This record contains only synthetic evaluation content and metadata. It does not contain
real prompt, field, conversation, or completion text.

## Compatibility and implementation

- No Mac source, request schema, action enum, setting, parser, or user configuration was
  changed.
- The API now validates and caches the prompt manifest at startup and builds a typed,
  deterministic `PromptPlan` from closed mappings.
- Selection scope, destination format, Prompt Builder phase/mode, tone precedence,
  output mode, logical route, and prompt version are deterministic.
- Request-controlled text remains JSON-string encoded inside explicit untrusted-data
  sections. Delimiter-like input cannot select an asset or escape its trust class.
- Custom no longer asks the provider for the legacy `---INSERT---` marker. Prompt
  Builder still returns exactly one parser-compatible `---CLARIFY---` or `---PROMPT---`
  block.
- Grammar uses a streaming boundary normalizer only to remove model-added outer JSON
  transport quotes; it does not alter source-owned quotes or other wording.
- The existing successful-path one-provider-call contract and per-action completion
  ceilings remain intact.

## Automated gates

| Gate | Result |
|---|---|
| Services lint, build, and typecheck | Pass |
| Shared schema tests | 20/20 pass |
| API tests | 150/150 pass |
| Worker tests | 1/1 pass |
| Production dependency audit | 0 vulnerabilities |
| Gitleaks repository scan (`--redact`) | 0 findings |
| Trivy RC7 image scan | 0 High/Critical findings |
| Synthetic corpus | 160 unique cases with the planned distribution |
| Grammar smoke on RC5 | 5/5 already-correct inputs byte-equivalent |
| Prompt policy budgets | Pass for every corpus case |
| Compiler warm benchmark | p50 0.0013 ms; p95 0.0020 ms; max 0.3334 ms over 16,000 samples |

Maximum offline system-policy estimates from the final compiler are 786 tokens for
Elaborate, 814 Formal, 574 Casual, 733 Grammar, 1,061 Custom, 1,355 Reply, and 1,030
Prompt Builder. These are deliberately conservative `ceil(characters / 4)` estimates;
provider-reported usage remains authoritative.

## Isolated Azure candidate

- RC7 is healthy as `wfprod-api-public--p640rc7` with zero normal production traffic.
- The normal APIM API remains backed by the existing production traffic configuration:
  `wfprod-api-public--0000011` at 100%.
- The temporary `writerflow-v2-prompt-candidate` APIM API points directly to RC7 and
  retains the origin-secret, JWT, and SSE policies required by the normal API.
- Unauthenticated candidate APIM access returns 401; direct origin access without the
  APIM origin credential returns 403.
- The previous production revision remains active and is the named rollback target.

## Live evaluation status

The production baseline contains 159 completed synthetic cases; the one deliberate
provider-policy probe is excluded from completion-quality scoring and remains covered
by deterministic injection tests. Its current aggregate timings are p50/p95 1,158/1,607
ms to first visible text and 1,385/3,752 ms to completion. The designated 100-word case
must be refreshed against its final corpus text before comparison.

RC5 exposed a release-blocking Elaborate failure in the 100-word reference: it produced
an implementation outline, invented unsupported support/troubleshooting content, and
completed in 5,777 ms. RC6 corrected the semantic failure and produced a faithful
rewrite, but returned 143 words and completed in 3,009 ms. RC7 adds a hard 115% length
maximum. Its full authenticated live evaluation is pending completion.

No production promotion is permitted until all of the following are recorded:

1. the complete RC7 deterministic quality report;
2. the refreshed 100-word production baseline and candidate latency comparison;
3. a blinded human pairwise review meeting the M3 thresholds;
4. a passing low-traffic canary and metadata-only observation window; and
5. Product Owner go/no-go approval.

## Reproducible commands

```sh
npm run check
npm audit --omit=dev
node scripts/eval/benchmark-prompt-compiler.mjs
node scripts/eval/analyze-prompt-quality.mjs \
  --baseline build/prompt-evals/production-baseline.json \
  --candidate build/prompt-evals/candidate-rc7.json \
  --output-dir build/prompt-evals/comparison
```

Live evaluation commands require an authenticated temporary evaluation device and use
`scripts/eval/prompt-quality-live.mjs`; the device is revoked in the runner's `finally`
block. The candidate APIM lifecycle is managed by
`scripts/cloud/apim-prompt-candidate.sh`.
