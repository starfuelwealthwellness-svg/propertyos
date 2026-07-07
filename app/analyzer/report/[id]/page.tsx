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
