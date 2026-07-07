#!/usr/bin/env bash
# PropertyOS — integrate the Infill Build Analyzer as an in-app page.
# Run from your project root (folder with package.json and app/).
set -e
if [ ! -f package.json ] || [ ! -d app ]; then
  echo "ERROR: run this from your propertyos project root."
  exit 1
fi

echo "Creating folder..."
mkdir -p app/analyzer

echo "Writing files..."

# ---------------------------------------------------------------
cat > app/analyzer/page.tsx << '__EOF__'
import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";
import Analyzer from "./Analyzer";

export default async function AnalyzerPage() {
  const { membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";
  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100">
      <AppHeader orgName={orgName} />
      <main className="max-w-5xl mx-auto px-6 py-8">
        <Analyzer />
      </main>
    </div>
  );
}
__EOF__

# ---------------------------------------------------------------
cat > app/analyzer/Analyzer.tsx << '__EOF__'
"use client";

import { useState } from "react";

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

const input =
  "w-full rounded-md bg-neutral-900 border border-neutral-800 px-3 py-2 text-sm outline-none focus:border-amber-500";
const label = "block text-xs uppercase tracking-wide text-neutral-500 mb-1";

function Line({ k, v, strong, neg }: { k: string; v: string; strong?: boolean; neg?: boolean }) {
  return (
    <div className="flex justify-between items-baseline py-2 border-b border-neutral-800/70 text-sm">
      <span className="text-neutral-400">{k}</span>
      <span className={(strong ? "text-amber-300 font-semibold " : "font-medium ") + (neg ? "text-red-400" : "text-neutral-100")}>{v}</span>
    </div>
  );
}

export default function Analyzer() {
  const [f, setF] = useState({
    planIdx: 10, addr: "1125 E 36th St N, Tulsa, OK", lotSize: "6000", landCost: "15000",
    sqft: "1632", beds: "3", units: "1", buildPsf: "160", softPct: "18", finVal: "",
    downPct: "20", rate: "7.25", term: "30", rentPsf: "1.05", vac: "7", opex: "35", appr: "3", hold: "10",
  });
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
  let pi = 0;
  if (loan > 0) pi = rMo === 0 ? loan / nTot : (loan * rMo * Math.pow(1 + rMo, nTot)) / (Math.pow(1 + rMo, nTot) - 1);
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

  let vClass = "bg-green-500/15 text-green-300 border-green-500/40", vText = "Pencils";
  if (!(cfMo >= 0 && coc >= 0.05)) {
    if (cfMo >= 0) { vClass = "bg-amber-500/15 text-amber-300 border-amber-500/40"; vText = "Tight but positive"; }
    else { vClass = "bg-red-500/15 text-red-300 border-red-500/40"; vText = "Underwater"; }
  }
  const plan = PLANS[f.planIdx];

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

          <div className="rounded-lg border border-amber-500/40 bg-gradient-to-b from-neutral-900 to-neutral-950 p-5">
            <div className="text-xs uppercase tracking-wide text-amber-400 font-semibold">Build-to-own outlook</div>
            <p className="text-lg mt-2 leading-snug">
              {cfMo >= 0
                ? <>Build for about <b className="text-amber-300">{money(total)}</b>, rent at <b className="text-amber-300">{money(rentMo)}/mo</b>, and it puts <b className="text-amber-300">{money(cfMo)}/mo</b> in your pocket. In <b className="text-amber-300">{n("hold")} years</b> you'd hold roughly <b className="text-amber-300">{money(equity)}</b> in equity{instant > 0 ? <> — and about <b className="text-amber-300">{money(instant)}</b> in instant equity the day you finish.</> : "."}</>
                : <>At these numbers it runs <b className="text-red-400">{money(-cfMo)}/mo</b> short after the mortgage. Lower the build cost, land price, or financing — or raise rent — to bring it positive. In <b className="text-amber-300">{n("hold")} years</b> the equity position is about <b className="text-amber-300">{money(equity)}</b>.</>}
            </p>
          </div>

          {/* Pro teaser */}
          <div className="rounded-lg border border-neutral-800 bg-neutral-900 p-5">
            <div className="flex items-center justify-between gap-3">
              <div>
                <div className="text-sm font-semibold text-amber-300">Coming with Pro</div>
                <p className="text-sm text-neutral-400 mt-1">Save deals to a pipeline · Export branded PDF reports · Send deals to your Acquisition Engine.</p>
              </div>
              <button disabled className="shrink-0 rounded-md border border-neutral-700 text-neutral-500 text-sm font-medium px-3 py-2 cursor-not-allowed">Upgrade soon</button>
            </div>
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

# ---------------------------------------------------------------
# Rewrite AppHeader to add the Analyzer nav link.
cat > app/_components/AppHeader.tsx << '__EOF__'
import Link from "next/link";
import { signOut } from "@/app/login/actions";

export default function AppHeader({ orgName }: { orgName: string }) {
  return (
    <header className="border-b border-neutral-800 bg-neutral-950">
      <div className="max-w-6xl mx-auto px-6 py-3 flex items-center justify-between">
        <div className="flex items-center gap-5">
          <span className="font-semibold text-amber-400">PropertyOS</span>
          <nav className="flex gap-4 text-sm text-neutral-300">
            <Link href="/dashboard" className="hover:text-white">Dashboard</Link>
            <Link href="/properties" className="hover:text-white">Properties</Link>
            <Link href="/units" className="hover:text-white">Units</Link>
            <Link href="/tenants" className="hover:text-white">Tenants</Link>
            <Link href="/leases" className="hover:text-white">Leases</Link>
            <Link href="/payments" className="hover:text-white">Payments</Link>
            <Link href="/maintenance" className="hover:text-white">Maintenance</Link>
            <Link href="/vendors" className="hover:text-white">Vendors</Link>
            <Link href="/analyzer" className="hover:text-white text-amber-300">Analyzer</Link>
          </nav>
        </div>
        <div className="flex items-center gap-3 text-sm">
          <span className="text-neutral-400">{orgName}</span>
          <form action={signOut}>
            <button className="text-neutral-400 hover:text-white">Sign out</button>
          </form>
        </div>
      </div>
    </header>
  );
}
__EOF__

echo ""
echo "Done. Files created/updated:"
echo "  app/analyzer/page.tsx"
echo "  app/analyzer/Analyzer.tsx"
echo "  app/_components/AppHeader.tsx  (added Analyzer nav link)"
echo ""
echo "No database changes. Test locally, then commit + push to deploy."
