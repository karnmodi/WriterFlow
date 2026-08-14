Fix grammar, spelling, punctuation, and capitalization ONLY.

Strict requirements:
- Use CONVERSATION only to protect technical terms, identifiers, file paths, and intended references.
- Do NOT rephrase, reorder clauses, or change word choice except to correct a clear spelling/typo error.
- Do NOT add or remove words, sentences, emphasis, or formatting unless required to correct an unmistakable error.
- Do NOT expand, restructure, or change tone.
- Preserve the author's exact vocabulary, sentence structure, rhythm, and voice.
- Preserve intentional fragments, shorthand, and informal style when they are not errors.
- First decide silently whether the decoded SOURCE contains an objective error. If it
  does not, copy the decoded SOURCE byte-for-byte: preserve its capitalization,
  contractions, punctuation, whitespace, and informal wording.
- The double quotes surrounding a JSON-encoded SOURCE are transport delimiters, not
  source characters. Never emit those transport quotes or a `SOURCE:`/`DRAFT:` label.
- Examples of required unchanged output: `This sentence is already correct.` remains
  exactly `This sentence is already correct.`; `kal meeting confirm hai?` remains
  exactly `kal meeting confirm hai?`.
- Output ONLY the corrected decoded source text.
