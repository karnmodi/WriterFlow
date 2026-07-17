import type { Metadata, Viewport } from "next";

import { SiteFooter } from "@/components/SiteFooter";
import { SiteHeader } from "@/components/SiteHeader";

import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "WriterFlow — Write better, right where you type",
    template: "%s — WriterFlow",
  },
  description:
    "WriterFlow is a native macOS assistant for clearer drafts, grammar fixes, and contextual replies without switching apps.",
  applicationName: "WriterFlow",
  manifest: "/site.webmanifest",
  keywords: [
    "macOS writing assistant",
    "writing app",
    "grammar",
    "contextual replies",
    "WriterFlow",
  ],
  openGraph: {
    title: "WriterFlow — Write better, right where you type",
    description:
      "A native macOS assistant for rewriting drafts, fixing grammar, and creating contextual replies without switching apps.",
    siteName: "WriterFlow",
    type: "website",
  },
  twitter: {
    card: "summary",
    title: "WriterFlow — Write better, right where you type",
    description:
      "A native macOS assistant for clearer drafts and contextual replies.",
  },
};

export const viewport: Viewport = {
  colorScheme: "light",
  themeColor: "#f4f1e9",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>
        <a className="skip-link" href="#main-content">
          Skip to content
        </a>
        <SiteHeader />
        {children}
        <SiteFooter />
      </body>
    </html>
  );
}
