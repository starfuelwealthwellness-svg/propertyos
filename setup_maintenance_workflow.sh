#!/usr/bin/env bash
# PropertyOS — Vertical 5 setup: maintenance workflow + vendors + double-submit fix.
# Run this from your project root (the folder with package.json and app/).
set -e

if [ ! -f package.json ] || [ ! -d app ]; then
  echo "ERROR: run this from your propertyos project root (where package.json and app/ live)."
  exit 1
fi

echo "Creating folders..."
mkdir -p app/vendors/new "app/maintenance/[id]"

echo "Writing files..."

# ---------------------------------------------------------------
# Reusable submit button that disables itself while the form is
# submitting — this is the fix for the double-submit duplicate.
cat > app/_components/SubmitButton.tsx << '__EOF__'
"use client";

import { useFormStatus } from "react-dom";

export default function SubmitButton({
  children,
  className = "",
  pendingText = "Working…",
}: {
  children: React.ReactNode;
  className?: string;
  pendingText?: string;
}) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      aria-disabled={pending}
      className={className + (pending ? " opacity-60 cursor-not-allowed" : "")}
    >
      {pending ? pendingText : children}
    </button>
  );
}
__EOF__

# ---------------------------------------------------------------
cat > app/vendors/actions.ts << '__EOF__'
"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { requireOrg } from "@/lib/auth";

export async function createVendor(formData: FormData) {
  const { supabase, orgId } = await requireOrg();
  const payload = {
    organization_id: orgId,
    name: String(formData.get("name")),
    trade: String(formData.get("trade") || "").trim() || null,
    email: String(formData.get("email") || "").trim() || null,
    phone: String(formData.get("phone") || "").trim() || null,
  };
  const { error } = await supabase.from("vendors").insert(payload);
  if (error) redirect("/vendors/new?error=" + encodeURIComponent(error.message));
  revalidatePath("/vendors");
  redirect("/vendors");
}
__EOF__

# ---------------------------------------------------------------
cat > app/vendors/page.tsx << '__EOF__'
import Link from "next/link";
import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";

export default async function VendorsPage() {
  const { supabase, membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";

  const { data: vendors } = await supabase
    .from("vendors")
    .select("id, name, trade, email, phone")
    .is("deleted_at", null)
    .order("created_at", { ascending: false });

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100">
      <AppHeader orgName={orgName} />
      <main className="max-w-5xl mx-auto px-6 py-8 space-y-6">
        <div className="flex items-center justify-between">
          <h1 className="text-xl font-semibold">Vendors</h1>
          <Link
            href="/vendors/new"
            className="rounded-md bg-amber-500 text-neutral-950 text-sm font-medium px-3 py-2 hover:bg-amber-400"
          >
            Add vendor
          </Link>
        </div>

        {!vendors || vendors.length === 0 ? (
          <p className="text-neutral-400 text-sm">No vendors yet. Add your first one.</p>
        ) : (
          <div className="overflow-hidden rounded-lg border border-neutral-800">
            <table className="w-full text-sm">
              <thead className="bg-neutral-900 text-neutral-400 text-left">
                <tr>
                  <th className="px-4 py-2 font-medium">Name</th>
                  <th className="px-4 py-2 font-medium">Trade</th>
                  <th className="px-4 py-2 font-medium">Email</th>
                  <th className="px-4 py-2 font-medium">Phone</th>
                </tr>
              </thead>
              <tbody>
                {vendors.map((v: any) => (
                  <tr key={v.id} className="border-t border-neutral-800">
                    <td className="px-4 py-3 font-medium">{v.name}</td>
                    <td className="px-4 py-3 text-neutral-300 capitalize">{v.trade ?? "—"}</td>
                    <td className="px-4 py-3 text-neutral-300">{v.email ?? "—"}</td>
                    <td className="px-4 py-3 text-neutral-300">{v.phone ?? "—"}</td>
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
cat > app/vendors/new/page.tsx << '__EOF__'
import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";
import SubmitButton from "@/app/_components/SubmitButton";
import { createVendor } from "../actions";

export default async function NewVendorPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";
  const { error } = await searchParams;
  const input =
    "w-full rounded-md bg-neutral-900 border border-neutral-800 px-3 py-2 text-sm outline-none focus:border-amber-500";

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100">
      <AppHeader orgName={orgName} />
      <main className="max-w-lg mx-auto px-6 py-8 space-y-6">
        <h1 className="text-xl font-semibold">Add vendor</h1>
        {error && (
          <p className="text-sm text-red-400 bg-red-950/40 border border-red-900 rounded-md p-3">
            {error}
          </p>
        )}
        <form action={createVendor} className="space-y-3">
          <input name="name" required placeholder="Vendor name" className={input} />
          <input name="trade" placeholder="Trade (e.g. plumbing, electrical)" className={input} />
          <input name="email" type="email" placeholder="Email (optional)" className={input} />
          <input name="phone" type="tel" placeholder="Phone (optional)" className={input} />
          <SubmitButton className="w-full rounded-md bg-amber-500 text-neutral-950 font-medium py-2 text-sm hover:bg-amber-400">
            Save vendor
          </SubmitButton>
        </form>
      </main>
    </div>
  );
}
__EOF__

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
  };
  const { error } = await supabase.from("maintenance_requests").insert(payload);
  if (error) redirect("/maintenance/new?error=" + encodeURIComponent(error.message));
  revalidatePath("/maintenance");
  revalidatePath("/dashboard");
  redirect("/maintenance");
}

export async function updateMaintenanceStatus(formData: FormData) {
  const { supabase } = await requireOrg();
  const id = String(formData.get("id"));
  const status = String(formData.get("status"));
  const { error } = await supabase
    .from("maintenance_requests")
    .update({ status })
    .eq("id", id);
  if (error) redirect("/maintenance/" + id + "?error=" + encodeURIComponent(error.message));
  revalidatePath("/maintenance/" + id);
  revalidatePath("/maintenance");
  revalidatePath("/dashboard");
  redirect("/maintenance/" + id);
}

export async function assignVendor(formData: FormData) {
  const { supabase } = await requireOrg();
  const id = String(formData.get("id"));
  const vendor_id = String(formData.get("vendor_id") || "").trim() || null;

  const update: { assigned_vendor: string | null; status?: string } = {
    assigned_vendor: vendor_id,
  };

  // If we just assigned a vendor and the ticket is still early-stage,
  // nudge it forward to 'assigned'.
  if (vendor_id) {
    const { data: cur } = await supabase
      .from("maintenance_requests")
      .select("status")
      .eq("id", id)
      .maybeSingle();
    if (cur && (cur.status === "open" || cur.status === "triaged")) {
      update.status = "assigned";
    }
  }

  const { error } = await supabase
    .from("maintenance_requests")
    .update(update)
    .eq("id", id);
  if (error) redirect("/maintenance/" + id + "?error=" + encodeURIComponent(error.message));
  revalidatePath("/maintenance/" + id);
  revalidatePath("/maintenance");
  revalidatePath("/dashboard");
  redirect("/maintenance/" + id);
}

export async function deleteRequest(formData: FormData) {
  const { supabase } = await requireOrg();
  const id = String(formData.get("id"));
  const { error } = await supabase
    .from("maintenance_requests")
    .update({ deleted_at: new Date().toISOString() })
    .eq("id", id);
  if (error) redirect("/maintenance/" + id + "?error=" + encodeURIComponent(error.message));
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
                  <th className="px-4 py-2 font-medium"></th>
                </tr>
              </thead>
              <tbody>
                {requests.map((r: any) => (
                  <tr key={r.id} className="border-t border-neutral-800 hover:bg-neutral-900/50">
                    <td className="px-4 py-3 font-medium">
                      <Link href={"/maintenance/" + r.id} className="text-amber-300 hover:underline">
                        {r.title}
                      </Link>
                    </td>
                    <td className="px-4 py-3 text-neutral-300">
                      {r.units?.properties?.name ?? "—"} · {r.units?.unit_number ?? "—"}
                    </td>
                    <td className={"px-4 py-3 capitalize " + (priorityColor[r.priority] ?? "text-neutral-300")}>
                      {r.priority}
                    </td>
                    <td className={"px-4 py-3 capitalize " + (statusColor[r.status] ?? "text-neutral-400")}>
                      {String(r.status).replace("_", " ")}
                    </td>
                    <td className="px-4 py-3 text-right">
                      <Link href={"/maintenance/" + r.id} className="text-neutral-400 hover:text-white">
                        View →
                      </Link>
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
cat > "app/maintenance/[id]/page.tsx" << '__EOF__'
import Link from "next/link";
import { redirect } from "next/navigation";
import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";
import SubmitButton from "@/app/_components/SubmitButton";
import { updateMaintenanceStatus, assignVendor, deleteRequest } from "../actions";

const STATUSES = ["open", "triaged", "assigned", "in_progress", "resolved", "closed"];

export default async function MaintenanceDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ error?: string }>;
}) {
  const { id } = await params;
  const { error } = await searchParams;
  const { supabase, membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";

  const { data: req } = await supabase
    .from("maintenance_requests")
    .select(
      "id, title, description, priority, status, created_at, assigned_vendor, units(unit_number, properties(name)), vendors(name)"
    )
    .eq("id", id)
    .is("deleted_at", null)
    .maybeSingle();

  if (!req) redirect("/maintenance");

  const { data: vendors } = await supabase
    .from("vendors")
    .select("id, name")
    .is("deleted_at", null)
    .order("name", { ascending: true });

  const input =
    "w-full rounded-md bg-neutral-900 border border-neutral-800 px-3 py-2 text-sm outline-none focus:border-amber-500";
  const r = req as any;

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100">
      <AppHeader orgName={orgName} />
      <main className="max-w-3xl mx-auto px-6 py-8 space-y-6">
        <div className="flex items-center gap-3 text-sm text-neutral-400">
          <Link href="/maintenance" className="hover:text-white">← Maintenance</Link>
        </div>

        {error && (
          <p className="text-sm text-red-400 bg-red-950/40 border border-red-900 rounded-md p-3">
            {error}
          </p>
        )}

        <div className="space-y-2">
          <h1 className="text-2xl font-semibold">{r.title}</h1>
          <p className="text-sm text-neutral-400">
            {r.units?.properties?.name ?? "—"} · Unit {r.units?.unit_number ?? "—"} ·
            {" "}Reported {new Date(r.created_at).toLocaleDateString()}
          </p>
        </div>

        <div className="rounded-lg border border-neutral-800 bg-neutral-900 p-5 space-y-3">
          <div className="text-xs uppercase tracking-wide text-neutral-500">Details</div>
          <p className="text-sm text-neutral-200 whitespace-pre-wrap">
            {r.description || "No description provided."}
          </p>
          <div className="flex gap-6 text-sm pt-2">
            <span><span className="text-neutral-500">Priority:</span> <span className="capitalize">{r.priority}</span></span>
            <span><span className="text-neutral-500">Vendor:</span> {r.vendors?.name ?? "Unassigned"}</span>
          </div>
        </div>

        <div className="grid sm:grid-cols-2 gap-4">
          <div className="rounded-lg border border-neutral-800 bg-neutral-900 p-5 space-y-3">
            <div className="text-xs uppercase tracking-wide text-neutral-500">Status</div>
            <form action={updateMaintenanceStatus} className="space-y-3">
              <input type="hidden" name="id" value={r.id} />
              <select name="status" defaultValue={r.status} className={input}>
                {STATUSES.map((s) => (
                  <option key={s} value={s}>{s.replace("_", " ")}</option>
                ))}
              </select>
              <SubmitButton className="w-full rounded-md bg-amber-500 text-neutral-950 font-medium py-2 text-sm hover:bg-amber-400">
                Update status
              </SubmitButton>
            </form>
          </div>

          <div className="rounded-lg border border-neutral-800 bg-neutral-900 p-5 space-y-3">
            <div className="text-xs uppercase tracking-wide text-neutral-500">Vendor</div>
            {!vendors || vendors.length === 0 ? (
              <div className="text-sm text-neutral-400 space-y-2">
                <p>No vendors yet.</p>
                <Link href="/vendors/new" className="inline-block rounded-md border border-amber-500 text-amber-400 font-medium px-3 py-2 hover:bg-amber-500/10">
                  Add a vendor
                </Link>
              </div>
            ) : (
              <form action={assignVendor} className="space-y-3">
                <input type="hidden" name="id" value={r.id} />
                <select name="vendor_id" defaultValue={r.assigned_vendor ?? ""} className={input}>
                  <option value="">— Unassigned —</option>
                  {vendors.map((v: any) => (
                    <option key={v.id} value={v.id}>{v.name}</option>
                  ))}
                </select>
                <SubmitButton className="w-full rounded-md bg-amber-500 text-neutral-950 font-medium py-2 text-sm hover:bg-amber-400">
                  Assign vendor
                </SubmitButton>
              </form>
            )}
          </div>
        </div>

        <div className="border-t border-neutral-800 pt-5">
          <form action={deleteRequest}>
            <input type="hidden" name="id" value={r.id} />
            <SubmitButton
              pendingText="Deleting…"
              className="rounded-md border border-red-900 text-red-400 text-sm font-medium px-3 py-2 hover:bg-red-950/40"
            >
              Delete request
            </SubmitButton>
          </form>
          <p className="text-xs text-neutral-600 mt-2">
            Removes it from your list. (Use this to clear the duplicate ticket.)
          </p>
        </div>
      </main>
    </div>
  );
}
__EOF__

# ---------------------------------------------------------------
# Rewrite the maintenance "new" form to use SubmitButton (double-submit fix).
cat > app/maintenance/new/page.tsx << '__EOF__'
import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";
import SubmitButton from "@/app/_components/SubmitButton";
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

            <textarea name="description" rows={4} placeholder="Details (optional)" className={input + " resize-y"} />

            <label className="block text-xs uppercase tracking-wide text-neutral-500">Priority</label>
            <select name="priority" defaultValue="normal" className={input}>
              <option value="low">Low</option>
              <option value="normal">Normal</option>
              <option value="high">High</option>
              <option value="emergency">Emergency</option>
            </select>

            <SubmitButton className="w-full rounded-md bg-amber-500 text-neutral-950 font-medium py-2 text-sm hover:bg-amber-400">
              Submit request
            </SubmitButton>
          </form>
        )}
      </main>
    </div>
  );
}
__EOF__

# ---------------------------------------------------------------
# Rewrite AppHeader to add the Vendors nav link.
cat > app/_components/AppHeader.tsx << '__EOF__'
import Link from "next/link";
import { signOut } from "@/app/login/actions";

export default function AppHeader({ orgName }: { orgName: string }) {
  return (
    <header className="border-b border-neutral-800 bg-neutral-950">
      <div className="max-w-6xl mx-auto px-6 py-3 flex items-center justify-between">
        <div className="flex items-center gap-6">
          <span className="font-semibold text-amber-400">PropertyOS</span>
          <nav className="flex gap-4 text-sm text-neutral-300">
            <Link href="/dashboard" className="hover:text-white">Dashboard</Link>
            <Link href="/properties" className="hover:text-white">Properties</Link>
            <Link href="/units" className="hover:text-white">Units</Link>
            <Link href="/tenants" className="hover:text-white">Tenants</Link>
            <Link href="/leases" className="hover:text-white">Leases</Link>
            <Link href="/maintenance" className="hover:text-white">Maintenance</Link>
            <Link href="/vendors" className="hover:text-white">Vendors</Link>
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

# ---------------------------------------------------------------
# Rewrite dashboard so the stat cards link to their sections.
cat > app/dashboard/page.tsx << '__EOF__'
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
__EOF__

echo ""
echo "Done. Files created/updated:"
echo "  app/_components/SubmitButton.tsx        (double-submit fix)"
echo "  app/vendors/(page.tsx, new/page.tsx, actions.ts)"
echo "  app/maintenance/[id]/page.tsx           (detail + status + vendor + delete)"
echo "  app/maintenance/(page.tsx, new/page.tsx, actions.ts)"
echo "  app/_components/AppHeader.tsx           (added Vendors nav)"
echo "  app/dashboard/page.tsx                  (clickable stat cards)"
echo ""
echo "No database changes. Make sure the dev server is running, then open /maintenance."
