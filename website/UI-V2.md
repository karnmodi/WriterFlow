# WriterFlow website UI v2.0.0

The website uses one user-focused visual system across Privacy, Install, Membership,
Account, and the product workflow. Colour supports meaning, but labels, icons, and copy
must always communicate the same state without relying on colour.

## Surface variants

| Variant | Tokens | Use | Avoid |
| --- | --- | --- | --- |
| Paper | `--color-paper`, `surface-paper` | Primary reading, instructions, plan details, and long-form content | Critical warnings or primary actions |
| Soft / lavender | `--lavender`, `surface-lavender` | Preparation, guidance, explanatory callouts, and next steps | Errors, destructive actions, or security boundaries |
| Prism | `surface-cobalt` | Light lavender, mint, and peach blend for selected/current states and membership context | Warnings, errors, or dense decoration |
| Ink | `--color-ink`, `surface-ink` | Privacy boundaries, security disclosures, platform limitations, and high-importance status | Routine help text |
| Amber | `--color-amber-soft` | Installation cautions and recoverable attention states | Success or primary navigation |
| Success | `--color-success` | Confirmed completion with an accompanying check icon and text | Decorative accents or the only success indicator |

## Placement rules

- Heroes may use Ink, Lavender, or Prism according to the page’s user task. They must
  contain one plain-language purpose statement and no more than one primary route onward.
- Paper is the default content surface. Use it for any paragraph longer than three lines.
- Lavender sits between a task and its next action: setup preparation, explanations, or
  “what happens next” content.
- Prism marks active or current state without creating a saturated reading surface. Use
  Ink text and keep the lavender, mint, and peach blend subtle.
- Ink is reserved for trust-critical boundaries and limitations. Primary text uses Paper;
  secondary text must remain at least 70% white.
- Amber callouts require a descriptive icon and explanatory text.
- Success and failure feedback use the same card structure, with icon and text changing
  alongside colour.

## Accessibility

- Normal text must meet WCAG AA contrast (4.5:1); large text and large interface glyphs
  must meet at least 3:1.
- Selected page text uses white on `--color-blue-deep` sitewide.
- Colour is never the sole indicator of plan, warning, success, or failure state.
- Interactive targets have a minimum height of 44px and visible `:focus-visible` outlines.
- Layouts must not scroll horizontally at 375px, 768px, 1024px, or 1440px.
- Motion must respect the existing `prefers-reduced-motion` rules.
