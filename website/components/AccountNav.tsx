import { cookies } from "next/headers";
import Link from "next/link";

import { fetchWebMe } from "@/lib/writerflow-api";
import { readWebAccountToken, WEB_ACCOUNT_COOKIE } from "@/lib/web-auth";

/** Server-rendered account link for the site header (ADR-0013). */
export async function AccountNav() {
  const cookieStore = await cookies();
  const token = readWebAccountToken(cookieStore.get(WEB_ACCOUNT_COOKIE)?.value);
  const snapshot = token ? await fetchWebMe(token).catch(() => null) : null;

  if (snapshot) {
    const label = snapshot.displayName?.trim() || snapshot.email?.trim() || "Account";
    return (
      <div className="flex items-center gap-4">
        <Link className="nav-link hidden sm:inline" href="/account">
          {label}
        </Link>
        <Link className="nav-link text-black/60" href="/auth/sign-out">
          Sign out
        </Link>
      </div>
    );
  }

  return (
    <Link className="nav-link" href="/account">
      Account
    </Link>
  );
}
