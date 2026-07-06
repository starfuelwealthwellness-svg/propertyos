import Link from "next/link";
import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";

const statusColor: Record<string, string> = {
  vacant: "text-neutral-400",
  occupied: "text-green-400",
  maintenance: "text-amber-400",
  offline: "text-red-400",
};

export default async function UnitsPage() {
  const { supabase, membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";

  const { data: units } = await supabase
    .from("units")
    .select("id, unit_number, bedrooms, bathrooms, market_rent, status, properties(name)")
    .is("deleted_at", null)
    .order("created_at", { ascending: false });

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100">
      <AppHeader orgName={orgName} />
      <main className="max-w-5xl mx-auto px-6 py-8 space-y-6">
        <div className="flex items-center justify-between">
          <h1 className="text-xl font-semibold">Units</h1>
          <Link
            href="/units/new"
            className="rounded-md bg-amber-500 text-neutral-950 text-sm font-medium px-3 py-2 hover:bg-amber-400"
          >
            Add unit
          </Link>
        </div>

        {!units || units.length === 0 ? (
          <p className="text-neutral-400 text-sm">No units yet. Add your first one.</p>
        ) : (
          <div className="overflow-hidden rounded-lg border border-neutral-800">
            <table className="w-full text-sm">
              <thead className="bg-neutral-900 text-neutral-400 text-left">
                <tr>
                  <th className="px-4 py-2 font-medium">Unit</th>
                  <th className="px-4 py-2 font-medium">Property</th>
                  <th className="px-4 py-2 font-medium">Bed / Bath</th>
                  <th className="px-4 py-2 font-medium">Market rent</th>
                  <th className="px-4 py-2 font-medium">Status</th>
                </tr>
              </thead>
              <tbody>
                {units.map((u: any) => (
                  <tr key={u.id} className="border-t border-neutral-800">
                    <td className="px-4 py-3 font-medium">{u.unit_number}</td>
                    <td className="px-4 py-3 text-neutral-300">{u.properties?.name ?? "—"}</td>
                    <td className="px-4 py-3 text-neutral-300">
                      {u.bedrooms ?? "—"} / {u.bathrooms ?? "—"}
                    </td>
                    <td className="px-4 py-3 text-neutral-300">
                      {u.market_rent != null ? "$" + Number(u.market_rent).toLocaleString() : "—"}
                    </td>
                    <td className={"px-4 py-3 capitalize " + (statusColor[u.status] ?? "text-neutral-400")}>
                      {u.status}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </main>
    </div>
  );
}
