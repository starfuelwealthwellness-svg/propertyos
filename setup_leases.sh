#!/usr/bin/env bash
# PropertyOS — Vertical 3 setup: Tenants + Leases.
# Run this from your project root (the folder with package.json and app/).
set -e

if [ ! -f package.json ] || [ ! -d app ]; then
  echo "ERROR: run this from your propertyos project root (where package.json and app/ live)."
  exit 1
fi

echo "Creating folders..."
mkdir -p app/tenants/new app/leases/new supabase/migrations

echo "Writing files..."

# ---------------------------------------------------------------
cat > supabase/migrations/0004_leases.sql << '__EOF__'
-- PropertyOS — 0004_leases.sql
-- create_lease: atomically create a lease, link a tenant via the
-- lease_tenants join table, and flip the unit to 'occupied'.
-- SECURITY INVOKER (default): RLS still applies, so a user can only
-- ever do this within their own org. The whole function is one
-- transaction, so all three writes succeed together or not at all.

create or replace function create_lease(
  p_unit_id uuid,
  p_tenant_id uuid,
  p_rent numeric,
  p_deposit numeric,
  p_start date,
  p_end date
)
returns uuid
language plpgsql
as $$
declare
  v_org uuid;
  v_tenant_org uuid;
  v_lease_id uuid;
begin
  -- RLS makes these selects return NULL if the rows aren't in the
  -- caller's org, which doubles as an ownership check.
  select organization_id into v_org
  from units where id = p_unit_id and deleted_at is null;
  if v_org is null then
    raise exception 'Unit not found or not accessible';
  end if;

  select organization_id into v_tenant_org
  from tenants where id = p_tenant_id and deleted_at is null;
  if v_tenant_org is null or v_tenant_org <> v_org then
    raise exception 'Tenant not found in the same organization';
  end if;

  insert into leases (organization_id, unit_id, start_date, end_date, rent_amount, deposit_amount, status)
  values (v_org, p_unit_id, p_start, p_end, p_rent, p_deposit, 'active')
  returning id into v_lease_id;

  insert into lease_tenants (lease_id, tenant_id, is_primary)
  values (v_lease_id, p_tenant_id, true);

  update units set status = 'occupied' where id = p_unit_id;

  return v_lease_id;
end $$;

grant execute on function create_lease(uuid, uuid, numeric, numeric, date, date) to authenticated;
__EOF__

# ---------------------------------------------------------------
cat > app/tenants/actions.ts << '__EOF__'
"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { requireOrg } from "@/lib/auth";

export async function createTenant(formData: FormData) {
  const { supabase, orgId } = await requireOrg();
  const payload = {
    organization_id: orgId,
    full_name: String(formData.get("full_name")),
    email: String(formData.get("email") || "").trim() || null,
    phone: String(formData.get("phone") || "").trim() || null,
  };
  const { error } = await supabase.from("tenants").insert(payload);
  if (error) redirect("/tenants/new?error=" + encodeURIComponent(error.message));
  revalidatePath("/tenants");
  redirect("/tenants");
}
__EOF__

# ---------------------------------------------------------------
cat > app/tenants/page.tsx << '__EOF__'
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
__EOF__

# ---------------------------------------------------------------
cat > app/tenants/new/page.tsx << '__EOF__'
import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";
import { createTenant } from "../actions";

export default async function NewTenantPage({
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
        <h1 className="text-xl font-semibold">Add tenant</h1>
        {error && (
          <p className="text-sm text-red-400 bg-red-950/40 border border-red-900 rounded-md p-3">
            {error}
          </p>
        )}
        <form action={createTenant} className="space-y-3">
          <input name="full_name" required placeholder="Full name" className={input} />
          <input name="email" type="email" placeholder="Email (optional)" className={input} />
          <input name="phone" type="tel" placeholder="Phone (optional)" className={input} />
          <button className="w-full rounded-md bg-amber-500 text-neutral-950 font-medium py-2 text-sm hover:bg-amber-400">
            Save tenant
          </button>
        </form>
      </main>
    </div>
  );
}
__EOF__

# ---------------------------------------------------------------
cat > app/leases/actions.ts << '__EOF__'
"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { requireOrg } from "@/lib/auth";

function emptyToNull(v: FormDataEntryValue | null) {
  const s = String(v ?? "").trim();
  return s === "" ? null : s;
}

export async function createLease(formData: FormData) {
  const { supabase } = await requireOrg();

  const unit_id = String(formData.get("unit_id") || "");
  const tenant_id = String(formData.get("tenant_id") || "");
  if (!unit_id || !tenant_id) {
    redirect("/leases/new?error=" + encodeURIComponent("Choose both a unit and a tenant"));
  }

  const rentStr = String(formData.get("rent_amount") || "").trim();
  const rent = rentStr === "" ? NaN : Number(rentStr);
  if (Number.isNaN(rent)) {
    redirect("/leases/new?error=" + encodeURIComponent("Enter a valid rent amount"));
  }

  const depositStr = String(formData.get("deposit_amount") || "").trim();
  const deposit = depositStr === "" ? null : Number(depositStr);

  const start = emptyToNull(formData.get("start_date"));
  if (!start) {
    redirect("/leases/new?error=" + encodeURIComponent("Enter a start date"));
  }
  const end = emptyToNull(formData.get("end_date"));

  const { error } = await supabase.rpc("create_lease", {
    p_unit_id: unit_id,
    p_tenant_id: tenant_id,
    p_rent: rent,
    p_deposit: deposit,
    p_start: start,
    p_end: end,
  });
  if (error) redirect("/leases/new?error=" + encodeURIComponent(error.message));

  revalidatePath("/leases");
  revalidatePath("/units");
  revalidatePath("/dashboard");
  redirect("/leases");
}
__EOF__

# ---------------------------------------------------------------
cat > app/leases/page.tsx << '__EOF__'
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
__EOF__

# ---------------------------------------------------------------
cat > app/leases/new/page.tsx << '__EOF__'
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
__EOF__

# ---------------------------------------------------------------
# Rewrite AppHeader to add Tenants and Leases nav links.
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
# Rewrite dashboard to add an "Active leases" stat.
cat > app/dashboard/page.tsx << '__EOF__'
import Link from "next/link";
import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-lg border border-neutral-800 bg-neutral-900 p-5">
      <div className="text-3xl font-semibold">{value}</div>
      <div className="text-sm text-neutral-400 mt-1">{label}</div>
    </div>
  );
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
          <Stat label="Properties" value={properties} />
          <Stat label="Units" value={units} />
          <Stat label="Active leases" value={activeLeases} />
          <Stat label="Open maintenance" value={openReqs} />
        </div>
      </main>
    </div>
  );
}
__EOF__

echo ""
echo "Done. Files created/updated:"
echo "  supabase/migrations/0004_leases.sql   (RUN THIS IN SUPABASE)"
echo "  app/tenants/(page.tsx, new/page.tsx, actions.ts)"
echo "  app/leases/(page.tsx, new/page.tsx, actions.ts)"
echo "  app/_components/AppHeader.tsx   (added Tenants + Leases nav)"
echo "  app/dashboard/page.tsx          (added Active leases stat)"
echo ""
echo "IMPORTANT: run supabase/migrations/0004_leases.sql in the Supabase SQL Editor"
echo "before creating a lease, or the lease form will error."
