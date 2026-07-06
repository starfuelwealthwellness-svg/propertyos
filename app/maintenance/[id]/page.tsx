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
