#!/usr/bin/env bash
# PropertyOS — Vertical 1 setup: auth + org onboarding + Properties CRUD.
# Run this from your project root (the folder with package.json and app/).
set -e

if [ ! -f package.json ] || [ ! -d app ]; then
  echo "ERROR: run this from your propertyos project root (where package.json and app/ live)."
  exit 1
fi

echo "Creating folders..."
mkdir -p lib/supabase app/login app/onboarding app/dashboard app/properties/new app/_components supabase/migrations

echo "Writing files..."

# ---------------------------------------------------------------
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
  const isPublic = path.startsWith("/login") || path.startsWith("/auth");
  if (!user && !isPublic) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    return NextResponse.redirect(url);
  }

  return supabaseResponse;
}
__EOF__

# ---------------------------------------------------------------
cat > middleware.ts << '__EOF__'
import { type NextRequest } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";

export async function middleware(request: NextRequest) {
  return await updateSession(request);
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
__EOF__

# ---------------------------------------------------------------
cat > lib/auth.ts << '__EOF__'
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function getUser() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return { supabase, user };
}

export async function requireUser() {
  const { supabase, user } = await getUser();
  if (!user) redirect("/login");
  return { supabase, user };
}

export async function requireOrg() {
  const { supabase, user } = await requireUser();
  const { data: membership } = await supabase
    .from("memberships")
    .select("organization_id, role, organizations(name)")
    .is("deleted_at", null)
    .limit(1)
    .maybeSingle();
  if (!membership) redirect("/onboarding");
  return {
    supabase,
    user,
    orgId: membership.organization_id as string,
    membership,
  };
}
__EOF__

# ---------------------------------------------------------------
cat > app/page.tsx << '__EOF__'
import { redirect } from "next/navigation";

export default function Home() {
  redirect("/dashboard");
}
__EOF__

# ---------------------------------------------------------------
cat > app/login/actions.ts << '__EOF__'
"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function signIn(formData: FormData) {
  const email = String(formData.get("email"));
  const password = String(formData.get("password"));
  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) redirect("/login?error=" + encodeURIComponent(error.message));
  redirect("/dashboard");
}

export async function signUp(formData: FormData) {
  const email = String(formData.get("email"));
  const password = String(formData.get("password"));
  const fullName = String(formData.get("full_name") || "");
  const supabase = await createClient();
  const { error } = await supabase.auth.signUp({
    email,
    password,
    options: { data: { full_name: fullName } },
  });
  if (error) redirect("/login?error=" + encodeURIComponent(error.message));
  redirect("/onboarding");
}

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/login");
}
__EOF__

# ---------------------------------------------------------------
cat > app/login/page.tsx << '__EOF__'
import { signIn, signUp } from "./actions";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;
  const input =
    "w-full rounded-md bg-neutral-900 border border-neutral-800 px-3 py-2 text-sm outline-none focus:border-amber-500";

  return (
    <main className="min-h-screen flex items-center justify-center bg-neutral-950 text-neutral-100 p-6">
      <div className="w-full max-w-sm space-y-8">
        <div className="text-center space-y-1">
          <h1 className="text-2xl font-semibold tracking-tight">
            Starfuel <span className="text-amber-400">PropertyOS</span>
          </h1>
          <p className="text-sm text-neutral-400">Sign in or create an account</p>
        </div>

        {error && (
          <p className="text-sm text-red-400 bg-red-950/40 border border-red-900 rounded-md p-3">
            {error}
          </p>
        )}

        <form action={signIn} className="space-y-3">
          <input name="email" type="email" required placeholder="Email" className={input} />
          <input name="password" type="password" required placeholder="Password" className={input} />
          <button className="w-full rounded-md bg-amber-500 text-neutral-950 font-medium py-2 text-sm hover:bg-amber-400">
            Sign in
          </button>
        </form>

        <form action={signUp} className="space-y-3 border-t border-neutral-800 pt-6">
          <p className="text-xs uppercase tracking-wide text-neutral-500">
            New here? Create an account
          </p>
          <input name="full_name" type="text" placeholder="Full name" className={input} />
          <input name="email" type="email" required placeholder="Email" className={input} />
          <input name="password" type="password" required placeholder="Password (min 6 chars)" className={input} />
          <button className="w-full rounded-md border border-amber-500 text-amber-400 font-medium py-2 text-sm hover:bg-amber-500/10">
            Create account
          </button>
        </form>
      </div>
    </main>
  );
}
__EOF__

# ---------------------------------------------------------------
cat > app/onboarding/actions.ts << '__EOF__'
"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function createOrg(formData: FormData) {
  const name = String(formData.get("name") || "").trim();
  if (!name) redirect("/onboarding?error=" + encodeURIComponent("Name is required"));
  const supabase = await createClient();
  const { error } = await supabase.rpc("create_organization", { p_name: name });
  if (error) redirect("/onboarding?error=" + encodeURIComponent(error.message));
  redirect("/dashboard");
}
__EOF__

# ---------------------------------------------------------------
cat > app/onboarding/page.tsx << '__EOF__'
import { redirect } from "next/navigation";
import { requireUser } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { createOrg } from "./actions";

export default async function OnboardingPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  await requireUser();
  const supabase = await createClient();
  const { data: existing } = await supabase
    .from("memberships")
    .select("organization_id")
    .is("deleted_at", null)
    .limit(1)
    .maybeSingle();
  if (existing) redirect("/dashboard");

  const { error } = await searchParams;
  const input =
    "w-full rounded-md bg-neutral-900 border border-neutral-800 px-3 py-2 text-sm outline-none focus:border-amber-500";

  return (
    <main className="min-h-screen flex items-center justify-center bg-neutral-950 text-neutral-100 p-6">
      <div className="w-full max-w-sm space-y-6">
        <div className="space-y-1">
          <h1 className="text-xl font-semibold">Create your organization</h1>
          <p className="text-sm text-neutral-400">
            This is your workspace. You can add properties, tenants, and your team inside it.
          </p>
        </div>
        {error && (
          <p className="text-sm text-red-400 bg-red-950/40 border border-red-900 rounded-md p-3">
            {error}
          </p>
        )}
        <form action={createOrg} className="space-y-3">
          <input name="name" required placeholder="Organization name" className={input} />
          <button className="w-full rounded-md bg-amber-500 text-neutral-950 font-medium py-2 text-sm hover:bg-amber-400">
            Create organization
          </button>
        </form>
      </div>
    </main>
  );
}
__EOF__

# ---------------------------------------------------------------
cat > app/_components/AppHeader.tsx << '__EOF__'
import Link from "next/link";
import { signOut } from "@/app/login/actions";

export default function AppHeader({ orgName }: { orgName: string }) {
  return (
    <header className="border-b border-neutral-800 bg-neutral-950">
      <div className="max-w-5xl mx-auto px-6 py-3 flex items-center justify-between">
        <div className="flex items-center gap-6">
          <span className="font-semibold text-amber-400">PropertyOS</span>
          <nav className="flex gap-4 text-sm text-neutral-300">
            <Link href="/dashboard" className="hover:text-white">Dashboard</Link>
            <Link href="/properties" className="hover:text-white">Properties</Link>
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
cat > app/dashboard/page.tsx << '__EOF__'
import Link from "next/link";
import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-lg border border-neutral-800 bg-neutral-900 p-5">
      <div className="text-3xl font-semibold">{value}</div>
      <div className="text-sm text-neutral-400 mt-1">{label}</div>
    </div>
  );
}

export default async function DashboardPage() {
  const { supabase, membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";

  const results = await Promise.all([
    supabase.from("properties").select("*", { count: "exact", head: true }).is("deleted_at", null),
    supabase.from("units").select("*", { count: "exact", head: true }).is("deleted_at", null),
    supabase
      .from("maintenance_requests")
      .select("*", { count: "exact", head: true })
      .is("deleted_at", null)
      .neq("status", "closed"),
  ]);
  const [properties, units, openReqs] = results.map((r) => r.count ?? 0);

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100">
      <AppHeader orgName={orgName} />
      <main className="max-w-5xl mx-auto px-6 py-8 space-y-6">
        <div className="flex items-center justify-between">
          <h1 className="text-xl font-semibold">Dashboard</h1>
          <Link
            href="/properties/new"
            className="rounded-md bg-amber-500 text-neutral-950 text-sm font-medium px-3 py-2 hover:bg-amber-400"
          >
            Add property
          </Link>
        </div>
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <Stat label="Properties" value={properties} />
          <Stat label="Units" value={units} />
          <Stat label="Open maintenance" value={openReqs} />
        </div>
      </main>
    </div>
  );
}
__EOF__

# ---------------------------------------------------------------
cat > app/properties/page.tsx << '__EOF__'
import Link from "next/link";
import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";

export default async function PropertiesPage() {
  const { supabase, membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";

  const { data: properties } = await supabase
    .from("properties")
    .select("id, name, address_line1, city, state, property_type")
    .is("deleted_at", null)
    .order("created_at", { ascending: false });

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100">
      <AppHeader orgName={orgName} />
      <main className="max-w-5xl mx-auto px-6 py-8 space-y-6">
        <div className="flex items-center justify-between">
          <h1 className="text-xl font-semibold">Properties</h1>
          <Link
            href="/properties/new"
            className="rounded-md bg-amber-500 text-neutral-950 text-sm font-medium px-3 py-2 hover:bg-amber-400"
          >
            Add property
          </Link>
        </div>

        {!properties || properties.length === 0 ? (
          <p className="text-neutral-400 text-sm">No properties yet. Add your first one.</p>
        ) : (
          <div className="grid gap-3">
            {properties.map((p: any) => (
              <div key={p.id} className="rounded-lg border border-neutral-800 bg-neutral-900 p-4">
                <div className="font-medium">{p.name}</div>
                <div className="text-sm text-neutral-400">
                  {p.address_line1}, {p.city}, {p.state}
                </div>
                <div className="text-xs text-amber-400/80 mt-1 uppercase tracking-wide">
                  {String(p.property_type).replace("_", " ")}
                </div>
              </div>
            ))}
          </div>
        )}
      </main>
    </div>
  );
}
__EOF__

# ---------------------------------------------------------------
cat > app/properties/actions.ts << '__EOF__'
"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { requireOrg } from "@/lib/auth";

export async function createProperty(formData: FormData) {
  const { supabase, orgId } = await requireOrg();
  const payload = {
    organization_id: orgId,
    name: String(formData.get("name")),
    address_line1: String(formData.get("address_line1")),
    city: String(formData.get("city")),
    state: String(formData.get("state")),
    postal_code: String(formData.get("postal_code")),
    property_type: String(formData.get("property_type") || "multi_family"),
  };
  const { error } = await supabase.from("properties").insert(payload);
  if (error) redirect("/properties/new?error=" + encodeURIComponent(error.message));
  revalidatePath("/properties");
  redirect("/properties");
}
__EOF__

# ---------------------------------------------------------------
cat > app/properties/new/page.tsx << '__EOF__'
import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";
import { createProperty } from "../actions";

export default async function NewPropertyPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";
  const { error } = await searchParams;
  const input =
    "w-full rounded-md bg-neutral-900 border border-neutral-800 px-3 py-2 text-sm outline-none focus:border-amber-500";

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100">
      <AppHeader orgName={orgName} />
      <main className="max-w-lg mx-auto px-6 py-8 space-y-6">
        <h1 className="text-xl font-semibold">Add property</h1>
        {error && (
          <p className="text-sm text-red-400 bg-red-950/40 border border-red-900 rounded-md p-3">
            {error}
          </p>
        )}
        <form action={createProperty} className="space-y-3">
          <input name="name" required placeholder="Property name" className={input} />
          <input name="address_line1" required placeholder="Street address" className={input} />
          <div className="grid grid-cols-2 gap-3">
            <input name="city" required placeholder="City" className={input} />
            <input name="state" required placeholder="State" className={input} />
          </div>
          <input name="postal_code" required placeholder="ZIP" className={input} />
          <select name="property_type" defaultValue="multi_family" className={input}>
            <option value="single_family">Single family</option>
            <option value="multi_family">Multi family</option>
            <option value="commercial">Commercial</option>
            <option value="mixed_use">Mixed use</option>
          </select>
          <button className="w-full rounded-md bg-amber-500 text-neutral-950 font-medium py-2 text-sm hover:bg-amber-400">
            Save property
          </button>
        </form>
      </main>
    </div>
  );
}
__EOF__

# ---------------------------------------------------------------
cat > supabase/migrations/0003_onboarding.sql << '__EOF__'
-- PropertyOS — 0003_onboarding.sql
-- A transactional helper to create an organization AND make the
-- current user its owner, in one atomic step. SECURITY DEFINER so it
-- can insert both rows, but it ties the membership to auth.uid(), so a
-- user can only ever make THEMSELVES an owner of a NEW org.

create or replace function create_organization(p_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_slug text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  v_slug := lower(regexp_replace(p_name, '[^a-zA-Z0-9]+', '-', 'g'))
            || '-' || substr(gen_random_uuid()::text, 1, 8);

  insert into organizations (name, slug)
  values (p_name, v_slug)
  returning id into v_org_id;

  insert into memberships (organization_id, user_id, role)
  values (v_org_id, auth.uid(), 'owner');

  return v_org_id;
end $$;

grant execute on function create_organization(text) to authenticated;
__EOF__

echo ""
echo "Done. Files created:"
echo "  middleware.ts"
echo "  lib/supabase/middleware.ts, lib/auth.ts"
echo "  app/page.tsx"
echo "  app/login/(page.tsx, actions.ts)"
echo "  app/onboarding/(page.tsx, actions.ts)"
echo "  app/dashboard/page.tsx"
echo "  app/properties/(page.tsx, new/page.tsx, actions.ts)"
echo "  app/_components/AppHeader.tsx"
echo "  supabase/migrations/0003_onboarding.sql"
echo ""
echo "Next: run 0003_onboarding.sql in Supabase, disable email confirmation, then 'npm run dev'."
