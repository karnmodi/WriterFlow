export function rewriteDemoTypingDuration(
  textLength: number,
  charactersPerTick: number,
  tickMilliseconds = 42,
  readingPauseMilliseconds = 1200,
): number {
  return Math.ceil(textLength / charactersPerTick) * tickMilliseconds + readingPauseMilliseconds;
}
