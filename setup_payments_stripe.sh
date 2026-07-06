#!/usr/bin/env bash
# PropertyOS — Vertical 6 setup: rent tracking + Stripe (test mode).
# Run this from your project root (the folder with package.json and app/).
set -e

if [ ! -f package.json ] || [ ! -d app ]; then
  echo "ERROR: run this from your propertyos project root (where package.json and app/ live)."
  exit 1
fi

echo "Creating folders..."
mkdir -p app/payments app/api/stripe/webhook supabase/migrations lib

echo "Writing files..."

# ---------------------------------------------------------------
cat > supabase/migrations/0005_payments.sql << '__EOF__'
-- PropertyOS — 0005_payments.sql
-- generate_current_rent: for every active lease that doesn't yet have a
-- payment row for the current month, create one (status 'due'). Idempotent
-- thanks to the NOT EXISTS guard + the unique(lease_id, period_start)
-- constraint. SECURITY INVOKER, so RLS scopes it to the caller's org.

create or replace function generate_current_rent()
returns integer
language plpgsql
as $$
declare
  v_period date := date_trunc('month', now())::date;
  v_count integer;
begin
  insert into payments (organization_id, lease_id, period_start, amount_due, status)
  select l.organization_id, l.id, v_period, l.rent_amount, 'due'
  from leases l
  where l.status = 'active'
    and l.deleted_at is null
    and not exists (
      select 1 from payments p
      where p.lease_id = l.id
        and p.period_start = v_period
        and p.deleted_at is null
    );
  get diagnostics v_count = row_count;
  return v_count;
end $$;

grant execute on function generate_current_rent() to authenticated;
__EOF__

# ---------------------------------------------------------------
cat > lib/stripe.ts << '__EOF__'
import Stripe from "stripe";

export const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!);
__EOF__

# ---------------------------------------------------------------
# Rewrite the middleware helper to treat /api as public (so Stripe's
# webhook can reach /api/stripe/webhook without an auth redirect).
cat > lib/supabase/middleware.ts << '__EOF__'
import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

export async function updateSession(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value)
          );
          supabaseResponse = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options)
          );
        },
      },
    }
  );

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const path = request.nextUrl.pathname;
  const isPublic =
    path.startsWith("/login") ||
    path.startsWith("/auth") ||
    path.startsWith("/api");
  if (!user && !isPublic) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    return NextResponse.redirect(url);
  }

  return supabaseResponse;
}
__EOF__

# ---------------------------------------------------------------
cat > app/payments/actions.ts << '__EOF__'
"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { requireOrg } from "@/lib/auth";
import { stripe } from "@/lib/stripe";

export async function generateRent() {
  const { supabase } = await requireOrg();
  const { data, error } = await supabase.rpc("generate_current_rent");
  if (error) redirect("/payments?error=" + encodeURIComponent(error.message));
  revalidatePath("/payments");
  redirect("/payments?gen=" + (data ?? 0));
}

export async function markPaidManual(formData: FormData) {
  const { supabase } = await requireOrg();
  const id = String(formData.get("id"));
  const { data: pay } = await supabase
    .from("payments")
    .select("amount_due")
    .eq("id", id)
    .maybeSingle();
  if (!pay) redirect("/payments?error=" + encodeURIComponent("Payment not found"));
  const { error } = await supabase
    .from("payments")
    .update({
      status: "paid",
      amount_paid: (pay as any).amount_due,
      paid_at: new Date().toISOString(),
    })
    .eq("id", id);
  if (error) redirect("/payments?error=" + encodeURIComponent(error.message));
  revalidatePath("/payments");
  redirect("/payments?manual=1");
}

export async function createCheckout(formData: FormData) {
  const { supabase } = await requireOrg();
  const id = String(formData.get("id"));

  const { data: pay } = await supabase
    .from("payments")
    .select("amount_due, period_start, leases(units(unit_number, properties(name)))")
    .eq("id", id)
    .maybeSingle();
  if (!pay) redirect("/payments?error=" + encodeURIComponent("Payment not found"));

  const p = pay as any;
  const appUrl = process.env.NEXT_PUBLIC_APP_URL || "http://localhost:3004";
  const label =
    "Rent — " +
    (p.leases?.units?.properties?.name ?? "Property") +
    " " +
    (p.leases?.units?.unit_number ?? "") +
    " (" +
    p.period_start +
    ")";

  let url: string | null = null;
  try {
    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      line_items: [
        {
          price_data: {
            currency: "usd",
            product_data: { name: label },
            unit_amount: Math.round(Number(p.amount_due) * 100),
          },
          quantity: 1,
        },
      ],
      metadata: { payment_id: id },
      success_url: appUrl + "/payments?paid=1",
      cancel_url: appUrl + "/payments?canceled=1",
    });
    url = session.url;
  } catch (e: any) {
    redirect("/payments?error=" + encodeURIComponent(e?.message ?? "Stripe error"));
  }
  redirect(url!);
}
__EOF__

# ---------------------------------------------------------------
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
    event = stripe.webhooks.constructEvent(
      body,
      sig,
      process.env.STRIPE_WEBHOOK_SECRET!
    );
  } catch (err: any) {
    return new NextResponse("Signature verification failed: " + err.message, {
      status: 400,
    });
  }

  if (event.type === "checkout.session.completed") {
    const session = event.data.object as any;
    const paymentId = session.metadata?.payment_id;
    if (paymentId) {
      // service-role client: this is Stripe calling, not a logged-in user.
      const admin = createAdminClient();
      const { data: pay } = await admin
        .from("payments")
        .select("amount_due")
        .eq("id", paymentId)
        .maybeSingle();
      await admin
        .from("payments")
        .update({
          status: "paid",
          amount_paid: pay?.amount_due ?? 0,
          stripe_payment_intent: session.payment_intent ?? null,
          paid_at: new Date().toISOString(),
        })
        .eq("id", paymentId);
    }
  }

  return NextResponse.json({ received: true });
}
__EOF__

# ---------------------------------------------------------------
cat > app/payments/page.tsx << '__EOF__'
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
__EOF__

# ---------------------------------------------------------------
# Rewrite AppHeader to add the Payments nav link.
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
# Update the env template to document the new Stripe variables.
cat > .env.local.example << '__EOF__'
# PropertyOS — copy this file to ".env.local" and fill in your values.
# .env.local is gitignored. NEVER commit real keys. NEVER paste keys in chat.

# --- Supabase: Public (safe in the browser; protected by RLS) ---
NEXT_PUBLIC_SUPABASE_URL=https://YOUR-PROJECT-ref.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-public-key

# --- Supabase: Server-only SECRET (full DB access, bypasses RLS) ---
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key

# --- App URL (used for Stripe success/cancel redirects) ---
NEXT_PUBLIC_APP_URL=http://localhost:3004

# --- Stripe: use TEST-mode keys for now ---
STRIPE_SECRET_KEY=sk_test_your-test-secret-key
# This value comes from running:  stripe listen --forward-to localhost:3004/api/stripe/webhook
STRIPE_WEBHOOK_SECRET=whsec_your-webhook-signing-secret
__EOF__

echo ""
echo "Done. Files created/updated:"
echo "  supabase/migrations/0005_payments.sql   (RUN THIS IN SUPABASE)"
echo "  lib/stripe.ts"
echo "  lib/supabase/middleware.ts               (made /api public for the webhook)"
echo "  app/payments/(page.tsx, actions.ts)"
echo "  app/api/stripe/webhook/route.ts"
echo "  app/_components/AppHeader.tsx            (added Payments nav)"
echo "  .env.local.example                       (documented Stripe vars)"
echo ""
echo "NEXT: npm install stripe  |  run 0005 in Supabase  |  add Stripe keys to .env.local"
echo "      run 'stripe listen', then RESTART the dev server."
