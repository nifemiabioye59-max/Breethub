"use client";

import Link from "next/link";
import { FormEvent, useState } from "react";
import { Nav } from "../../../components/ui";
import { supabase } from "../../../lib/supabase";

const countries = [
  "Nigeria",
  "Ghana",
  "Kenya",
  "United States",
  "United Kingdom",
  "South Africa",
  "Canada",
  "Other",
];

const roles = [
  "reader",
  "affiliate",
  "writer",
  "advertiser",
];

export default function SignupPage() {
  const [role, setRole] = useState("reader");
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    setLoading(true);
    setMessage("");

    const form = new FormData(event.currentTarget);

    const realName = String(form.get("real_name") || "");
    const nickname = String(form.get("nickname") || "");
    const email = String(form.get("email") || "");
    const password = String(form.get("password") || "");
    const phone = String(form.get("phone") || "");
    const country = String(form.get("country") || "");

    try {
      const { data, error } = await supabase.auth.signUp({
        email,
        password,
        options: {
          data: {
            real_name: realName,
            nickname,
            phone,
            country,
            role,
          },
        },
      });

      if (error) {
        throw error;
      }

      if (!data.user) {
        throw new Error("Account could not be created.");
      }

      setMessage(
        "Account created. Check your email if email confirmation is enabled."
      );
    } catch (error) {
      setMessage(
        error instanceof Error
          ? error.message
          : "Something went wrong."
      );
    } finally {
      setLoading(false);
    }
  }

  return (
    <main className="page">
      <div className="container">
        <Nav />

        <div
          className="glass"
          style={{
            maxWidth: 650,
            margin: "30px auto",
            padding: 28,
          }}
        >
          <div className="gold">Join Breethub</div>

          <h1>Create your account</h1>

          <p className="muted">
            Create your Breethub account and choose how you want to
            participate.
          </p>

          <form className="form" onSubmit={handleSubmit}>
            <div className="field">
              <label>Real name</label>
              <input
                name="real_name"
                required
                placeholder="Your real name"
              />
            </div>

            <div className="field">
              <label>Nickname</label>
              <input
                name="nickname"
                required
                placeholder="Your display name"
              />
            </div>

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
                minLength={8}
                placeholder="At least 8 characters"
              />
            </div>

            <div className="field">
              <label>Phone number</label>
              <input
                name="phone"
                type="tel"
                required
                placeholder="+234..."
              />
            </div>

            <div className="field">
              <label>Country</label>

              <select name="country" defaultValue="Nigeria">
                {countries.map((country) => (
                  <option key={country} value={country}>
                    {country}
                  </option>
                ))}
              </select>
            </div>

            <div className="field">
              <label>Account role</label>

              <select
                value={role}
                onChange={(event) => setRole(event.target.value)}
              >
                {roles.map((item) => (
                  <option key={item} value={item}>
                    {item.charAt(0).toUpperCase() + item.slice(1)}
                  </option>
                ))}
              </select>
            </div>

            <button
              type="submit"
              className="btn btn-primary"
              disabled={loading}
            >
              {loading ? "Creating account..." : "Create account"}
            </button>
          </form>

          {message && (
            <div className="glass notice" style={{ marginTop: 18 }}>
              {message}
            </div>
          )}

          <p className="muted" style={{ marginTop: 20 }}>
            Already have an account?{" "}
            <Link href="/auth" className="cyan">
              Sign in
            </Link>
          </p>
        </div>
      </div>
    </main>
  );
}
