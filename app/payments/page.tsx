import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";
import SubmitButton from "@/app/_components/SubmitButton";
import { generateRent, markPaidManual, createCheckout } from "./actions";

function tenantName(lease: any): string {
  const lt = lease?.lease_tenants as any[] | undefined;
  if (!lt || lt.length === 0) return "—";
  const primary = lt.find((x) => x.is_primary) ?? lt[0];
  return primary?.tenants?.full_name ?? "—";
}

function periodLabel(d: string): string {
  return new Date(d + "T00:00:00").toLocaleDateString(undefined, {
    month: "short",
    year: "numeric",
  });
}

export default async function PaymentsPage({
  searchParams,
}: {
  searchParams: Promise<{
    gen?: string;
    paid?: string;
    canceled?: string;
    manual?: string;
    error?: string;
  }>;
}) {
  const { supabase, membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";
  const sp = await searchParams;

  const { data: payments } = await supabase
    .from("payments")
    .select(
      "id, period_start, amount_due, amount_paid, status, leases(units(unit_number, properties(name)), lease_tenants(is_primary, tenants(full_name)))"
    )
    .is("deleted_at", null)
    .order("period_start", { ascending: false });

  const monthStart = new Date(
    new Date().getFullYear(),
    new Date().getMonth(),
    1
  )
    .toISOString()
    .slice(0, 10);

  const btn =
    "rounded-md text-xs font-medium px-2.5 py-1.5";

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100">
      <AppHeader orgName={orgName} />
      <main className="max-w-5xl mx-auto px-6 py-8 space-y-6">
        <div className="flex items-center justify-between">
          <h1 className="text-xl font-semibold">Payments</h1>
          <form action={generateRent}>
            <SubmitButton
              pendingText="Generating…"
              className="rounded-md bg-amber-500 text-neutral-950 text-sm font-medium px-3 py-2 hover:bg-amber-400"
            >
              Generate this month&apos;s rent
            </SubmitButton>
          </form>
        </div>

        {sp.error && (
          <p className="text-sm text-red-400 bg-red-950/40 border border-red-900 rounded-md p-3">{sp.error}</p>
        )}
        {sp.gen && (
          <p className="text-sm text-green-400 bg-green-950/30 border border-green-900 rounded-md p-3">
            Generated {sp.gen} rent record(s) for this month.
          </p>
        )}
        {sp.paid && (
          <p className="text-sm text-green-400 bg-green-950/30 border border-green-900 rounded-md p-3">
            Payment received. (It flips to Paid once the webhook lands.)
          </p>
        )}
        {sp.manual && (
          <p className="text-sm text-green-400 bg-green-950/30 border border-green-900 rounded-md p-3">
            Marked as paid.
          </p>
        )}
        {sp.canceled && (
          <p className="text-sm text-neutral-400 bg-neutral-900 border border-neutral-800 rounded-md p-3">
            Checkout canceled.
          </p>
        )}

        {!payments || payments.length === 0 ? (
          <p className="text-neutral-400 text-sm">
            No payment records yet. Click &quot;Generate this month&apos;s rent&quot; to create them from your active leases.
          </p>
        ) : (
          <div className="overflow-hidden rounded-lg border border-neutral-800">
            <table className="w-full text-sm">
              <thead className="bg-neutral-900 text-neutral-400 text-left">
                <tr>
                  <th className="px-4 py-2 font-medium">Tenant</th>
                  <th className="px-4 py-2 font-medium">Unit</th>
                  <th className="px-4 py-2 font-medium">Period</th>
                  <th className="px-4 py-2 font-medium">Amount</th>
                  <th className="px-4 py-2 font-medium">Status</th>
                  <th className="px-4 py-2 font-medium"></th>
                </tr>
              </thead>
              <tbody>
                {payments.map((p: any) => {
                  const isPaid = p.status === "paid";
                  const overdue = !isPaid && p.period_start < monthStart;
                  const statusCls = isPaid
                    ? "text-green-400"
                    : overdue
                    ? "text-red-400"
                    : "text-amber-400";
                  const statusText = isPaid ? "Paid" : overdue ? "Overdue" : "Due";
                  return (
                    <tr key={p.id} className="border-t border-neutral-800">
                      <td className="px-4 py-3 font-medium">{tenantName(p.leases)}</td>
                      <td className="px-4 py-3 text-neutral-300">
                        {p.leases?.units?.properties?.name ?? "—"} · {p.leases?.units?.unit_number ?? "—"}
                      </td>
                      <td className="px-4 py-3 text-neutral-300">{periodLabel(p.period_start)}</td>
                      <td className="px-4 py-3 text-neutral-300">
                        ${Number(p.amount_due).toLocaleString()}
                      </td>
                      <td className={"px-4 py-3 " + statusCls}>{statusText}</td>
                      <td className="px-4 py-3 text-right">
                        {isPaid ? (
                          <span className="text-neutral-600 text-xs">—</span>
                        ) : (
                          <div className="flex gap-2 justify-end">
                            <form action={createCheckout}>
                              <input type="hidden" name="id" value={p.id} />
                              <SubmitButton
                                pendingText="…"
                                className={btn + " bg-amber-500 text-neutral-950 hover:bg-amber-400"}
                              >
                                Pay (Stripe)
                              </SubmitButton>
                            </form>
                            <form action={markPaidManual}>
                              <input type="hidden" name="id" value={p.id} />
                              <SubmitButton
                                pendingText="…"
                                className={btn + " border border-neutral-700 text-neutral-300 hover:bg-neutral-800"}
                              >
                                Mark paid
                              </SubmitButton>
                            </form>
                          </div>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </main>
    </div>
  );
}
