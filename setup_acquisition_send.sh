#!/usr/bin/env bash
# PropertyOS — "Send to Acquisition Engine" handoff (final Pro feature).
# Run from project root. Then run 0008 in Supabase + add two env vars.
set -e
if [ ! -f app/analyzer/actions.ts ]; then
  echo "ERROR: run the analyzer Pro setup first."
  exit 1
fi
mkdir -p supabase/migrations

# ---------------------------------------------------------------
cat > supabase/migrations/0008_acquisition_send.sql << '__EOF__'
-- PropertyOS — 0008_acquisition_send.sql
-- Track when an analysis was pushed to the Acquisition Engine.

alter table analyses
  add column if not exists sent_to_acquisition_at timestamptz,
  add column if not exists acquisition_deal_id text;
__EOF__

# ---------------------------------------------------------------
# Rewrite analyzer actions to include BOTH saveAnalysis and sendToAcquisition.
cat > app/analyzer/actions.ts << '__EOF__'
"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { requireOrg } from "@/lib/auth";
import { computeProForma } from "@/lib/proforma";

type SaveInput = {
  name: string; address: string; planName: string; inputs: unknown; summary: unknown;
};

export async function saveAnalysis(data: SaveInput) {
  const { supabase, orgId, user } = await requireOrg();
  const { data: org } = await supabase
    .from("organizations").select("plan").eq("id", orgId).maybeSingle();
  if ((org as any)?.plan !== "pro") {
    return { ok: false as const, error: "Saving deals is a Pro feature." };
  }
  const { error } = await supabase.from("analyses").insert({
    organization_id: orgId,
    created_by: user.id,
    name: (data.name || "Untitled deal").slice(0, 120),
    address: data.address || null,
    plan_name: data.planName || null,
    inputs: data.inputs ?? {},
    summary: data.summary ?? {},
  });
  if (error) return { ok: false as const, error: error.message };
  return { ok: true as const };
}

const ERR = (msg: string) => redirect("/analyzer/saved?error=" + encodeURIComponent(msg));

export async function sendToAcquisition(formData: FormData) {
  const dealId = String(formData.get("id"));
  const { supabase, orgId, user } = await requireOrg();

  const { data: org } = await supabase
    .from("organizations").select("plan").eq("id", orgId).maybeSingle();
  if ((org as any)?.plan !== "pro") ERR("Sending deals is a Pro feature.");
  if (!user.email) ERR("Your account has no email on file.");

  const { data: deal } = await supabase
    .from("analyses").select("*").eq("id", dealId).is("deleted_at", null).maybeSingle();
  if (!deal) ERR("Deal not found.");
  const d = deal as any;

  const base = process.env.ACQUISITION_ENGINE_URL;
  const secret = process.env.ACQUISITION_INGEST_SECRET;
  if (!base || !secret) ERR("Acquisition Engine isn't configured (missing URL or key).");

  const c = computeProForma(d.inputs || {});
  const payload = {
    source: "propertyos",
    source_ref: d.id,
    email: user.email,
    name: d.name,
    address: d.address || undefined,
    plan_name: d.plan_name || undefined,
    total_project_cost: Math.round(c.total),
    monthly_cash_flow: Math.round(c.cfMo),
    cap_rate: Number(c.cap.toFixed(4)),
    cash_on_cash: Number(c.coc.toFixed(4)),
    verdict: c.verdict,
    notes: "Imported from Starfuel PropertyOS Infill Build Analyzer",
  };

  let res: Response;
  try {
    res = await fetch(base + "/api/deals/ingest", {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-api-key": secret! },
      body: JSON.stringify(payload),
      cache: "no-store",
    });
  } catch {
    ERR("Could not reach the Acquisition Engine.");
    return;
  }

  if (res.status === 404) ERR("No Acquisition Engine account for " + user.email + ". Sign up there with the same email first.");
  if (res.status === 401) ERR("Acquisition Engine rejected the key — check the shared secret matches in both apps.");
  if (!res.ok) ERR("Send failed (HTTP " + res.status + ").");

  const bodyJson: any = await res.json().catch(() => ({}));
  await supabase.from("analyses").update({
    sent_to_acquisition_at: new Date().toISOString(),
    acquisition_deal_id: bodyJson?.dealId ?? null,
  }).eq("id", dealId);

  revalidatePath("/analyzer/saved");
  redirect("/analyzer/saved?sent=" + (bodyJson?.deduped ? "already" : "1"));
}
__EOF__

# ---------------------------------------------------------------
# Saved deals: add Send button / Sent status + result banners.
cat > app/analyzer/saved/page.tsx << '__EOF__'
import Link from "next/link";
import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";
import SubmitButton from "@/app/_components/SubmitButton";
import { sendToAcquisition } from "../actions";

export default async function SavedDealsPage({
  searchParams,
}: {
  searchParams: Promise<{ sent?: string; error?: string }>;
}) {
  const { supabase, orgId, membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";
  const { data: org } = await supabase.from("organizations").select("plan").eq("id", orgId).maybeSingle();
  const isPro = (org as any)?.plan === "pro";
  const sp = await searchParams;

  let deals: any[] | null = null;
  if (isPro) {
    const res = await supabase
      .from("analyses")
      .select("id, name, address, plan_name, summary, created_at, sent_to_acquisition_at")
      .is("deleted_at", null)
      .order("created_at", { ascending: false });
    deals = res.data;
  }

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100">
      <AppHeader orgName={orgName} />
      <main className="max-w-4xl mx-auto px-6 py-8 space-y-6">
        <div className="flex items-center justify-between">
          <h1 className="text-xl font-semibold">Saved deals</h1>
          <Link href="/analyzer" className="text-sm text-amber-300 hover:underline">← Back to Analyzer</Link>
        </div>

        {sp.sent === "1" && <p className="text-sm text-green-400 bg-green-950/30 border border-green-900 rounded-md p-3">Sent to your Acquisition Engine pipeline.</p>}
        {sp.sent === "already" && <p className="text-sm text-amber-300 bg-amber-950/20 border border-amber-900 rounded-md p-3">That deal was already in your Acquisition Engine pipeline.</p>}
        {sp.error && <p className="text-sm text-red-400 bg-red-950/40 border border-red-900 rounded-md p-3">{sp.error}</p>}

        {!isPro ? (
          <div className="rounded-lg border border-amber-500/40 bg-neutral-900 p-6">
            <div className="text-amber-300 font-semibold">Saved deals is a Pro feature</div>
            <p className="text-sm text-neutral-400 mt-2">
              Upgrade to save analyses to a pipeline, export branded PDF reports, and send deals to your Acquisition Engine.
            </p>
            <Link href="/billing" className="inline-block mt-4 rounded-md bg-amber-500 text-neutral-950 text-sm font-semibold px-4 py-2 hover:bg-amber-400">
              Upgrade to Pro →
            </Link>
          </div>
        ) : !deals || deals.length === 0 ? (
          <p className="text-neutral-400 text-sm">No saved deals yet. Run an analysis and click &ldquo;Save this deal.&rdquo;</p>
        ) : (
          <div className="grid gap-3">
            {deals.map((d: any) => {
              const s = d.summary || {};
              const verdict = s.verdict ?? "—";
              const vc = verdict === "Pencils" ? "text-green-400" : verdict === "Underwater" ? "text-red-400" : "text-amber-400";
              return (
                <div key={d.id} className="rounded-lg border border-neutral-800 bg-neutral-900 p-4">
                  <div className="flex items-center justify-between">
                    <div className="font-medium">{d.name}</div>
                    <div className={"text-sm font-semibold " + vc}>{verdict}</div>
                  </div>
                  <div className="text-sm text-neutral-400 mt-1">
                    {d.plan_name ?? "—"}{d.address ? " · " + d.address : ""}
                  </div>
                  <div className="text-xs text-neutral-500 mt-2 flex flex-wrap gap-4">
                    {s.total != null && <span>Cost ${Number(s.total).toLocaleString()}</span>}
                    {s.cfMo != null && <span>Cash flow ${Math.round(s.cfMo).toLocaleString()}/mo</span>}
                    {s.coc != null && <span>CoC {(s.coc * 100).toFixed(1)}%</span>}
                    <span>{new Date(d.created_at).toLocaleDateString()}</span>
                  </div>
                  <div className="mt-3 pt-3 border-t border-neutral-800 flex items-center gap-4">
                    <Link href={"/analyzer/report/" + d.id} className="text-xs text-amber-300 hover:underline">PDF report →</Link>
                    <div className="ml-auto">
                      {d.sent_to_acquisition_at ? (
                        <span className="text-xs text-green-400">Sent to Acquisition ✓</span>
                      ) : (
                        <form action={sendToAcquisition}>
                          <input type="hidden" name="id" value={d.id} />
                          <SubmitButton pendingText="Sending…" className="text-xs rounded-md border border-amber-500/50 text-amber-300 px-2.5 py-1 hover:bg-amber-500/10">
                            Send to Acquisition Engine
                          </SubmitButton>
                        </form>
                      )}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </main>
    </div>
  );
}
__EOF__

echo ""
echo "Done. Created/updated:"
echo "  supabase/migrations/0008_acquisition_send.sql   (RUN IN SUPABASE)"
echo "  app/analyzer/actions.ts     (added sendToAcquisition)"
echo "  app/analyzer/saved/page.tsx (Send button + Sent status + banners)"
echo ""
echo "Then add to .env.local (and later Vercel):"
echo "  ACQUISITION_ENGINE_URL=https://starfuel-acquisition-engine-7qw7.vercel.app"
echo "  ACQUISITION_INGEST_SECRET=<same value as the Acquisition Engine>"
