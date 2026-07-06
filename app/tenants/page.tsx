import Link from "next/link";
import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";

export default async function TenantsPage() {
  const { supabase, membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";

  const { data: tenants } = await supabase
    .from("tenants")
    .select("id, full_name, email, phone")
    .is("deleted_at", null)
    .order("created_at", { ascending: false });

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100">
      <AppHeader orgName={orgName} />
      <main className="max-w-5xl mx-auto px-6 py-8 space-y-6">
        <div className="flex items-center justify-between">
          <h1 className="text-xl font-semibold">Tenants</h1>
          <Link
            href="/tenants/new"
            className="rounded-md bg-amber-500 text-neutral-950 text-sm font-medium px-3 py-2 hover:bg-amber-400"
          >
            Add tenant
          </Link>
        </div>

        {!tenants || tenants.length === 0 ? (
          <p className="text-neutral-400 text-sm">No tenants yet. Add your first one.</p>
        ) : (
          <div className="overflow-hidden rounded-lg border border-neutral-800">
            <table className="w-full text-sm">
              <thead className="bg-neutral-900 text-neutral-400 text-left">
                <tr>
                  <th className="px-4 py-2 font-medium">Name</th>
                  <th className="px-4 py-2 font-medium">Email</th>
                  <th className="px-4 py-2 font-medium">Phone</th>
                </tr>
              </thead>
              <tbody>
                {tenants.map((t: any) => (
                  <tr key={t.id} className="border-t border-neutral-800">
                    <td className="px-4 py-3 font-medium">{t.full_name}</td>
                    <td className="px-4 py-3 text-neutral-300">{t.email ?? "—"}</td>
                    <td className="px-4 py-3 text-neutral-300">{t.phone ?? "—"}</td>
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
