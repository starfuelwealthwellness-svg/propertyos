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
