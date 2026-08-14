/**
 * Removes accidental JSON transport quotes from a streamed Grammar result
 * without buffering the whole response. The final character is held until
 * completion so a model-added closing quote is never sent to the client.
 */
export class GrammarOutputNormalizer {
  private readonly preserveLeadingQuote: boolean;
  private readonly preserveTrailingQuote: boolean;
  private started = false;
  private pending = "";

  constructor(source: string) {
    this.preserveLeadingQuote = source.startsWith('"');
    this.preserveTrailingQuote = source.endsWith('"');
  }

  push(delta: string): string {
    if (!delta) return "";
    let visible = delta;
    if (!this.started) {
      this.started = true;
      if (!this.preserveLeadingQuote && visible.startsWith('"')) {
        visible = visible.slice(1);
      }
    }
    this.pending += visible;
    if (this.pending.length <= 1) return "";
    const output = this.pending.slice(0, -1);
    this.pending = this.pending.slice(-1);
    return output;
  }

  finish(): string {
    const output = !this.preserveTrailingQuote && this.pending === '"' ? "" : this.pending;
    this.pending = "";
    return output;
  }
}
