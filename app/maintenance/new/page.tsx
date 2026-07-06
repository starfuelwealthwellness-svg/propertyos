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
