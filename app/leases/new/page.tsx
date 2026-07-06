import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";
import Link from "next/link";
import { createLease } from "../actions";

export default async function NewLeasePage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { supabase, membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";
  const { error } = await searchParams;

  const [{ data: units }, { data: tenants }] = await Promise.all([
    supabase
      .from("units")
      .select("id, unit_number, status, properties(name)")
      .is("deleted_at", null)
      .order("created_at", { ascending: false }),
    supabase
      .from("tenants")
      .select("id, full_name")
      .is("deleted_at", null)
      .order("full_name", { ascending: true }),
  ]);

  const input =
    "w-full rounded-md bg-neutral-900 border border-neutral-800 px-3 py-2 text-sm outline-none focus:border-amber-500";

  const ready = units && units.length > 0 && tenants && tenants.length > 0;

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100">
      <AppHeader orgName={orgName} />
      <main className="max-w-lg mx-auto px-6 py-8 space-y-6">
        <h1 className="text-xl font-semibold">New lease</h1>
        {error && (
          <p className="text-sm text-red-400 bg-red-950/40 border border-red-900 rounded-md p-3">
            {error}
          </p>
        )}

        {!ready ? (
          <div className="text-sm text-neutral-400 space-y-3">
            <p>A lease needs at least one unit and one tenant.</p>
            <div className="flex gap-2">
              {(!units || units.length === 0) && (
                <Link href="/units/new" className="rounded-md bg-amber-500 text-neutral-950 font-medium px-3 py-2 hover:bg-amber-400">
                  Add a unit
                </Link>
              )}
              {(!tenants || tenants.length === 0) && (
                <Link href="/tenants/new" className="rounded-md border border-amber-500 text-amber-400 font-medium px-3 py-2 hover:bg-amber-500/10">
                  Add a tenant
                </Link>
              )}
            </div>
          </div>
        ) : (
          <form action={createLease} className="space-y-3">
            <label className="block text-xs uppercase tracking-wide text-neutral-500">Unit</label>
            <select name="unit_id" required defaultValue="" className={input}>
              <option value="" disabled>Choose a unit…</option>
              {units!.map((u: any) => (
                <option key={u.id} value={u.id}>
                  {(u.properties?.name ?? "Property")} · {u.unit_number} ({u.status})
                </option>
              ))}
            </select>

            <label className="block text-xs uppercase tracking-wide text-neutral-500">Tenant</label>
            <select name="tenant_id" required defaultValue="" className={input}>
              <option value="" disabled>Choose a tenant…</option>
              {tenants!.map((t: any) => (
                <option key={t.id} value={t.id}>{t.full_name}</option>
              ))}
            </select>

            <div className="grid grid-cols-2 gap-3">
              <input name="rent_amount" type="number" min="0" step="0.01" required placeholder="Monthly rent ($)" className={input} />
              <input name="deposit_amount" type="number" min="0" step="0.01" placeholder="Deposit ($)" className={input} />
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs uppercase tracking-wide text-neutral-500 mb-1">Start date</label>
                <input name="start_date" type="date" required className={input} />
              </div>
              <div>
                <label className="block text-xs uppercase tracking-wide text-neutral-500 mb-1">End date (optional)</label>
                <input name="end_date" type="date" className={input} />
              </div>
            </div>

            <button className="w-full rounded-md bg-amber-500 text-neutral-950 font-medium py-2 text-sm hover:bg-amber-400">
              Create lease
            </button>
          </form>
        )}
      </main>
    </div>
  );
}
