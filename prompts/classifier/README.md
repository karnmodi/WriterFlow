# Phase 6 classifier evaluation

`cases.mjs` expands reviewed app/scenario/variant axes into 330 deterministic synthetic
cases. Each case labels exact and acceptable skills, output mode, context requirement,
direct/composed eligibility, and destructive risk without using user history.

Run `npm run eval:classifier`. The harness gates high-confidence deterministic rules at
95% acceptable precision and prints the baseline. It deliberately keeps
`rolloutGateMet=false`: classifier accuracy and live shadow-cohort latency/acceptance
must be measured separately before enabling the auto cohort.

The checked-in `baseline.json` is the current deterministic-rule baseline. Update it
only after reviewing a changed dataset and the harness output together.
