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
