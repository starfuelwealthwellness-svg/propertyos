#!/usr/bin/env bash
# PropertyOS — Stripe subscription billing (self-serve Pro upgrade).
# Run from project root. Then do the Stripe + Supabase setup steps.
set -e
if [ ! -f app/analyzer/Analyzer.tsx ]; then
  echo "ERROR: run the analyzer setup first."
  exit 1
fi
mkdir -p app/billing supabase/migrations

# ---------------------------------------------------------------
cat > supabase/migrations/0007_billing.sql << '__EOF__'
-- PropertyOS — 0007_billing.sql
-- Store the Stripe customer + subscription for each org so webhooks
-- can map events back to the right organization.

alter table organizations
  add column if not exists stripe_customer_id text,
  add column if not exists stripe_subscription_id text;
__EOF__

# ---------------------------------------------------------------
cat > app/billing/actions.ts << '__EOF__'
"use server";

import { redirect } from "next/navigation";
import { requireOrg } from "@/lib/auth";
import { stripe } from "@/lib/stripe";

export async function startProCheckout() {
  const { supabase, orgId, user } = await requireOrg();
  const { data: org } = await supabase
    .from("organizations").select("plan, stripe_customer_id").eq("id", orgId).maybeSingle();
  const o = org as any;
  if (o?.plan === "pro") redirect("/billing");

  const appUrl = process.env.NEXT_PUBLIC_APP_URL || "http://localhost:3004";
  let url: string | null = null;
  try {
    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      line_items: [{ price: process.env.STRIPE_PRO_PRICE_ID!, quantity: 1 }],
      customer: o?.stripe_customer_id || undefined,
      customer_email: o?.stripe_customer_id ? undefined : (user.email || undefined),
      metadata: { organization_id: orgId },
      subscription_data: { metadata: { organization_id: orgId } },
      success_url: appUrl + "/billing?upgraded=1",
      cancel_url: appUrl + "/billing?canceled=1",
    });
    url = session.url;
  } catch (e: any) {
    redirect("/billing?error=" + encodeURIComponent(e?.message ?? "Stripe error"));
  }
  redirect(url!);
}

export async function openBillingPortal() {
  const { supabase, orgId } = await requireOrg();
  const { data: org } = await supabase
    .from("organizations").select("stripe_customer_id").eq("id", orgId).maybeSingle();
  const customer = (org as any)?.stripe_customer_id;
  if (!customer) redirect("/billing?error=" + encodeURIComponent("No billing account yet."));

  const appUrl = process.env.NEXT_PUBLIC_APP_URL || "http://localhost:3004";
  let url: string | null = null;
  try {
    const portal = await stripe.billingPortal.sessions.create({ customer, return_url: appUrl + "/billing" });
    url = portal.url;
  } catch (e: any) {
    redirect("/billing?error=" + encodeURIComponent(e?.message ?? "Stripe error"));
  }
  redirect(url!);
}
__EOF__

# ---------------------------------------------------------------
cat > app/billing/page.tsx << '__EOF__'
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
  const { data: org } = await supabase.from("organizations").select("plan").eq("id", orgId).maybeSingle();
  const isPro = (org as any)?.plan === "pro";
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
            <li className="text-neutral-500">○ Acquisition Engine handoff <span className="text-neutral-600">(coming soon)</span></li>
          </ul>

          <div className="mt-6">
            {isPro ? (
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
__EOF__

# ---------------------------------------------------------------
# Webhook: now handles BOTH one-off rent payments AND subscriptions.
cat > app/api/stripe/webhook/route.ts << '__EOF__'
import { NextRequest, NextResponse } from "next/server";
import { stripe } from "@/lib/stripe";
import { createAdminClient } from "@/lib/supabase/server";

export async function POST(req: NextRequest) {
  const body = await req.text();
  const sig = req.headers.get("stripe-signature");
  if (!sig) return new NextResponse("Missing signature", { status: 400 });

  let event;
  try {
    event = stripe.webhooks.constructEvent(body, sig, process.env.STRIPE_WEBHOOK_SECRET!);
  } catch (err: any) {
    return new NextResponse("Signature verification failed: " + err.message, { status: 400 });
  }

  const admin = createAdminClient();

  if (event.type === "checkout.session.completed") {
    const session = event.data.object as any;
    if (session.mode === "subscription") {
      const orgId = session.metadata?.organization_id;
      if (orgId) {
        await admin.from("organizations").update({
          plan: "pro",
          stripe_customer_id: session.customer ?? null,
          stripe_subscription_id: session.subscription ?? null,
        }).eq("id", orgId);
      }
    } else {
      // one-off rent payment (unchanged)
      const paymentId = session.metadata?.payment_id;
      if (paymentId) {
        const { data: pay } = await admin.from("payments").select("amount_due").eq("id", paymentId).maybeSingle();
        await admin.from("payments").update({
          status: "paid",
          amount_paid: pay?.amount_due ?? 0,
          stripe_payment_intent: session.payment_intent ?? null,
          paid_at: new Date().toISOString(),
        }).eq("id", paymentId);
      }
    }
  } else if (event.type === "customer.subscription.deleted") {
    const sub = event.data.object as any;
    const orgId = sub.metadata?.organization_id;
    if (orgId) await admin.from("organizations").update({ plan: "free", stripe_subscription_id: null }).eq("id", orgId);
    else if (sub.customer) await admin.from("organizations").update({ plan: "free", stripe_subscription_id: null }).eq("stripe_customer_id", sub.customer);
  } else if (event.type === "customer.subscription.updated") {
    const sub = event.data.object as any;
    const active = sub.status === "active" || sub.status === "trialing";
    const orgId = sub.metadata?.organization_id;
    const patch = { plan: active ? "pro" : "free" };
    if (orgId) await admin.from("organizations").update(patch).eq("id", orgId);
    else if (sub.customer) await admin.from("organizations").update(patch).eq("stripe_customer_id", sub.customer);
  }

  return NextResponse.json({ received: true });
}
__EOF__

# ---------------------------------------------------------------
# AppHeader: org name now links to /billing.
cat > app/_components/AppHeader.tsx << '__EOF__'
import Link from "next/link";
import { signOut } from "@/app/login/actions";

export default function AppHeader({ orgName }: { orgName: string }) {
  return (
    <header className="border-b border-neutral-800 bg-neutral-950">
      <div className="max-w-6xl mx-auto px-6 py-3 flex items-center justify-between">
        <div className="flex items-center gap-5">
          <span className="font-semibold text-amber-400">PropertyOS</span>
          <nav className="flex gap-4 text-sm text-neutral-300">
            <Link href="/dashboard" className="hover:text-white">Dashboard</Link>
            <Link href="/properties" className="hover:text-white">Properties</Link>
            <Link href="/units" className="hover:text-white">Units</Link>
            <Link href="/tenants" className="hover:text-white">Tenants</Link>
            <Link href="/leases" className="hover:text-white">Leases</Link>
            <Link href="/payments" className="hover:text-white">Payments</Link>
            <Link href="/maintenance" className="hover:text-white">Maintenance</Link>
            <Link href="/vendors" className="hover:text-white">Vendors</Link>
            <Link href="/analyzer" className="hover:text-white text-amber-300">Analyzer</Link>
          </nav>
        </div>
        <div className="flex items-center gap-3 text-sm">
          <Link href="/billing" className="text-neutral-400 hover:text-white">{orgName}</Link>
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
# Saved deals: free-tier prompt now links to /billing.
cat > app/analyzer/saved/page.tsx << '__EOF__'
import Link from "next/link";
import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";

export default async function SavedDealsPage() {
  const { supabase, orgId, membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";
  const { data: org } = await supabase.from("organizations").select("plan").eq("id", orgId).maybeSingle();
  const isPro = (org as any)?.plan === "pro";

  let deals: any[] | null = null;
  if (isPro) {
    const res = await supabase
      .from("analyses")
      .select("id, name, address, plan_name, summary, created_at")
      .is("deleted_at", null)
      .order("created_at", { ascending: false });
    deals = res.data;
  }

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100">
      <AppHeader orgName={orgName} />
      <main className="max-w-4xl mx-auto px-6 py-8 space-y-6">
        <div className="flex items-center justify-between">
          <h1 className="text-xl font-semibold">Saved deals</h1>
          <Link href="/analyzer" className="text-sm text-amber-300 hover:underline">← Back to Analyzer</Link>
        </div>

        {!isPro ? (
          <div className="rounded-lg border border-amber-500/40 bg-neutral-900 p-6">
            <div className="text-amber-300 font-semibold">Saved deals is a Pro feature</div>
            <p className="text-sm text-neutral-400 mt-2">
              Upgrade to save analyses to a pipeline, export branded PDF reports, and send deals to your Acquisition Engine.
            </p>
            <Link href="/billing" className="inline-block mt-4 rounded-md bg-amber-500 text-neutral-950 text-sm font-semibold px-4 py-2 hover:bg-amber-400">
              Upgrade to Pro →
            </Link>
          </div>
        ) : !deals || deals.length === 0 ? (
          <p className="text-neutral-400 text-sm">No saved deals yet. Run an analysis and click &ldquo;Save this deal.&rdquo;</p>
        ) : (
          <div className="grid gap-3">
            {deals.map((d: any) => {
              const s = d.summary || {};
              const verdict = s.verdict ?? "—";
              const vc = verdict === "Pencils" ? "text-green-400" : verdict === "Underwater" ? "text-red-400" : "text-amber-400";
              return (
                <div key={d.id} className="rounded-lg border border-neutral-800 bg-neutral-900 p-4">
                  <div className="flex items-center justify-between">
                    <div className="font-medium">{d.name}</div>
                    <div className={"text-sm font-semibold " + vc}>{verdict}</div>
                  </div>
                  <div className="text-sm text-neutral-400 mt-1">
                    {d.plan_name ?? "—"}{d.address ? " · " + d.address : ""}
                  </div>
                  <div className="text-xs text-neutral-500 mt-2 flex flex-wrap gap-4 items-center">
                    {s.total != null && <span>Cost ${Number(s.total).toLocaleString()}</span>}
                    {s.cfMo != null && <span>Cash flow ${Math.round(s.cfMo).toLocaleString()}/mo</span>}
                    {s.coc != null && <span>CoC {(s.coc * 100).toFixed(1)}%</span>}
                    <span>{new Date(d.created_at).toLocaleDateString()}</span>
                    <Link href={"/analyzer/report/" + d.id} className="text-amber-300 hover:underline ml-auto">PDF report →</Link>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </main>
    </div>
  );
}
__EOF__

echo ""
echo "Done. Created/updated:"
echo "  supabase/migrations/0007_billing.sql   (RUN IN SUPABASE)"
echo "  app/billing/(page.tsx, actions.ts)"
echo "  app/api/stripe/webhook/route.ts   (now handles subscriptions + rent)"
echo "  app/_components/AppHeader.tsx      (org name links to /billing)"
echo "  app/analyzer/saved/page.tsx       (free prompt links to /billing)"
