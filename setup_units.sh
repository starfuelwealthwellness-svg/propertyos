#!/usr/bin/env bash
# PropertyOS — Vertical 2 setup: Units (flat page + property dropdown).
# Run this from your project root (the folder with package.json and app/).
set -e

if [ ! -f package.json ] || [ ! -d app ]; then
  echo "ERROR: run this from your propertyos project root (where package.json and app/ live)."
  exit 1
fi

echo "Creating folders..."
mkdir -p app/units/new

echo "Writing files..."

# ---------------------------------------------------------------
cat > app/units/actions.ts << '__EOF__'
"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { requireOrg } from "@/lib/auth";

function numOrNull(v: FormDataEntryValue | null) {
  const s = String(v ?? "").trim();
  if (s === "") return null;
  const n = Number(s);
  return Number.isNaN(n) ? null : n;
}

export async function createUnit(formData: FormData) {
  const { supabase, orgId } = await requireOrg();

  const property_id = String(formData.get("property_id") || "");
  if (!property_id) {
    redirect("/units/new?error=" + encodeURIComponent("Please choose a property"));
  }

  const payload = {
    organization_id: orgId,
    property_id,
    unit_number: String(formData.get("unit_number")),
    bedrooms: numOrNull(formData.get("bedrooms")),
    bathrooms: numOrNull(formData.get("bathrooms")),
    square_feet: numOrNull(formData.get("square_feet")),
    market_rent: numOrNull(formData.get("market_rent")),
    status: String(formData.get("status") || "vacant"),
  };

  const { error } = await supabase.from("units").insert(payload);
  if (error) redirect("/units/new?error=" + encodeURIComponent(error.message));

  revalidatePath("/units");
  redirect("/units");
}
__EOF__

# ---------------------------------------------------------------
cat > app/units/page.tsx << '__EOF__'
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
__EOF__

# ---------------------------------------------------------------
cat > app/units/new/page.tsx << '__EOF__'
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
__EOF__

# ---------------------------------------------------------------
# Update AppHeader to add a "Units" nav link (rewrite the file).
cat > app/_components/AppHeader.tsx << '__EOF__'
import Link from "next/link";
import { signOut } from "@/app/login/actions";

export default function AppHeader({ orgName }: { orgName: string }) {
  return (
    <header className="border-b border-neutral-800 bg-neutral-950">
      <div className="max-w-5xl mx-auto px-6 py-3 flex items-center justify-between">
        <div className="flex items-center gap-6">
          <span className="font-semibold text-amber-400">PropertyOS</span>
          <nav className="flex gap-4 text-sm text-neutral-300">
            <Link href="/dashboard" className="hover:text-white">Dashboard</Link>
            <Link href="/properties" className="hover:text-white">Properties</Link>
            <Link href="/units" className="hover:text-white">Units</Link>
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
echo "  app/units/page.tsx"
echo "  app/units/new/page.tsx"
echo "  app/units/actions.ts"
echo "  app/_components/AppHeader.tsx  (added Units nav link)"
echo ""
echo "No database changes needed — the units table and its RLS already exist."
echo "Just make sure the dev server is running, then open /units."
