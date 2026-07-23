type BrandMarkProps = {
  className?: string;
  inverse?: boolean;
  size?: number;
};

export function BrandMark({ className = "", inverse = false, size = 36 }: BrandMarkProps) {
  return (
    <svg
      aria-hidden="true"
      className={className}
      height={size}
      viewBox="0 0 64 64"
      width={size}
    >
      <rect fill="currentColor" height="64" rx="18" width="64" />
      <g
        fill="none"
        stroke={inverse ? "#11131a" : "#f4f1e9"}
        strokeLinecap="round"
        strokeWidth="4.4"
      >
        <path d="M12 22.2c7.4-2.8 13.9 3.1 21.1 1.1 6.3-1.7 11.3-4.7 18.9-1.4" />
        <path d="M12 32.3c7.2-2.4 13.4 3.5 20.7 1.2 6.6-2.1 12-4.5 19.3-1.1" />
        <path d="M12 42.3c7.7-2.2 13.1 3.2 20.7 1.2 6.9-1.8 12.3-4.3 19.3-.9" />
      </g>
    </svg>
  );
}

export function Wordmark({ inverse = false }: { inverse?: boolean }) {
  return (
    <span className="inline-flex items-center gap-2.5">
      <BrandMark
        className={inverse ? "text-paper" : "text-ink"}
        inverse={inverse}
        size={34}
      />
      <span
        className={`text-[1.05rem] font-semibold tracking-[-0.02em] ${
          inverse ? "text-paper" : "text-ink"
        }`}
      >
        WriterFlow
      </span>
    </span>
  );
}
