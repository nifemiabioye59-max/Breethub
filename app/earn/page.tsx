import { Nav, PageHeader } from "../../components/ui";

export default function EarnPage() {
  return (
    <main className="page">
      <div className="container">
        <Nav />

        <PageHeader
          eyebrow="Affiliate Dashboard"
          title="Turn attention into earnings."
          description="Complete eligible reading activities, verified tasks and referrals to earn."
        />

        <section className="stats">
          <div className="glass stat">
            <span className="muted">Wallet</span>
            <strong>₦0</strong>
          </div>
          <div className="glass stat">
            <span className="muted">Today's tasks</span>
            <strong>0 / 3</strong>
          </div>
          <div className="glass stat">
            <span className="muted">Streak</span>
            <strong>0 days</strong>
          </div>
          <div className="glass stat">
            <span className="muted">Referrals</span>
            <strong>0</strong>
          </div>
        </section>

        <section className="section">
          <div className="glass notice">
            <strong>MANDATORY: Read 2 chapters today to unlock tasks</strong>
            <p className="muted">0 / 2 — Tasks are LOCKED until completed.</p>
          </div>
        </section>

        <section className="section grid">
          <div className="glass story-card">
            <h3>Task Feed</h3>
            <p className="muted">
              Read the required chapters first. Eligible verified tasks will
              appear here.
            </p>
            <button className="btn btn-secondary" disabled>
              Tasks locked
            </button>
          </div>

          <div className="glass story-card">
            <h3>Referral Program</h3>
            <p className="muted">
              Invite new users with your referral link and earn ₦2,000 per
              qualifying referral.
            </p>
            <button className="btn btn-primary">Get referral link</button>
          </div>

          <div className="glass story-card">
            <h3>Affiliate Courses</h3>
            <p className="muted">
              Learn mindset, career change, communication and human behaviour.
            </p>
            <button className="btn btn-secondary">Browse courses</button>
          </div>
        </section>
      </div>
    </main>
  );
}
