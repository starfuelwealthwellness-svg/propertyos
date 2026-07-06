import Link from "next/link";
import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";

function tenantName(row: any): string {
  const lt = row.lease_tenants as any[] | undefined;
  if (!lt || lt.length === 0) return "—";
  const primary = lt.find((x) => x.is_primary) ?? lt[0];
  return primary?.tenants?.full_name ?? "—";
}

export default async function LeasesPage() {
  const { supabase, membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";

  const { data: leases } = await supabase
    .from("leases")
    .select(
      "id, start_date, end_date, rent_amount, status, units(unit_number, properties(name)), lease_tenants(is_primary, tenants(full_name))"
    )
    .is("deleted_at", null)
    .order("created_at", { ascending: false });

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100">
      <AppHeader orgName={orgName} />
      <main className="max-w-5xl mx-auto px-6 py-8 space-y-6">
        <div className="flex items-center justify-between">
          <h1 className="text-xl font-semibold">Leases</h1>
          <Link
            href="/leases/new"
            className="rounded-md bg-amber-500 text-neutral-950 text-sm font-medium px-3 py-2 hover:bg-amber-400"
          >
            New lease
          </Link>
        </div>

        {!leases || leases.length === 0 ? (
          <p className="text-neutral-400 text-sm">No leases yet. Create your first one.</p>
        ) : (
          <div className="overflow-hidden rounded-lg border border-neutral-800">
            <table className="w-full text-sm">
              <thead className="bg-neutral-900 text-neutral-400 text-left">
                <tr>
                  <th className="px-4 py-2 font-medium">Tenant</th>
                  <th className="px-4 py-2 font-medium">Unit</th>
                  <th className="px-4 py-2 font-medium">Rent</th>
                  <th className="px-4 py-2 font-medium">Term</th>
                  <th className="px-4 py-2 font-medium">Status</th>
                </tr>
              </thead>
              <tbody>
                {leases.map((l: any) => (
                  <tr key={l.id} className="border-t border-neutral-800">
                    <td className="px-4 py-3 font-medium">{tenantName(l)}</td>
                    <td className="px-4 py-3 text-neutral-300">
                      {l.units?.properties?.name ?? "—"} · {l.units?.unit_number ?? "—"}
                    </td>
                    <td className="px-4 py-3 text-neutral-300">
                      {l.rent_amount != null ? "$" + Number(l.rent_amount).toLocaleString() : "—"}
                    </td>
                    <td className="px-4 py-3 text-neutral-300">
                      {l.start_date}{l.end_date ? " → " + l.end_date : " → open"}
                    </td>
                    <td className="px-4 py-3 capitalize text-green-400">{l.status}</td>
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
