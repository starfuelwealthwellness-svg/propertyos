import Link from "next/link";
import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";

export default async function PropertiesPage() {
  const { supabase, membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";

  const { data: properties } = await supabase
    .from("properties")
    .select("id, name, address_line1, city, state, property_type")
    .is("deleted_at", null)
    .order("created_at", { ascending: false });

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100">
      <AppHeader orgName={orgName} />
      <main className="max-w-5xl mx-auto px-6 py-8 space-y-6">
        <div className="flex items-center justify-between">
          <h1 className="text-xl font-semibold">Properties</h1>
          <Link
            href="/properties/new"
            className="rounded-md bg-amber-500 text-neutral-950 text-sm font-medium px-3 py-2 hover:bg-amber-400"
          >
            Add property
          </Link>
        </div>

        {!properties || properties.length === 0 ? (
          <p className="text-neutral-400 text-sm">No properties yet. Add your first one.</p>
        ) : (
          <div className="grid gap-3">
            {properties.map((p: any) => (
              <div key={p.id} className="rounded-lg border border-neutral-800 bg-neutral-900 p-4">
                <div className="font-medium">{p.name}</div>
                <div className="text-sm text-neutral-400">
                  {p.address_line1}, {p.city}, {p.state}
                </div>
                <div className="text-xs text-amber-400/80 mt-1 uppercase tracking-wide">
                  {String(p.property_type).replace("_", " ")}
                </div>
              </div>
            ))}
          </div>
        )}
      </main>
    </div>
  );
}
