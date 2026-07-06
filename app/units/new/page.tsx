import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";
import Link from "next/link";
import { createUnit } from "../actions";

export default async function NewUnitPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { supabase, membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";
  const { error } = await searchParams;

  const { data: properties } = await supabase
    .from("properties")
    .select("id, name")
    .is("deleted_at", null)
    .order("name", { ascending: true });

  const input =
    "w-full rounded-md bg-neutral-900 border border-neutral-800 px-3 py-2 text-sm outline-none focus:border-amber-500";

  const hasProperties = properties && properties.length > 0;

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100">
      <AppHeader orgName={orgName} />
      <main className="max-w-lg mx-auto px-6 py-8 space-y-6">
        <h1 className="text-xl font-semibold">Add unit</h1>
        {error && (
          <p className="text-sm text-red-400 bg-red-950/40 border border-red-900 rounded-md p-3">
            {error}
          </p>
        )}

        {!hasProperties ? (
          <div className="text-sm text-neutral-400 space-y-3">
            <p>You need at least one property before adding a unit.</p>
            <Link
              href="/properties/new"
              className="inline-block rounded-md bg-amber-500 text-neutral-950 font-medium px-3 py-2 hover:bg-amber-400"
            >
              Add a property first
            </Link>
          </div>
        ) : (
          <form action={createUnit} className="space-y-3">
            <label className="block text-xs uppercase tracking-wide text-neutral-500">Property</label>
            <select name="property_id" required defaultValue="" className={input}>
              <option value="" disabled>Choose a property…</option>
              {properties!.map((p: any) => (
                <option key={p.id} value={p.id}>{p.name}</option>
              ))}
            </select>

            <input name="unit_number" required placeholder="Unit number (e.g. 1A)" className={input} />

            <div className="grid grid-cols-2 gap-3">
              <input name="bedrooms" type="number" min="0" step="1" placeholder="Bedrooms" className={input} />
              <input name="bathrooms" type="number" min="0" step="0.5" placeholder="Bathrooms" className={input} />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <input name="square_feet" type="number" min="0" step="1" placeholder="Square feet" className={input} />
              <input name="market_rent" type="number" min="0" step="0.01" placeholder="Market rent ($)" className={input} />
            </div>

            <select name="status" defaultValue="vacant" className={input}>
              <option value="vacant">Vacant</option>
              <option value="occupied">Occupied</option>
              <option value="maintenance">Maintenance</option>
              <option value="offline">Offline</option>
            </select>

            <button className="w-full rounded-md bg-amber-500 text-neutral-950 font-medium py-2 text-sm hover:bg-amber-400">
              Save unit
            </button>
          </form>
        )}
      </main>
    </div>
  );
}
