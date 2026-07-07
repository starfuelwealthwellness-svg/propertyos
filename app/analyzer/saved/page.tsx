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
