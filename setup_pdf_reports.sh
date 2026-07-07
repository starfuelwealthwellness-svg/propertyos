#!/usr/bin/env bash
# PropertyOS — Analyzer Pro: branded PDF reports.
# Run from project root. No database change needed.
set -e
if [ ! -f app/analyzer/Analyzer.tsx ]; then
  echo "ERROR: run the analyzer setup first."
  exit 1
fi
mkdir -p "app/analyzer/report/[id]" lib

# ---------------------------------------------------------------
cat > lib/proforma.ts << '__EOF__'
// Shared pro-forma math. Mirrors the Analyzer's calculation so a saved
// deal's stored inputs recompute identically for reports.

export function computeProForma(inp: Record<string, unknown>) {
  const num = (v: unknown) => Number(v) || 0;
  const sqft = num(inp.sqft), buildPsf = num(inp.buildPsf), softPct = num(inp.softPct), landCost = num(inp.landCost);
  const hard = sqft * buildPsf;
  const soft = hard * (softPct / 100);
  const total = landCost + hard + soft;
  const finVal = num(inp.finVal) > 0 ? num(inp.finVal) : total;
  const instant = finVal - total;
  const down = total * (num(inp.downPct) / 100);
  const loan = total - down;
  const rMo = num(inp.rate) / 100 / 12;
  const nTot = num(inp.term) * 12;
  const factor = rMo === 0 ? (nTot > 0 ? 1 / nTot : 0) : (rMo * Math.pow(1 + rMo, nTot)) / (Math.pow(1 + rMo, nTot) - 1);
  const pi = loan > 0 ? loan * factor : 0;
  const debtYr = pi * 12;
  const rentMo = sqft * num(inp.rentPsf);
  const egi = rentMo * 12 * (1 - num(inp.vac) / 100);
  const noi = egi * (1 - num(inp.opex) / 100);
  const cfMo = (noi - debtYr) / 12;
  const cap = total > 0 ? noi / total : 0;
  const coc = down > 0 ? (noi - debtYr) / down : 0;
  const fv = finVal * Math.pow(1 + num(inp.appr) / 100, num(inp.hold));
  const made = Math.min(num(inp.hold) * 12, nTot);
  let bal = 0;
  if (loan > 0) {
    if (rMo === 0) bal = Math.max(0, loan * (1 - made / nTot));
    else { const a = Math.pow(1 + rMo, nTot), b = Math.pow(1 + rMo, made); bal = (loan * (a - b)) / (a - 1); }
  }
  const equity = fv - bal;
  let verdict = "Pencils";
  if (!(cfMo >= 0 && coc >= 0.05)) verdict = cfMo >= 0 ? "Tight but positive" : "Underwater";
  return { landCost, hard, soft, total, finVal, instant, down, loan, pi, rentMo, noi, cfMo, cap, coc, fv, equity, verdict, hold: num(inp.hold) };
}
__EOF__

# ---------------------------------------------------------------
cat > app/analyzer/PrintButton.tsx << '__EOF__'
"use client";

export default function PrintButton() {
  return (
    <button
      onClick={() => window.print()}
      className="rounded-md bg-amber-500 text-neutral-950 text-sm font-semibold px-4 py-2 hover:bg-amber-400"
    >
      Download / Print PDF
    </button>
  );
}
__EOF__

# ---------------------------------------------------------------
cat > "app/analyzer/report/[id]/page.tsx" << '__EOF__'
import Link from "next/link";
import { redirect } from "next/navigation";
import { requireOrg } from "@/lib/auth";
import { computeProForma } from "@/lib/proforma";
import PrintButton from "@/app/analyzer/PrintButton";

const money = (n: number) => (n < 0 ? "-$" : "$") + Math.round(Math.abs(n)).toLocaleString();
const pct = (n: number) => (n * 100).toFixed(1) + "%";

function Row({ k, v, strong }: { k: string; v: string; strong?: boolean }) {
  return (
    <div className={"flex justify-between py-1.5 border-b border-neutral-200 text-sm " + (strong ? "font-semibold" : "")}>
      <span className={strong ? "text-neutral-900" : "text-neutral-600"}>{k}</span>
      <span className="text-neutral-900 tabular-nums">{v}</span>
    </div>
  );
}

export default async function ReportPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { supabase, orgId, membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";

  const { data: org } = await supabase.from("organizations").select("plan").eq("id", orgId).maybeSingle();
  if ((org as any)?.plan !== "pro") redirect("/analyzer/saved");

  const { data: deal } = await supabase.from("analyses").select("*").eq("id", id).is("deleted_at", null).maybeSingle();
  if (!deal) redirect("/analyzer/saved");
  const d = deal as any;
  const c = computeProForma(d.inputs || {});

  const badge =
    c.verdict === "Pencils" ? "bg-green-100 text-green-800 border-green-300"
    : c.verdict === "Underwater" ? "bg-red-100 text-red-800 border-red-300"
    : "bg-amber-100 text-amber-800 border-amber-300";

  return (
    <div className="min-h-screen bg-neutral-300 py-8 print:bg-white print:py-0 print:min-h-0">
      <div className="max-w-3xl mx-auto px-4 flex justify-between items-center mb-4 print:hidden">
        <Link href="/analyzer/saved" className="text-sm text-neutral-700 hover:text-neutral-900">← Back to saved deals</Link>
        <PrintButton />
      </div>

      <div className="max-w-3xl mx-auto bg-white text-neutral-900 shadow-lg print:shadow-none p-10 print:p-8">
        {/* Masthead */}
        <div className="text-[11px] font-semibold tracking-[0.18em] text-amber-700 uppercase">Starfuel PropertyOS</div>
        <div className="mt-1 pb-3 border-b-2 border-amber-600 flex items-end justify-between">
          <div>
            <h1 className="text-2xl font-bold">Infill Build Analysis</h1>
            <div className="text-sm text-neutral-500">{orgName}</div>
          </div>
          <span className={"text-sm font-semibold px-3 py-1 rounded-full border " + badge}>{c.verdict}</span>
        </div>

        {/* Meta */}
        <div className="grid grid-cols-2 gap-x-8 gap-y-1 mt-4 text-sm">
          <div><span className="text-neutral-500">Deal:</span> <b>{d.name}</b></div>
          <div><span className="text-neutral-500">Plan:</span> {d.plan_name ?? "—"}</div>
          <div><span className="text-neutral-500">Address:</span> {d.address ?? "—"}</div>
          <div><span className="text-neutral-500">Prepared:</span> {new Date(d.created_at).toLocaleDateString()}</div>
        </div>

        {/* Cost + financing */}
        <div className="grid grid-cols-2 gap-8 mt-6">
          <div>
            <div className="text-xs uppercase tracking-wide text-neutral-500 font-semibold mb-1">Project cost</div>
            <Row k="Land / lot" v={money(c.landCost)} />
            <Row k="Hard cost (build)" v={money(c.hard)} />
            <Row k="Soft costs" v={money(c.soft)} />
            <Row k="Total project cost" v={money(c.total)} strong />
          </div>
          <div>
            <div className="text-xs uppercase tracking-wide text-neutral-500 font-semibold mb-1">Financing &amp; operations</div>
            <Row k="Down payment" v={money(c.down)} />
            <Row k="Loan amount" v={money(c.loan)} />
            <Row k="Mortgage / mo" v={money(c.pi)} />
            <Row k="Gross rent / mo" v={money(c.rentMo)} />
            <Row k="Net operating income / yr" v={money(c.noi)} />
            <Row k="Cash flow / mo" v={money(c.cfMo)} strong />
          </div>
        </div>

        {/* Metrics */}
        <div className="grid grid-cols-3 gap-4 mt-6">
          <div className="border border-neutral-200 rounded-lg p-3"><div className="text-[11px] uppercase tracking-wide text-neutral-500">Cap rate</div><div className="text-xl font-bold">{pct(c.cap)}</div></div>
          <div className="border border-neutral-200 rounded-lg p-3"><div className="text-[11px] uppercase tracking-wide text-neutral-500">Cash-on-cash</div><div className="text-xl font-bold">{pct(c.coc)}</div></div>
          <div className="border border-neutral-200 rounded-lg p-3"><div className="text-[11px] uppercase tracking-wide text-neutral-500">Equity @ yr {c.hold}</div><div className="text-xl font-bold">{money(c.equity)}</div></div>
        </div>

        {/* Narrative */}
        <div className="mt-6 rounded-lg bg-neutral-50 border border-neutral-200 p-4 text-sm">
          <div className="text-xs uppercase tracking-wide text-amber-700 font-semibold mb-1">Build-to-own outlook</div>
          {c.cfMo >= 0
            ? <>Built for about <b>{money(c.total)}</b> and rented at <b>{money(c.rentMo)}/mo</b>, this project nets <b>{money(c.cfMo)}/mo</b> after financing, and grows to roughly <b>{money(c.equity)}</b> in equity over {c.hold} years{c.instant > 0 ? <>, with about <b>{money(c.instant)}</b> in equity created the day it's finished.</> : "."}</>
            : <>At these assumptions the project runs <b>{money(-c.cfMo)}/mo</b> short after financing. It reaches feasibility with lower build cost, cheaper land, subsidized financing, or higher rent — the levers infill and affordable-housing programs are designed to provide.</>}
        </div>

        <div className="mt-6 pt-3 border-t border-neutral-200 text-[10px] text-neutral-500 leading-relaxed">
          Plan specifications are from the City of Tulsa T-Town HOME Catalog. Cost, rent, and financing figures are planning estimates only and do not constitute financial, investment, or lending advice. Generated by Starfuel PropertyOS.
        </div>
      </div>
    </div>
  );
}
__EOF__

# ---------------------------------------------------------------
# Add a "PDF report" link to each saved deal card.
cat > app/analyzer/saved/page.tsx << '__EOF__'
import Link from "next/link";
import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";

export default async function SavedDealsPage() {
  const { supabase, orgId, membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";
  const { data: org } = await supabase.from("organizations").select("plan").eq("id", orgId).maybeSingle();
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
                  <div className="text-xs text-neutral-500 mt-2 flex flex-wrap gap-4 items-center">
                    {s.total != null && <span>Cost ${Number(s.total).toLocaleString()}</span>}
                    {s.cfMo != null && <span>Cash flow ${Math.round(s.cfMo).toLocaleString()}/mo</span>}
                    {s.coc != null && <span>CoC {(s.coc * 100).toFixed(1)}%</span>}
                    <span>{new Date(d.created_at).toLocaleDateString()}</span>
                    <Link href={"/analyzer/report/" + d.id} className="text-amber-300 hover:underline ml-auto">PDF report →</Link>
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
echo "  lib/proforma.ts"
echo "  app/analyzer/PrintButton.tsx"
echo "  app/analyzer/report/[id]/page.tsx"
echo "  app/analyzer/saved/page.tsx   (added 'PDF report' link)"
echo ""
echo "No migration. Restart dev server if the new route 404s, then test."
