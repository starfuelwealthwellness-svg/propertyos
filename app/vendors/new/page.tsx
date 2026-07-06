import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";
import SubmitButton from "@/app/_components/SubmitButton";
import { createVendor } from "../actions";

export default async function NewVendorPage({
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
        <h1 className="text-xl font-semibold">Add vendor</h1>
        {error && (
          <p className="text-sm text-red-400 bg-red-950/40 border border-red-900 rounded-md p-3">
            {error}
          </p>
        )}
        <form action={createVendor} className="space-y-3">
          <input name="name" required placeholder="Vendor name" className={input} />
          <input name="trade" placeholder="Trade (e.g. plumbing, electrical)" className={input} />
          <input name="email" type="email" placeholder="Email (optional)" className={input} />
          <input name="phone" type="tel" placeholder="Phone (optional)" className={input} />
          <SubmitButton className="w-full rounded-md bg-amber-500 text-neutral-950 font-medium py-2 text-sm hover:bg-amber-400">
            Save vendor
          </SubmitButton>
        </form>
      </main>
    </div>
  );
}
