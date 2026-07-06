#!/usr/bin/env bash
# PropertyOS — Vertical 4 setup: Maintenance (create + list).
# Run this from your project root (the folder with package.json and app/).
set -e

if [ ! -f package.json ] || [ ! -d app ]; then
  echo "ERROR: run this from your propertyos project root (where package.json and app/ live)."
  exit 1
fi

echo "Creating folders..."
mkdir -p app/maintenance/new

echo "Writing files..."

# ---------------------------------------------------------------
cat > app/maintenance/actions.ts << '__EOF__'
"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { requireOrg } from "@/lib/auth";

export async function createMaintenanceRequest(formData: FormData) {
  const { supabase, orgId, user } = await requireOrg();

  const unit_id = String(formData.get("unit_id") || "");
  if (!unit_id) {
    redirect("/maintenance/new?error=" + encodeURIComponent("Please choose a unit"));
  }

  const payload = {
    organization_id: orgId,
    unit_id,
    reported_by: user.id,
    title: String(formData.get("title")),
    description: String(formData.get("description") || "").trim() || null,
    priority: String(formData.get("priority") || "normal"),
    // status defaults to 'open' in the database
  };

  const { error } = await supabase.from("maintenance_requests").insert(payload);
  if (error) redirect("/maintenance/new?error=" + encodeURIComponent(error.message));

  revalidatePath("/maintenance");
  revalidatePath("/dashboard");
  redirect("/maintenance");
}
__EOF__

# ---------------------------------------------------------------
cat > app/maintenance/page.tsx << '__EOF__'
import Link from "next/link";
import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";

const priorityColor: Record<string, string> = {
  low: "text-neutral-400",
  normal: "text-neutral-300",
  high: "text-amber-400",
  emergency: "text-red-400",
};

const statusColor: Record<string, string> = {
  open: "text-amber-400",
  triaged: "text-blue-400",
  assigned: "text-blue-400",
  in_progress: "text-amber-400",
  resolved: "text-green-400",
  closed: "text-neutral-500",
};

export default async function MaintenancePage() {
  const { supabase, membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";

  const { data: requests } = await supabase
    .from("maintenance_requests")
    .select("id, title, priority, status, created_at, units(unit_number, properties(name))")
    .is("deleted_at", null)
    .order("created_at", { ascending: false });

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100">
      <AppHeader orgName={orgName} />
      <main className="max-w-5xl mx-auto px-6 py-8 space-y-6">
        <div className="flex items-center justify-between">
          <h1 className="text-xl font-semibold">Maintenance</h1>
          <Link
            href="/maintenance/new"
            className="rounded-md bg-amber-500 text-neutral-950 text-sm font-medium px-3 py-2 hover:bg-amber-400"
          >
            New request
          </Link>
        </div>

        {!requests || requests.length === 0 ? (
          <p className="text-neutral-400 text-sm">No maintenance requests yet.</p>
        ) : (
          <div className="overflow-hidden rounded-lg border border-neutral-800">
            <table className="w-full text-sm">
              <thead className="bg-neutral-900 text-neutral-400 text-left">
                <tr>
                  <th className="px-4 py-2 font-medium">Request</th>
                  <th className="px-4 py-2 font-medium">Unit</th>
                  <th className="px-4 py-2 font-medium">Priority</th>
                  <th className="px-4 py-2 font-medium">Status</th>
                  <th className="px-4 py-2 font-medium">Reported</th>
                </tr>
              </thead>
              <tbody>
                {requests.map((r: any) => (
                  <tr key={r.id} className="border-t border-neutral-800">
                    <td className="px-4 py-3 font-medium">{r.title}</td>
                    <td className="px-4 py-3 text-neutral-300">
                      {r.units?.properties?.name ?? "—"} · {r.units?.unit_number ?? "—"}
                    </td>
                    <td className={"px-4 py-3 capitalize " + (priorityColor[r.priority] ?? "text-neutral-300")}>
                      {r.priority}
                    </td>
                    <td className={"px-4 py-3 capitalize " + (statusColor[r.status] ?? "text-neutral-400")}>
                      {String(r.status).replace("_", " ")}
                    </td>
                    <td className="px-4 py-3 text-neutral-400">
                      {new Date(r.created_at).toLocaleDateString()}
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
cat > app/maintenance/new/page.tsx << '__EOF__'
import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";
import Link from "next/link";
import { createMaintenanceRequest } from "../actions";

export default async function NewMaintenancePage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { supabase, membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";
  const { error } = await searchParams;

  const { data: units } = await supabase
    .from("units")
    .select("id, unit_number, properties(name)")
    .is("deleted_at", null)
    .order("created_at", { ascending: false });

  const input =
    "w-full rounded-md bg-neutral-900 border border-neutral-800 px-3 py-2 text-sm outline-none focus:border-amber-500";

  const hasUnits = units && units.length > 0;

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100">
      <AppHeader orgName={orgName} />
      <main className="max-w-lg mx-auto px-6 py-8 space-y-6">
        <h1 className="text-xl font-semibold">New maintenance request</h1>
        {error && (
          <p className="text-sm text-red-400 bg-red-950/40 border border-red-900 rounded-md p-3">
            {error}
          </p>
        )}

        {!hasUnits ? (
          <div className="text-sm text-neutral-400 space-y-3">
            <p>You need at least one unit before logging a maintenance request.</p>
            <Link href="/units/new" className="inline-block rounded-md bg-amber-500 text-neutral-950 font-medium px-3 py-2 hover:bg-amber-400">
              Add a unit first
            </Link>
          </div>
        ) : (
          <form action={createMaintenanceRequest} className="space-y-3">
            <label className="block text-xs uppercase tracking-wide text-neutral-500">Unit</label>
            <select name="unit_id" required defaultValue="" className={input}>
              <option value="" disabled>Choose a unit…</option>
              {units!.map((u: any) => (
                <option key={u.id} value={u.id}>
                  {(u.properties?.name ?? "Property")} · {u.unit_number}
                </option>
              ))}
            </select>

            <input name="title" required placeholder="What's wrong? (e.g. Leaking kitchen faucet)" className={input} />

            <textarea
              name="description"
              rows={4}
              placeholder="Details (optional)"
              className={input + " resize-y"}
            />

            <label className="block text-xs uppercase tracking-wide text-neutral-500">Priority</label>
            <select name="priority" defaultValue="normal" className={input}>
              <option value="low">Low</option>
              <option value="normal">Normal</option>
              <option value="high">High</option>
              <option value="emergency">Emergency</option>
            </select>

            <button className="w-full rounded-md bg-amber-500 text-neutral-950 font-medium py-2 text-sm hover:bg-amber-400">
              Submit request
            </button>
          </form>
        )}
      </main>
    </div>
  );
}
__EOF__

# ---------------------------------------------------------------
# Rewrite AppHeader to add the Maintenance nav link.
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
            <Link href="/tenants" className="hover:text-white">Tenants</Link>
            <Link href="/leases" className="hover:text-white">Leases</Link>
            <Link href="/maintenance" className="hover:text-white">Maintenance</Link>
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
echo "  app/maintenance/(page.tsx, new/page.tsx, actions.ts)"
echo "  app/_components/AppHeader.tsx   (added Maintenance nav link)"
echo ""
echo "No database changes needed. Just make sure the dev server is running, then open /maintenance."
