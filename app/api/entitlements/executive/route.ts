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
