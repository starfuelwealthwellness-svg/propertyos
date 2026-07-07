#!/usr/bin/env bash
# PropertyOS — Analyzer Pro foundation: plan flag + save/pipeline.
# Run from project root. Then run 0006 in Supabase.
set -e
if [ ! -f app/analyzer/Analyzer.tsx ]; then
  echo "ERROR: run the analyzer setup first (app/analyzer/Analyzer.tsx missing)."
  exit 1
fi
mkdir -p app/analyzer/saved supabase/migrations

# ---------------------------------------------------------------
cat > supabase/migrations/0006_analyzer_pro.sql << '__EOF__'
-- PropertyOS — 0006_analyzer_pro.sql
-- Adds a per-org plan flag (free/pro) and a table of saved analyses.

alter table organizations
  add column if not exists plan text not null default 'free'
  check (plan in ('free','pro'));

create table if not exists analyses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  created_by uuid references profiles(id),
  name text not null,
  address text,
  plan_name text,
  inputs jsonb not null default '{}',
  summary jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists analyses_org_idx on analyses (organization_id) where deleted_at is null;

alter table analyses enable row level security;
create policy "org access" on analyses for all
  using (organization_id in (select current_user_org_ids()))
  with check (organization_id in (select current_user_org_ids()));

create trigger trg_analyses_updated before update on analyses
  for each row execute function set_updated_at();
__EOF__

# ---------------------------------------------------------------
cat > app/analyzer/actions.ts << '__EOF__'
"use server";

import { requireOrg } from "@/lib/auth";

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
__EOF__

# ---------------------------------------------------------------
cat > app/analyzer/saved/page.tsx << '__EOF__'
import Link from "next/link";
import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";

export default async function SavedDealsPage() {
  const { supabase, orgId, membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";
  const { data: org } = await supabase
    .from("organizations").select("plan").eq("id", orgId).maybeSingle();
  const isPro = (org as any)?.plan === "pro";

  let deals: any[] | null = null;
  if (isPro) {
    const res = await supabase
      .from("analyses")
      .select("id, name, address, plan_name, summary, created_at")
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

        {!isPro ? (
          <div className="rounded-lg border border-amber-500/40 bg-neutral-900 p-6">
            <div className="text-amber-300 font-semibold">Saved deals is a Pro feature</div>
            <p className="text-sm text-neutral-400 mt-2">
              Upgrade to save analyses to a pipeline, export branded PDF reports, and send deals to your Acquisition Engine.
            </p>
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

# ---------------------------------------------------------------
cat > app/analyzer/page.tsx << '__EOF__'
import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";
import Analyzer from "./Analyzer";

export default async function AnalyzerPage() {
  const { supabase, orgId, membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";
  const { data: org } = await supabase
    .from("organizations").select("plan").eq("id", orgId).maybeSingle();
  const isPro = (org as any)?.plan === "pro";

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100">
      <AppHeader orgName={orgName} />
      <main className="max-w-5xl mx-auto px-6 py-8">
        <Analyzer isPro={isPro} />
      </main>
    </div>
  );
}
__EOF__

# ---------------------------------------------------------------
cat > app/analyzer/Analyzer.tsx << '__EOF__'
"use client";

import { useState } from "react";
import Link from "next/link";
import { saveAnalysis } from "./actions";

type Plan = {
  name: string; short: string; sqft: number; beds: number; units: number;
  psf: number; mix: string; ami: string; stories: number;
};

const PLANS: Plan[] = [
  { name: "Daffodil", short: "1bd cottage/ADU (352 sf)", sqft: 352, beds: 1, units: 1, psf: 180, mix: "1 unit · 1bd/1ba · ADU/cottage", ami: "60% AMI", stories: 1 },
  { name: "Berkeley", short: "1bd accessible cottage (560 sf)", sqft: 560, beds: 1, units: 1, psf: 175, mix: "1 unit · 1bd/1ba · adaptable ADU", ami: "80% AMI", stories: 1 },
  { name: "Lia", short: "studio garage apt (583 sf)", sqft: 583, beds: 0, units: 1, psf: 175, mix: "1 unit · studio/1ba · garage apt", ami: "80% AMI", stories: 2 },
  { name: "Nell", short: "1bd over garage (692 sf)", sqft: 692, beds: 1, units: 1, psf: 175, mix: "1 unit · 1bd/1ba over garage", ami: "80% AMI", stories: 2 },
  { name: "Tommie", short: "1bd cottage/ADU (728 sf)", sqft: 728, beds: 1, units: 1, psf: 172, mix: "1 unit · 1bd/1.5ba · cottage/ADU", ami: "100% AMI", stories: 2 },
  { name: "Bluebird", short: "2bd skinny-lot home (1,120 sf)", sqft: 1120, beds: 2, units: 1, psf: 165, mix: "1 unit · 2bd/2.5ba · skinny lot", ami: "120% AMI", stories: 2 },
  { name: "Side Hustle", short: "2bd expandable home (1,152 sf)", sqft: 1152, beds: 2, units: 1, psf: 165, mix: "1 unit · 2bd/1.5ba · expandable", ami: "120% AMI", stories: 2 },
  { name: "Front-to-Back Duplex", short: "2×1bd duplex (1,248 sf)", sqft: 1248, beds: 2, units: 2, psf: 165, mix: "2 units · 1bd/1ba each", ami: "—", stories: 1 },
  { name: "Azalea+", short: "1bd + rooming studio (1,350 sf)", sqft: 1350, beds: 1, units: 1, psf: 165, mix: "1 home + rooming studio", ami: "100% / 60% AMI", stories: 2 },
  { name: "Chickadee+", short: "2bd + rooming studio (1,450 sf)", sqft: 1450, beds: 2, units: 1, psf: 160, mix: "1 home + rooming studio", ami: "100% / 60% AMI", stories: 2 },
  { name: "Standard House", short: "3bd family home (1,632 sf)", sqft: 1632, beds: 3, units: 1, psf: 160, mix: "1 unit · 3bd/2.5ba", ami: "—", stories: 2 },
  { name: "Stacked Duplex", short: "2×2bd stacked duplex (2,112 sf)", sqft: 2112, beds: 4, units: 2, psf: 155, mix: "2 units · 2bd/1ba each", ami: "—", stories: 2 },
  { name: "Audrey", short: "2×2bd duplex/townhouse (2,312 sf)", sqft: 2312, beds: 4, units: 2, psf: 155, mix: "2 units · 2bd/2.5ba + 2bd/1.5ba", ami: "120% AMI", stories: 2 },
  { name: "Marie Louise", short: "3bd + 1bd lifelong home (2,369 sf)", sqft: 2369, beds: 4, units: 2, psf: 155, mix: "2 units · 3bd/2.5ba + 1bd/1ba", ami: "150% / 100% AMI", stories: 2 },
  { name: "Myrtle 4-Plex", short: "4×1bd fourplex (2,400 sf)", sqft: 2400, beds: 4, units: 4, psf: 152, mix: "4 units · 1bd/1ba each", ami: "120% / 80% AMI", stories: 2 },
  { name: "Lydia", short: "2×2bd duplex/townhouse (2,836 sf)", sqft: 2836, beds: 4, units: 2, psf: 155, mix: "2 units · 2bd/2.5ba each", ami: "150% AMI", stories: 2 },
  { name: "Carroll 6-Plex", short: "6-unit apartments (3,696 sf)", sqft: 3696, beds: 8, units: 6, psf: 150, mix: "6 units · 2×2bd + 4×1bd", ami: "100% / 80% AMI", stories: 2 },
  { name: "Oakdale 8-Plex", short: "8-unit apartments (4,280 sf)", sqft: 4280, beds: 8, units: 8, psf: 148, mix: "8 units · 1bd/1ba", ami: "80% / 100% AMI", stories: 2 },
];

const money = (n: number) => (n < 0 ? "-$" : "$") + Math.round(Math.abs(n)).toLocaleString();
const pct = (n: number) => (n * 100).toFixed(1) + "%";

function amortBalance(P: number, rMo: number, nTot: number, made: number) {
  if (P <= 0) return 0;
  if (rMo === 0) return Math.max(0, P * (1 - made / nTot));
  const f = Math.pow(1 + rMo, nTot), g = Math.pow(1 + rMo, made);
  return (P * (f - g)) / (f - 1);
}

const input = "w-full rounded-md bg-neutral-900 border border-neutral-800 px-3 py-2 text-sm outline-none focus:border-amber-500";
const label = "block text-xs uppercase tracking-wide text-neutral-500 mb-1";

function Line({ k, v, strong, neg }: { k: string; v: string; strong?: boolean; neg?: boolean }) {
  return (
    <div className="flex justify-between items-baseline py-2 border-b border-neutral-800/70 text-sm">
      <span className="text-neutral-400">{k}</span>
      <span className={(strong ? "text-amber-300 font-semibold " : "font-medium ") + (neg ? "text-red-400" : "text-neutral-100")}>{v}</span>
    </div>
  );
}

export default function Analyzer({ isPro }: { isPro: boolean }) {
  const [f, setF] = useState({
    planIdx: 16, addr: "1125 E 36th St N, Tulsa, OK", lotSize: "6000", landCost: "15000",
    sqft: "3696", beds: "8", units: "6", buildPsf: "150", softPct: "18", finVal: "",
    downPct: "20", rate: "7.25", term: "30", rentPsf: "1.50", vac: "7", opex: "35", appr: "3", hold: "10",
  });
  const [saveName, setSaveName] = useState("");
  const [saving, setSaving] = useState(false);
  const [saveMsg, setSaveMsg] = useState("");

  const set = (k: string, v: string) => setF((s) => ({ ...s, [k]: v }));
  const setPlan = (i: number) => {
    const p = PLANS[i];
    setF((s) => ({ ...s, planIdx: i, sqft: String(p.sqft), beds: String(p.beds), units: String(p.units), buildPsf: String(p.psf) }));
  };
  const n = (k: keyof typeof f) => Number(f[k]) || 0;

  const hard = n("sqft") * n("buildPsf");
  const soft = hard * (n("softPct") / 100);
  const total = n("landCost") + hard + soft;
  const finVal = n("finVal") > 0 ? n("finVal") : total;
  const instant = finVal - total;
  const down = total * (n("downPct") / 100);
  const loan = total - down;
  const rMo = n("rate") / 100 / 12;
  const nTot = n("term") * 12;
  const factor = rMo === 0 ? (nTot > 0 ? 1 / nTot : 0) : (rMo * Math.pow(1 + rMo, nTot)) / (Math.pow(1 + rMo, nTot) - 1);
  const pi = loan > 0 ? loan * factor : 0;
  const debtYr = pi * 12;
  const rentMo = n("sqft") * n("rentPsf");
  const egi = rentMo * 12 * (1 - n("vac") / 100);
  const noi = egi * (1 - n("opex") / 100);
  const cfYr = noi - debtYr;
  const cfMo = cfYr / 12;
  const cap = total > 0 ? noi / total : 0;
  const coc = down > 0 ? cfYr / down : 0;
  const fv = finVal * Math.pow(1 + n("appr") / 100, n("hold"));
  const equity = fv - amortBalance(loan, rMo, nTot, Math.min(n("hold") * 12, nTot));

  const rentDenom = n("sqft") * 12 * (1 - n("vac") / 100) * (1 - n("opex") / 100);
  const beRentPsf = rentDenom > 0 ? debtYr / rentDenom : NaN;
  const beRentPerUnit = n("units") > 0 ? (beRentPsf * n("sqft")) / n("units") : NaN;
  const dsCap = (1 - n("downPct") / 100) * factor * 12;
  const totalForBE = dsCap > 0 ? noi / dsCap : NaN;
  const beBuildPsf = (totalForBE - n("landCost")) / (n("sqft") * (1 + n("softPct") / 100));
  const beLand = totalForBE - hard - soft;

  let vClass = "bg-green-500/15 text-green-300 border-green-500/40", vText = "Pencils";
  if (!(cfMo >= 0 && coc >= 0.05)) {
    if (cfMo >= 0) { vClass = "bg-amber-500/15 text-amber-300 border-amber-500/40"; vText = "Tight but positive"; }
    else { vClass = "bg-red-500/15 text-red-300 border-red-500/40"; vText = "Underwater"; }
  }
  const plan = PLANS[f.planIdx];

  const useBtn = "shrink-0 rounded-md bg-amber-500 text-neutral-950 text-xs font-semibold px-2.5 py-1 hover:bg-amber-400";
  const useBtnOff = "shrink-0 rounded-md border border-neutral-700 text-neutral-600 text-xs font-semibold px-2.5 py-1 cursor-not-allowed";

  async function doSave() {
    setSaving(true); setSaveMsg("");
    const res = await saveAnalysis({
      name: saveName || f.addr || plan.name,
      address: f.addr,
      planName: plan.name,
      inputs: f,
      summary: { total, cfMo, coc, verdict: vText },
    });
    setSaving(false);
    setSaveMsg(res.ok ? "Saved to your pipeline." : (res.error || "Could not save."));
  }

  return (
    <div className="space-y-6">
      <div>
        <div className="text-xs uppercase tracking-wide text-amber-400 font-semibold">Infill Build Analyzer</div>
        <h1 className="text-2xl font-semibold mt-1">Does this lot pencil into a home you can own?</h1>
        <p className="text-sm text-neutral-400 mt-1 max-w-2xl">
          Pair a vacant Tulsa lot with a pre-approved T-Town HOME Catalog plan and see the build-to-own numbers in real time.
        </p>
      </div>

      <div className="flex flex-wrap items-center gap-3">
        <span className={"inline-flex items-center gap-2 rounded-full border px-4 py-1.5 text-sm font-semibold " + vClass}>{vText}</span>
        <span className="text-sm text-neutral-400">Total project cost <b className="text-neutral-100">{money(total)}</b></span>
        <span className="text-sm text-neutral-400">Cash flow/mo <b className={cfMo < 0 ? "text-red-400" : "text-neutral-100"}>{money(cfMo)}</b></span>
        <span className="text-sm text-neutral-400">Cash-on-cash <b className="text-neutral-100">{pct(coc)}</b></span>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 items-start">
        {/* INPUTS */}
        <div className="rounded-lg border border-neutral-800 bg-neutral-900 p-5 space-y-3">
          <div className="text-sm font-semibold text-neutral-200 mb-1">The site &amp; the plan</div>
          <div>
            <label className={label}>Lot address (for reference)</label>
            <input className={input} value={f.addr} onChange={(e) => set("addr", e.target.value)} />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className={label}>Lot size (sq ft)</label><input className={input} type="number" value={f.lotSize} onChange={(e) => set("lotSize", e.target.value)} /></div>
            <div><label className={label}>Land cost ($)</label><input className={input} type="number" value={f.landCost} onChange={(e) => set("landCost", e.target.value)} /></div>
          </div>
          <div>
            <label className={label}>Catalog plan (T-Town HOME Catalog)</label>
            <select className={input} value={f.planIdx} onChange={(e) => setPlan(Number(e.target.value))}>
              {PLANS.map((p, i) => <option key={i} value={i}>{p.name} — {p.short}</option>)}
            </select>
            <div className="flex flex-wrap gap-2 mt-2">
              <span className="text-xs bg-neutral-800 border border-neutral-700 rounded px-2 py-0.5 text-neutral-300">{plan.mix}</span>
              <span className="text-xs bg-neutral-800 border border-neutral-700 rounded px-2 py-0.5 text-neutral-300">{plan.stories} stories</span>
              {plan.ami !== "—" && <span className="text-xs bg-amber-500/15 border border-amber-500/40 rounded px-2 py-0.5 text-amber-300 font-medium">{plan.ami}</span>}
            </div>
          </div>
          <div className="grid grid-cols-3 gap-3">
            <div><label className={label}>Build sq ft</label><input className={input} type="number" value={f.sqft} onChange={(e) => set("sqft", e.target.value)} /></div>
            <div><label className={label}>Build $/sf</label><input className={input} type="number" value={f.buildPsf} onChange={(e) => set("buildPsf", e.target.value)} /></div>
            <div><label className={label}>Soft %</label><input className={input} type="number" value={f.softPct} onChange={(e) => set("softPct", e.target.value)} /></div>
          </div>
          <div className="grid grid-cols-3 gap-3">
            <div><label className={label}>Down %</label><input className={input} type="number" value={f.downPct} onChange={(e) => set("downPct", e.target.value)} /></div>
            <div><label className={label}>Rate %</label><input className={input} type="number" step="0.01" value={f.rate} onChange={(e) => set("rate", e.target.value)} /></div>
            <div><label className={label}>Term (yrs)</label><input className={input} type="number" value={f.term} onChange={(e) => set("term", e.target.value)} /></div>
          </div>
          <div className="grid grid-cols-3 gap-3">
            <div><label className={label}>Rent $/sf/mo</label><input className={input} type="number" step="0.01" value={f.rentPsf} onChange={(e) => set("rentPsf", e.target.value)} /></div>
            <div><label className={label}>Vacancy %</label><input className={input} type="number" value={f.vac} onChange={(e) => set("vac", e.target.value)} /></div>
            <div><label className={label}>Op-ex %</label><input className={input} type="number" value={f.opex} onChange={(e) => set("opex", e.target.value)} /></div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className={label}>Appreciation %/yr</label><input className={input} type="number" step="0.1" value={f.appr} onChange={(e) => set("appr", e.target.value)} /></div>
            <div><label className={label}>Hold (yrs)</label><input className={input} type="number" value={f.hold} onChange={(e) => set("hold", e.target.value)} /></div>
          </div>
        </div>

        {/* OUTPUTS */}
        <div className="space-y-4">
          <div className="rounded-lg border border-neutral-800 bg-neutral-900 p-5">
            <div className="text-sm font-semibold text-neutral-200 mb-2">The pro forma</div>
            <Line k="Land / lot" v={money(n("landCost"))} />
            <Line k="Hard cost (build)" v={money(hard)} />
            <Line k="Soft costs" v={money(soft)} />
            <Line k="Total project cost" v={money(total)} strong />
            <div className="h-3" />
            <Line k="Down payment (cash in)" v={money(down)} />
            <Line k="Loan amount" v={money(loan)} />
            <Line k="Mortgage (P&I) / mo" v={money(pi)} />
            <div className="h-3" />
            <Line k="Gross rent / mo" v={money(rentMo)} />
            <Line k="Net operating income / yr" v={money(noi)} />
            <Line k="Cash flow / mo (after mortgage)" v={money(cfMo)} neg={cfMo < 0} />
            <div className="grid grid-cols-2 gap-3 mt-4">
              <div className="rounded-md bg-neutral-800/60 border border-neutral-700 p-3"><div className="text-xs text-neutral-400 uppercase tracking-wide">Cap rate</div><div className="text-2xl font-semibold">{pct(cap)}</div></div>
              <div className="rounded-md bg-neutral-800/60 border border-neutral-700 p-3"><div className="text-xs text-neutral-400 uppercase tracking-wide">Cash-on-cash</div><div className={"text-2xl font-semibold " + (coc >= 0 ? "text-green-400" : "text-red-400")}>{pct(coc)}</div></div>
            </div>
          </div>

          {/* BREAK-EVEN SOLVER (free) */}
          <div className="rounded-lg border border-amber-500/30 bg-neutral-900 p-5">
            <div className="text-sm font-semibold text-amber-300">Break-even solver</div>
            <p className="text-xs text-neutral-500 mt-1 mb-3">
              {cfMo >= 0
                ? "This deal already cash-flows. Here's how much room you have on each lever."
                : "What one change brings monthly cash flow to $0 — holding everything else fixed."}
            </p>
            <div className="flex items-center justify-between gap-3 py-2 border-b border-neutral-800/70">
              <div>
                <div className="text-sm text-neutral-200">Rent needed</div>
                <div className="text-xs text-neutral-500">
                  {isFinite(beRentPsf) ? "$" + beRentPsf.toFixed(2) + "/sf" : "—"}
                  {isFinite(beRentPerUnit) ? " · " + money(beRentPerUnit) + "/unit avg" : ""}
                  {isFinite(beRentPsf) && beRentPsf > 1.9 ? " · likely above Tulsa market" : ""}
                </div>
              </div>
              <button className={isFinite(beRentPsf) && beRentPsf > 0 ? useBtn : useBtnOff}
                disabled={!(isFinite(beRentPsf) && beRentPsf > 0)}
                onClick={() => set("rentPsf", beRentPsf.toFixed(2))}>Use</button>
            </div>
            <div className="flex items-center justify-between gap-3 py-2 border-b border-neutral-800/70">
              <div>
                <div className="text-sm text-neutral-200">Max build cost</div>
                <div className="text-xs text-neutral-500">
                  {isFinite(beBuildPsf) && beBuildPsf > 0 ? "$" + Math.round(beBuildPsf) + "/sf or less" : "even $0 build won't reach it at this rent"}
                </div>
              </div>
              <button className={isFinite(beBuildPsf) && beBuildPsf > 0 ? useBtn : useBtnOff}
                disabled={!(isFinite(beBuildPsf) && beBuildPsf > 0)}
                onClick={() => set("buildPsf", String(Math.round(beBuildPsf)))}>Use</button>
            </div>
            <div className="flex items-center justify-between gap-3 py-2">
              <div>
                <div className="text-sm text-neutral-200">Max land price</div>
                <div className="text-xs text-neutral-500">
                  {isFinite(beLand) && beLand >= 0 ? money(beLand) + " or less" : "even free land won't reach it — cut build cost, raise rent, or lower the rate"}
                </div>
              </div>
              <button className={isFinite(beLand) && beLand >= 0 ? useBtn : useBtnOff}
                disabled={!(isFinite(beLand) && beLand >= 0)}
                onClick={() => set("landCost", String(Math.round(beLand)))}>Use</button>
            </div>
          </div>

          {/* BUILD-TO-OWN (free) */}
          <div className="rounded-lg border border-amber-500/40 bg-gradient-to-b from-neutral-900 to-neutral-950 p-5">
            <div className="text-xs uppercase tracking-wide text-amber-400 font-semibold">Build-to-own outlook</div>
            <p className="text-lg mt-2 leading-snug">
              {cfMo >= 0
                ? <>Build for about <b className="text-amber-300">{money(total)}</b>, rent at <b className="text-amber-300">{money(rentMo)}/mo</b>, and it puts <b className="text-amber-300">{money(cfMo)}/mo</b> in your pocket. In <b className="text-amber-300">{n("hold")} years</b> you'd hold roughly <b className="text-amber-300">{money(equity)}</b> in equity{instant > 0 ? <> — and about <b className="text-amber-300">{money(instant)}</b> in instant equity the day you finish.</> : "."}</>
                : <>At these numbers it runs <b className="text-red-400">{money(-cfMo)}/mo</b> short after the mortgage. Use the break-even solver above to see exactly what it takes. In <b className="text-amber-300">{n("hold")} years</b> the equity position is about <b className="text-amber-300">{money(equity)}</b>.</>}
            </p>
          </div>

          {/* SAVE / PRO */}
          <div className="rounded-lg border border-amber-500/40 bg-neutral-900 p-5 space-y-3">
            <div className="flex items-center justify-between gap-3">
              <div className="text-sm font-semibold text-amber-300">{isPro ? "Save this deal" : "Save, export & track deals — with Pro"}</div>
              <Link href="/analyzer/saved" className="text-xs text-neutral-400 hover:text-white">View saved deals →</Link>
            </div>
            {isPro ? (
              <>
                <div className="flex gap-2">
                  <input className={input + " flex-1"} placeholder="Name this deal" value={saveName} onChange={(e) => setSaveName(e.target.value)} />
                  <button onClick={doSave} disabled={saving} className="shrink-0 rounded-md bg-amber-500 text-neutral-950 text-sm font-semibold px-4 py-2 hover:bg-amber-400 disabled:opacity-60">{saving ? "Saving…" : "Save"}</button>
                </div>
                {saveMsg && <p className="text-xs text-neutral-400">{saveMsg}</p>}
              </>
            ) : (
              <>
                <p className="text-sm text-neutral-400">Save deals to a pipeline, export branded PDF reports, and send deals to your Acquisition Engine.</p>
                <button onClick={() => setSaveMsg("Saving deals is a Pro feature — upgrade coming soon.")} className="rounded-md border border-amber-500 text-amber-300 text-sm font-medium px-3 py-2 hover:bg-amber-500/10">Save this deal</button>
                {saveMsg && <p className="text-xs text-amber-300/80">{saveMsg}</p>}
              </>
            )}
          </div>

          <p className="text-xs text-neutral-600">
            Plan specs are from the City of Tulsa T-Town HOME Catalog. Cost, rent, and financing figures are editable estimates for planning only — not financial advice.
          </p>
        </div>
      </div>
    </div>
  );
}
__EOF__

echo ""
echo "Done. Created/updated:"
echo "  supabase/migrations/0006_analyzer_pro.sql   (RUN IN SUPABASE)"
echo "  app/analyzer/actions.ts"
echo "  app/analyzer/saved/page.tsx"
echo "  app/analyzer/page.tsx        (passes plan to Analyzer)"
echo "  app/analyzer/Analyzer.tsx    (adds Pro-gated save widget)"
echo ""
echo "Then run 0006 in Supabase, and to TEST Pro, flip your org:"
echo "  update organizations set plan='pro' where id=(select id from organizations order by created_at desc limit 1);"
