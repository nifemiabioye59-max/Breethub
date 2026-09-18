"use client";

import { Nav, PageHeader } from "../../components/ui";
import { useState } from "react";

export default function AdvertisePage() {
  const [accepted, setAccepted] = useState(false);

  return (
    <main className="page">
      <div className="container">
        <Nav />

        <PageHeader
          eyebrow="Advertise"
          title="Get real human attention."
          description="Create campaigns for genuine views and genuine comments from real people."
        />

        <div className="glass notice">
          <strong>10k+ engaging</strong>
          <p className="muted">
            Breethub campaigns are designed for real human patronage, not fake
            followers or bots.
          </p>
        </div>

        <section className="section glass" style={{ padding: 24 }}>
          <h2>Post a Link</h2>

          <form className="form" style={{ marginTop: 20 }}>
            <div className="field">
              <label>Content link</label>
              <input
                type="url"
                placeholder="https://instagram.com/... or your website"
              />
            </div>

            <div className="field">
              <label>Platform</label>
              <select defaultValue="instagram">
                <option value="instagram">Instagram</option>
                <option value="tiktok">TikTok</option>
                <option value="website">Website</option>
                <option value="app">App</option>
              </select>
            </div>

            <div className="field">
              <label>Engagement type</label>
              <select defaultValue="human">
                <option value="human">
                  Real human view + genuine comment
                </option>
              </select>
            </div>

            <div className="field">
              <label>Countries</label>
              <input placeholder="Nigeria, Ghana, Kenya..." />
            </div>

            <div className="field">
              <label>Number of people</label>
              <input type="number" min="1" placeholder="100" />
            </div>

            <div className="field">
              <label>Price per engagement</label>
              <input type="number" min="200" placeholder="₦200 minimum" />
            </div>

            <label className="muted">
              <input
                type="checkbox"
                checked={accepted}
                onChange={(e) => setAccepted(e.target.checked)}
                style={{ marginRight: 8 }}
              />
              I want real human patronage, not fake followers — I understand
              this is not bot followers, but real people viewing my content.
            </label>

            <button
              type="button"
              className="btn btn-primary"
              disabled={!accepted}
            >
              Deposit & Pay
            </button>
          </form>
        </section>
      </div>
    </main>
  );
}
