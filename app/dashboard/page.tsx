import Link from "next/link";
import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";

function Stat({ label, value, href }: { label: string; value: number; href?: string }) {
  const card = (
    <div className="rounded-lg border border-neutral-800 bg-neutral-900 p-5 hover:border-neutral-600 transition-colors">
      <div className="text-3xl font-semibold">{value}</div>
      <div className="text-sm text-neutral-400 mt-1">{label}</div>
    </div>
  );
  return href ? <Link href={href}>{card}</Link> : card;
}

export default async function DashboardPage() {
  const { supabase, membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";

  const results = await Promise.all([
    supabase.from("properties").select("*", { count: "exact", head: true }).is("deleted_at", null),
    supabase.from("units").select("*", { count: "exact", head: true }).is("deleted_at", null),
    supabase.from("leases").select("*", { count: "exact", head: true }).is("deleted_at", null).eq("status", "active"),
    supabase
      .from("maintenance_requests")
      .select("*", { count: "exact", head: true })
      .is("deleted_at", null)
      .neq("status", "closed"),
  ]);
  const [properties, units, activeLeases, openReqs] = results.map((r) => r.count ?? 0);

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100">
      <AppHeader orgName={orgName} />
      <main className="max-w-5xl mx-auto px-6 py-8 space-y-6">
        <div className="flex items-center justify-between">
          <h1 className="text-xl font-semibold">Dashboard</h1>
          <Link
            href="/properties/new"
            className="rounded-md bg-amber-500 text-neutral-950 text-sm font-medium px-3 py-2 hover:bg-amber-400"
          >
            Add property
          </Link>
        </div>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
          <Stat label="Properties" value={properties} href="/properties" />
          <Stat label="Units" value={units} href="/units" />
          <Stat label="Active leases" value={activeLeases} href="/leases" />
          <Stat label="Open maintenance" value={openReqs} href="/maintenance" />
        </div>
      </main>
    </div>
  );
}
