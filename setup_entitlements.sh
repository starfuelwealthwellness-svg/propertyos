#!/usr/bin/env bash
# PropertyOS — Integration 2: Executive -> Pro entitlement (receiving side).
# Run from project root. Then run 0009 in Supabase + add ENTITLEMENT_SYNC_SECRET.
set -e
if [ ! -f app/billing/page.tsx ]; then
  echo "ERROR: run the billing setup first."
  exit 1
fi
mkdir -p app/api/entitlements/executive supabase/migrations

# ---------------------------------------------------------------
cat > supabase/migrations/0009_entitlements.sql << '__EOF__'
-- PropertyOS — 0009_entitlements.sql
-- Cross-app entitlement support: match by email, dual-source Pro.

-- 1) Store email on profiles so entitlements can be matched by email.
alter table profiles add column if not exists email text;
create index if not exists profiles_email_idx on profiles (email);

-- Backfill existing emails from auth.users (SQL editor runs as postgres).
update profiles p set email = u.email
from auth.users u where u.id = p.id and p.email is null;

-- Capture email on new signups.
create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, email)
  values (new.id, new.raw_user_meta_data->>'full_name', new.email);
  return new;
end $$;

-- 2) Dual-source Pro: direct (own Stripe) OR executive (Acquisition Engine perk).
alter table organizations
  add column if not exists pro_direct boolean not null default false,
  add column if not exists pro_executive boolean not null default false;

-- Existing 'pro' orgs were directly paid.
update organizations set pro_direct = true where plan = 'pro' and pro_direct = false;

-- Derive plan from the two sources on every write.
create or replace function derive_org_plan()
returns trigger language plpgsql as $$
begin
  new.plan := case when (new.pro_direct or new.pro_executive) then 'pro' else 'free' end;
  return new;
end $$;

drop trigger if exists trg_org_plan on organizations;
create trigger trg_org_plan before insert or update on organizations
  for each row execute function derive_org_plan();
__EOF__

# ---------------------------------------------------------------
cat > app/api/entitlements/executive/route.ts << '__EOF__'
import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/server";

// Acquisition Engine calls this to grant/revoke PropertyOS Pro as an
// Executive-tier perk. Auth via shared secret; matches users by email.
export async function POST(req: NextRequest) {
  if (req.headers.get("x-api-key") !== process.env.ENTITLEMENT_SYNC_SECRET) {
    return new NextResponse("Unauthorized", { status: 401 });
  }

  let body: any;
  try { body = await req.json(); }
  catch { return NextResponse.json({ ok: false, error: "Invalid JSON" }, { status: 400 }); }

  const email = String(body?.email ?? "").trim().toLowerCase();
  const executive = body?.executive === true;
  if (!email) return NextResponse.json({ ok: false, error: "email is required" }, { status: 400 });

  const admin = createAdminClient();

  const { data: profs, error: pe } = await admin.from("profiles").select("id").eq("email", email);
  if (pe) return NextResponse.json({ ok: false, error: pe.message }, { status: 500 });
  if (!profs || profs.length === 0) {
    return NextResponse.json({ ok: true, matched: 0, note: "No PropertyOS account for that email yet." });
  }

  const ids = profs.map((p: any) => p.id);
  const { data: mems, error: me } = await admin
    .from("memberships").select("organization_id")
    .in("user_id", ids).eq("role", "owner").is("deleted_at", null);
  if (me) return NextResponse.json({ ok: false, error: me.message }, { status: 500 });

  const orgIds = Array.from(new Set((mems ?? []).map((m: any) => m.organization_id)));
  if (orgIds.length === 0) return NextResponse.json({ ok: true, matched: 0, note: "No owned organizations." });

  const { error: ue } = await admin.from("organizations").update({ pro_executive: executive }).in("id", orgIds);
  if (ue) return NextResponse.json({ ok: false, error: ue.message }, { status: 500 });

  return NextResponse.json({ ok: true, matched: orgIds.length, executive });
}
__EOF__

# ---------------------------------------------------------------
# Webhook: set pro_direct (not plan) so the trigger derives plan.
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
          pro_direct: true,
          stripe_customer_id: session.customer ?? null,
          stripe_subscription_id: session.subscription ?? null,
        }).eq("id", orgId);
      }
    } else {
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
    if (orgId) await admin.from("organizations").update({ pro_direct: false, stripe_subscription_id: null }).eq("id", orgId);
    else if (sub.customer) await admin.from("organizations").update({ pro_direct: false, stripe_subscription_id: null }).eq("stripe_customer_id", sub.customer);
  } else if (event.type === "customer.subscription.updated") {
    const sub = event.data.object as any;
    const active = sub.status === "active" || sub.status === "trialing";
    const orgId = sub.metadata?.organization_id;
    if (orgId) await admin.from("organizations").update({ pro_direct: active }).eq("id", orgId);
    else if (sub.customer) await admin.from("organizations").update({ pro_direct: active }).eq("stripe_customer_id", sub.customer);
  }

  return NextResponse.json({ received: true });
}
__EOF__

# ---------------------------------------------------------------
# Billing page: source-aware (direct vs executive perk).
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
__EOF__

echo ""
echo "Done. Created/updated:"
echo "  supabase/migrations/0009_entitlements.sql   (RUN IN SUPABASE)"
echo "  app/api/entitlements/executive/route.ts     (new receiving endpoint)"
echo "  app/api/stripe/webhook/route.ts             (now sets pro_direct)"
echo "  app/billing/page.tsx                        (source-aware)"
echo ""
echo "Then add to .env.local (and later Vercel):"
echo "  ENTITLEMENT_SYNC_SECRET=<same value the Acquisition Engine will send>"
echo ""
echo "NOTE: to manually test Pro now, set the source column (plan is derived):"
echo "  update organizations set pro_direct=true where id=(select id from organizations order by created_at desc limit 1);"
