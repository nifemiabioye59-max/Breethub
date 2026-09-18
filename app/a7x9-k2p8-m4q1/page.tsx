import { Nav, PageHeader } from "../../components/ui";

const adminSections = [
  {
    title: "Story Review",
    description: "Review submitted stories before publication.",
  },
  {
    title: "Task Approval",
    description: "Review submitted task proofs and approve eligible earnings.",
  },
  {
    title: "Users",
    description: "Manage users, roles and account status.",
  },
  {
    title: "Courses",
    description: "Create and manage affiliate and writer courses.",
  },
  {
    title: "Country Pricing",
    description: "Configure product pricing by supported currency and country.",
  },
  {
    title: "Disputes",
    description: "Review purchase, campaign and task disputes.",
  },
  {
    title: "Broadcast",
    description: "Send platform announcements and notifications.",
  },
  {
    title: "Syndication",
    description: "Track external story distribution and writer earnings.",
  },
];

export default function AdminPage() {
  return (
    <main className="page">
      <div className="container">
        <Nav />

        <PageHeader
          eyebrow="Control Center"
          title="Breethub Admin"
          description="Platform operations, moderation, earnings and content management."
        />

        <div className="glass notice">
          <strong>AI Co-Pilot</strong>
          <p className="muted">
            3 stories pending · affiliate earnings increased 40% · 2 disputes
            awaiting review.
          </p>
        </div>

        <section className="section stats">
          <div className="glass stat">
            <span className="muted">Pending stories</span>
            <strong>3</strong>
          </div>

          <div className="glass stat">
            <span className="muted">Pending tasks</span>
            <strong>12</strong>
          </div>

          <div className="glass stat">
            <span className="muted">Disputes</span>
            <strong>2</strong>
          </div>

          <div className="glass stat">
            <span className="muted">Users</span>
            <strong>10k+</strong>
          </div>
        </section>

        <section className="section grid">
          {adminSections.map((section) => (
            <article className="glass story-card" key={section.title}>
              <h3>{section.title}</h3>
              <p className="muted">{section.description}</p>
              <button className="btn btn-secondary">
                Open
              </button>
            </article>
          ))}
        </section>

        <section className="section glass" style={{ padding: 24 }}>
          <h2>Security reminder</h2>
          <p className="muted">
            This route is intentionally obscure, but the URL itself must
            never be treated as security. Production access must be enforced
            server-side using an admin role/claim and two-factor
            authentication.
          </p>
        </section>
      </div>
    </main>
  );
}
