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
