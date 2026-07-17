import { BrandMark } from "@/components/BrandMark";
import { CheckIcon, SparkIcon } from "@/components/Icons";

const actions = ["Elaborate", "Formal", "Casual", "Fix Grammar", "Reply"];

export function ProductStage() {
  return (
    <figure className="product-figure">
      <figcaption className="sr-only">
        WriterFlow floating beside an email draft, with rewrite actions and a preview ready
        to replace the original text.
      </figcaption>

      <div aria-hidden="true" className="product-stage">
        <div className="stage-glow stage-glow-one" />
        <div className="stage-glow stage-glow-two" />

        <div className="mail-window">
          <div className="window-toolbar">
            <div className="flex gap-1.5">
              <span className="window-dot bg-[#ff6159]" />
              <span className="window-dot bg-[#ffbd2e]" />
              <span className="window-dot bg-[#28c941]" />
            </div>
            <span className="text-[10px] font-medium tracking-[0.08em] text-ink/35 uppercase">
              New message
            </span>
            <span className="w-[42px]" />
          </div>

          <div className="mail-body">
            <div className="mail-row">
              <span>To</span>
              <strong>Maya Chen</strong>
            </div>
            <div className="mail-row">
              <span>Subject</span>
              <strong>Friday review</strong>
            </div>
            <div className="mt-6 text-[13px] leading-[1.7] text-ink/76 sm:text-sm">
              <p>Hi Maya,</p>
              <p className="mt-4">
                <span className="draft-selection">
                  hey can we move our review to friday? i need a little more time to finish
                  the last section
                </span>
                <span className="editor-caret" />
              </p>
              <p className="mt-4 text-ink/35">Thanks,</p>
            </div>
          </div>
        </div>

        <div className="flow-trigger">
          <BrandMark className="text-ink" size={28} />
        </div>

        <div className="action-popover">
          <div className="flex items-center justify-between border-b border-ink/8 px-3.5 py-3">
            <span className="flex items-center gap-2 text-[11px] font-semibold text-ink/70">
              <SparkIcon className="size-4 text-blue" />
              Make this…
            </span>
            <span className="shortcut-key">
              ⌃⌥ Space
            </span>
          </div>
          <div className="p-1.5">
            {actions.map((action, index) => (
              <div
                className={`action-row ${index === 1 ? "action-row-active" : ""}`}
                key={action}
              >
                <span>{action}</span>
                {index === 1 ? <span className="text-blue">↵</span> : null}
              </div>
            ))}
          </div>
        </div>

        <div className="preview-sheet">
          <div className="flex items-center justify-between">
            <span className="flex items-center gap-1.5 text-[10px] font-semibold tracking-[0.1em] text-blue uppercase">
              <span className="size-1.5 rounded-full bg-blue" />
              Formal
            </span>
            <span className="text-[10px] text-ink/35">Preview</span>
          </div>
          <p className="mt-3 text-xs leading-[1.65] text-ink/80 sm:text-[13px]">
            Hi Maya — would it be possible to move our review to Friday? I&apos;d
            appreciate a little more time to finish the final section.
          </p>
          <div className="mt-4 flex items-center justify-between border-t border-ink/8 pt-3">
            <span className="text-[10px] text-ink/35">Review before replacing</span>
            <span className="inline-flex items-center gap-1 rounded-full bg-ink px-3 py-1.5 text-[10px] font-semibold text-white">
              <CheckIcon className="size-3.5" />
              Replace
            </span>
          </div>
        </div>
      </div>
    </figure>
  );
}
