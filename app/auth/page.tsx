"use client";

import Link from "next/link";
import { Nav } from "../../components/ui";
import { FormEvent, useState } from "react";

export default function AuthPage() {
  const [message, setMessage] = useState("");

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setMessage(
      "Demo sign-in submitted. Connect Supabase Auth to enable real authentication."
    );
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
              <input type="email" required placeholder="you@example.com" />
            </div>

            <div className="field">
              <label>Password</label>
              <input type="password" required placeholder="••••••••" />
            </div>

            <button className="btn btn-primary" type="submit">
              Sign in
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
