import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";
import SubmitButton from "@/app/_components/SubmitButton";
import { startProCheckout, openBillingPortal } from "./actions";

export default async function BillingPage({
  searchParams,
}: {
  searchParams: Promise<{ upgraded?: string; canceled?: string; error?: string }>;
}) {
  const { supabase, orgId, membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";
  const { data: org } = await supabase
    .from("organizations").select("plan, pro_direct, pro_executive").eq("id", orgId).maybeSingle();
  const o = org as any;
  const isPro = o?.plan === "pro";
  const viaExecutiveOnly = isPro && o?.pro_executive && !o?.pro_direct;
  const sp = await searchParams;

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100">
      <AppHeader orgName={orgName} />
      <main className="max-w-2xl mx-auto px-6 py-8 space-y-6">
        <h1 className="text-xl font-semibold">Billing</h1>

        {sp.upgraded && <p className="text-sm text-green-400 bg-green-950/30 border border-green-900 rounded-md p-3">You&apos;re on Pro — thank you! Pro features are unlocked.</p>}
        {sp.canceled && <p className="text-sm text-neutral-400 bg-neutral-900 border border-neutral-800 rounded-md p-3">Checkout canceled.</p>}
        {sp.error && <p className="text-sm text-red-400 bg-red-950/40 border border-red-900 rounded-md p-3">{sp.error}</p>}

        <div className="rounded-lg border border-neutral-800 bg-neutral-900 p-6">
          <div className="flex items-center justify-between">
            <div>
              <div className="text-xs uppercase tracking-wide text-neutral-500">Current plan</div>
              <div className="text-2xl font-semibold mt-1">{isPro ? "PropertyOS Pro" : "Free"}</div>
            </div>
            <span className={"text-sm font-semibold px-3 py-1 rounded-full border " + (isPro ? "bg-amber-500/15 text-amber-300 border-amber-500/40" : "bg-neutral-800 text-neutral-300 border-neutral-700")}>
              {isPro ? "Pro" : "Free"}
            </span>
          </div>

          <ul className="mt-5 space-y-2 text-sm text-neutral-300">
            <li>· Property management, leasing, maintenance &amp; rent collection</li>
            <li>· Infill Build Analyzer with break-even solver <span className="text-neutral-500">(free)</span></li>
            <li className={isPro ? "" : "text-neutral-500"}>{isPro ? "✓" : "○"} Save deals to a pipeline</li>
            <li className={isPro ? "" : "text-neutral-500"}>{isPro ? "✓" : "○"} Branded PDF reports</li>
            <li className={isPro ? "" : "text-neutral-500"}>{isPro ? "✓" : "○"} Send deals to your Acquisition Engine</li>
          </ul>

          <div className="mt-6">
            {viaExecutiveOnly ? (
              <p className="text-sm text-amber-300 bg-amber-500/10 border border-amber-500/30 rounded-md p-3">
                Pro is included with your Acquisition Engine Executive plan. Manage it from the Acquisition Engine.
              </p>
            ) : o?.pro_direct ? (
              <form action={openBillingPortal}>
                <SubmitButton pendingText="Opening…" className="rounded-md border border-neutral-700 text-neutral-200 text-sm font-medium px-4 py-2 hover:bg-neutral-800">
                  Manage subscription
                </SubmitButton>
              </form>
            ) : (
              <form action={startProCheckout}>
                <SubmitButton pendingText="Redirecting…" className="rounded-md bg-amber-500 text-neutral-950 text-sm font-semibold px-5 py-2.5 hover:bg-amber-400">
                  Upgrade to Pro — $79/month
                </SubmitButton>
              </form>
            )}
          </div>
        </div>

        <p className="text-xs text-neutral-600">
          Subscriptions are billed monthly via Stripe. You can cancel anytime from &ldquo;Manage subscription.&rdquo;
        </p>
      </main>
    </div>
  );
}
