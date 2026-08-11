#!/usr/bin/env bash
# PropertyOS — secure admin page for granting free Pro access (e.g. 90-day agent access).
# Run from project root AFTER running migration 0010_comp_access.sql.
set -e
if [ ! -f app/billing/page.tsx ]; then echo "ERROR: run from the PropertyOS project root."; exit 1; fi
mkdir -p app/admin lib

# ---------------------------------------------------------------
# Admin gate: only emails listed in ADMIN_EMAILS may pass. Anyone
# else gets a 404 (the page's existence stays hidden).
cat > lib/admin.ts << '__EOF__'
import { requireOrg } from "@/lib/auth";
import { notFound } from "next/navigation";

export async function requireAdmin() {
  // requireOrg already enforces a logged-in user with an org.
  const { supabase } = await requireOrg();
  const { data: { user } } = await supabase.auth.getUser();

  const admins = (process.env.ADMIN_EMAILS ?? "")
    .split(",").map((s) => s.trim().toLowerCase()).filter(Boolean);
  const email = (user?.email ?? "").toLowerCase();

  if (!email || !admins.includes(email)) notFound();
  return { email };
}
__EOF__

# ---------------------------------------------------------------
# Server actions — each RE-VERIFIES admin before doing anything.
cat > app/admin/actions.ts << '__EOF__'
"use server";

import { requireAdmin } from "@/lib/admin";
import { createAdminClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";

async function ownerOrgIdsForEmail(email: string): Promise<string[]> {
  const admin = createAdminClient();
  const { data: profs } = await admin.from("profiles").select("id").eq("email", email);
  const ids = (profs ?? []).map((p: any) => p.id);
  if (ids.length === 0) return [];
  const { data: mems } = await admin
    .from("memberships").select("organization_id")
    .in("user_id", ids).eq("role", "owner").is("deleted_at", null);
  return Array.from(new Set((mems ?? []).map((m: any) => m.organization_id)));
}

export async function grantComp(formData: FormData) {
  await requireAdmin();
  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  const days = Math.max(1, Number(formData.get("days") ?? 90) || 90);
  if (!email) redirect("/admin");

  const orgIds = await ownerOrgIdsForEmail(email);
  if (orgIds.length === 0) redirect("/admin?msg=noaccount&email=" + encodeURIComponent(email));

  const expires = new Date(Date.now() + days * 86400000).toISOString();
  const admin = createAdminClient();
  await admin.from("organizations")
    .update({ pro_comp: true, pro_comp_expires_at: expires })
    .in("id", orgIds);

  redirect("/admin?msg=granted&email=" + encodeURIComponent(email) + "&days=" + days);
}

export async function revokeComp(formData: FormData) {
  await requireAdmin();
  const orgId = String(formData.get("orgId") ?? "");
  if (!orgId) redirect("/admin");
  const admin = createAdminClient();
  await admin.from("organizations")
    .update({ pro_comp: false, pro_comp_expires_at: null })
    .eq("id", orgId);
  redirect("/admin?msg=revoked");
}
__EOF__

# ---------------------------------------------------------------
# The page itself.
cat > app/admin/page.tsx << '__EOF__'
import { requireAdmin } from "@/lib/admin";
import { createAdminClient } from "@/lib/supabase/server";
import SubmitButton from "@/app/_components/SubmitButton";
import { grantComp, revokeComp } from "./actions";

export default async function AdminPage({
  searchParams,
}: {
  searchParams: Promise<{ msg?: string; email?: string; days?: string }>;
}) {
  const { email: adminEmail } = await requireAdmin();
  const sp = await searchParams;

  const admin = createAdminClient();
  const { data: comped } = await admin
    .from("organizations")
    .select("id, name, pro_comp_expires_at")
    .eq("pro_comp", true)
    .order("pro_comp_expires_at", { ascending: true });

  const now = Date.now();
  const rows = (comped ?? []).map((o: any) => {
    const exp = o.pro_comp_expires_at ? new Date(o.pro_comp_expires_at) : null;
    const days = exp ? Math.ceil((exp.getTime() - now) / 86400000) : null;
    return { id: o.id as string, name: o.name as string, exp, days };
  });

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100">
      <div className="border-b border-neutral-800 px-6 py-4">
        <div className="max-w-3xl mx-auto flex items-center justify-between">
          <span className="font-semibold">PropertyOS · Admin</span>
          <span className="text-xs text-neutral-500">{adminEmail}</span>
        </div>
      </div>

      <main className="max-w-3xl mx-auto px-6 py-8 space-y-8">
        <div>
          <h1 className="text-xl font-semibold">Grant free Pro access</h1>
          <p className="text-sm text-neutral-400 mt-1">Enter the agent&apos;s PropertyOS login email. They must have signed up first.</p>
        </div>

        {sp.msg === "granted" && <p className="text-sm text-green-400 bg-green-950/30 border border-green-900 rounded-md p-3">Granted {sp.days ?? 90} days of Pro to {sp.email}.</p>}
        {sp.msg === "noaccount" && <p className="text-sm text-amber-300 bg-amber-950/30 border border-amber-900 rounded-md p-3">No PropertyOS account owns {sp.email}. Have them sign up first, then grant.</p>}
        {sp.msg === "revoked" && <p className="text-sm text-neutral-300 bg-neutral-900 border border-neutral-800 rounded-md p-3">Access ended.</p>}

        <form action={grantComp} className="rounded-lg border border-neutral-800 bg-neutral-900 p-5 space-y-4">
          <div className="flex flex-col gap-1">
            <label className="text-xs text-neutral-400">Agent email</label>
            <input name="email" type="email" required placeholder="agent@example.com"
              className="h-11 rounded-md bg-neutral-950 border border-neutral-700 px-3 text-sm text-neutral-100" />
          </div>
          <div className="flex items-end gap-3">
            <div className="flex flex-col gap-1">
              <label className="text-xs text-neutral-400">Days</label>
              <input name="days" type="number" defaultValue={90} min={1}
                className="h-11 w-24 rounded-md bg-neutral-950 border border-neutral-700 px-3 text-sm text-neutral-100" />
            </div>
            <SubmitButton pendingText="Granting…"
              className="h-11 px-5 rounded-md bg-amber-500 text-neutral-950 text-sm font-semibold hover:bg-amber-400">
              Grant access
            </SubmitButton>
          </div>
        </form>

        <div>
          <h2 className="text-sm font-semibold text-neutral-300 mb-3">Currently comped ({rows.length})</h2>
          <div className="rounded-lg border border-neutral-800 divide-y divide-neutral-800">
            {rows.length === 0 && <p className="text-sm text-neutral-500 p-4">No active comps yet.</p>}
            {rows.map((r) => (
              <div key={r.id} className="flex items-center justify-between p-4">
                <div>
                  <div className="text-sm font-medium">{r.name}</div>
                  <div className="text-xs text-neutral-500">
                    {r.exp ? (r.days! > 0 ? `${r.days} days left · ends ${r.exp.toLocaleDateString()}` : `expired ${r.exp.toLocaleDateString()}`) : "no expiry"}
                  </div>
                </div>
                <form action={revokeComp}>
                  <input type="hidden" name="orgId" value={r.id} />
                  <SubmitButton pendingText="Ending…"
                    className="text-xs border border-neutral-700 rounded-md px-3 py-2 hover:bg-neutral-800">
                    End access
                  </SubmitButton>
                </form>
              </div>
            ))}
          </div>
        </div>
      </main>
    </div>
  );
}
__EOF__

echo ""
echo "Done. Created:"
echo "  lib/admin.ts              (admin gate — 404s non-admins)"
echo "  app/admin/actions.ts      (grant / revoke, re-checks admin each time)"
echo "  app/admin/page.tsx        (the /admin page)"
echo ""
echo "NEXT:"
echo "  1) Make sure migration 0010_comp_access.sql has been run in Supabase."
echo "  2) Add your email to .env.local AND Vercel:"
echo "        ADMIN_EMAILS=starfuelwealth.wellness@gmail.com"
echo "     (comma-separate if you ever add more admins)"
echo "  3) Restart the dev server, then visit http://localhost:3004/admin"
echo "  4) Deploy: git add -A && git commit -m 'Admin: grant comp Pro access' && git push"
