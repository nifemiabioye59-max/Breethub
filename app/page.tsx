import Link from "next/link";

export default function HomePage() {
  return (
    <main className="min-h-screen px-5 py-6 sm:px-8 lg:px-12">
      <nav className="mx-auto flex max-w-7xl items-center justify-between">
        <Link
          href="/"
          className="text-xl font-bold tracking-tight text-[#D6B06A]"
        >
          Breethub
        </Link>

        <div className="flex items-center gap-2">
          <Link href="/auth" className="secondary-button text-sm">
            Sign in
          </Link>

          <Link href="/auth/signup" className="primary-button text-sm">
            Join Breethub
          </Link>
        </div>
      </nav>

      <section className="mx-auto flex min-h-[75vh] max-w-5xl items-center justify-center text-center">
        <div className="animate-fade-up">
          <p className="mb-5 text-sm uppercase tracking-[0.35em] text-[#C9BBC0]">
            Read · Write · Earn
          </p>

          <h1 className="gold-text text-5xl font-black leading-tight sm:text-7xl">
            Stories have a home.
          </h1>

          <p className="mx-auto mt-6 max-w-2xl text-base leading-8 text-[#C9BBC0] sm:text-lg">
            Breethub connects readers, writers, creators, affiliates,
            advertisers and communities through stories, learning and
            opportunities.
          </p>

          <div className="mt-9 flex flex-wrap justify-center gap-3">
            <Link href="/read" className="primary-button">
              Discover stories
            </Link>

            <Link href="/auth/signup" className="secondary-button">
              Create an account
            </Link>
          </div>
        </div>
      </section>
    </main>
  );
}
