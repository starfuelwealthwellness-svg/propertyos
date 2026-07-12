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
