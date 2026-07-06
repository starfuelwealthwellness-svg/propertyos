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
