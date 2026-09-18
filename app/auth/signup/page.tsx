"use client";

import Link from "next/link";
import { Nav } from "../../../components/ui";
import { FormEvent, useState } from "react";

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

const roles = ["Reader", "Affiliate", "Writer", "Advertiser"];

export default function SignupPage() {
  const [role, setRole] = useState("Reader");
  const [message, setMessage] = useState("");

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    setMessage(
      "Demo account submitted. Connect Supabase Auth to create real accounts."
    );
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
            One account can participate in the Breethub ecosystem according to
            its selected role.
          </p>

          <form className="form" onSubmit={handleSubmit}>
            <div className="field">
              <label>Real name</label>
              <input required placeholder="Your real name" />
            </div>

            <div className="field">
              <label>Nickname</label>
              <input required placeholder="How you'd like to appear" />
            </div>

            <div className="field">
              <label>Email</label>
              <input
                type="email"
                required
                placeholder="you@example.com"
              />
            </div>

            <div className="field">
              <label>Password</label>
              <input
                type="password"
                required
                minLength={8}
                placeholder="At least 8 characters"
              />
            </div>

            <div className="field">
              <label>Phone number</label>
              <input
                type="tel"
                required
                placeholder="+234..."
              />
            </div>

            <div className="field">
              <label>Country</label>

              <select defaultValue="Nigeria">
                {countries.map((country) => (
                  <option key={country}>{country}</option>
                ))}
              </select>
            </div>

            <div className="field">
              <label>Your role</label>

              <select
                value={role}
                onChange={(event) => setRole(event.target.value)}
              >
                {roles.map((item) => (
                  <option key={item}>{item}</option>
                ))}
              </select>
            </div>

            <div className="glass" style={{ padding: 16 }}>
              <strong>Selected role: </strong>
              <span className="cyan">{role}</span>
            </div>

            <button type="submit" className="btn btn-primary">
              Create account
            </button>
          </form>

          {message && (
            <p className="muted" style={{ marginTop: 18 }}>
              {message}
            </p>
          )}

          <p className="muted" style={{ marginTop: 20 }}>
            Already registered?{" "}
            <Link href="/auth" className="cyan">
              Sign in
            </Link>
          </p>
        </div>
      </div>
    </main>
  );
}
