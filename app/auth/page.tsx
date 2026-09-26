
"use client";

import Link from "next/link";
import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";
import { Nav } from "../../components/ui";
import { supabase } from "../../lib/supabase";

export default function AuthPage() {
  const router = useRouter();
  const [message, setMessage] = useState("");
  const [loading, setLoading] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setLoading(true);
    setMessage("");

    const form = new FormData(event.currentTarget);
    const email = String(form.get("email") || "");
    const password = String(form.get("password") || "");

    const { error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });

    if (error) {
      setMessage(error.message);
      setLoading(false);
      return;
    }

    router.push("/");
    router.refresh();
  }

  return (
    <main className="page">
      <div className="container">
        <Nav />

        <div
          className="glass"
          style={{
            maxWidth: 520,
            margin: "60px auto",
            padding: 28,
          }}
        >
          <div className="gold">Welcome back</div>
          <h1>Sign in to Breethub</h1>

          <form className="form" onSubmit={handleSubmit}>
            <div className="field">
              <label>Email</label>
              <input
                name="email"
                type="email"
                required
                placeholder="you@example.com"
              />
            </div>

            <div className="field">
              <label>Password</label>
              <input
                name="password"
                type="password"
                required
                placeholder="Your password"
              />
            </div>

            <button
              className="btn btn-primary"
              type="submit"
              disabled={loading}
            >
              {loading ? "Signing in..." : "Sign in"}
            </button>
          </form>

          {message && (
            <p className="muted" style={{ marginTop: 18 }}>
              {message}
            </p>
          )}

          <p className="muted" style={{ marginTop: 20 }}>
            Don't have an account?{" "}
            <Link href="/auth/signup" className="cyan">
              Create one
            </Link>
          </p>
        </div>
      </div>
    </main>
  );
}

