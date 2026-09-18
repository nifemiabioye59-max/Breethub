import { Nav, PageHeader } from "../../components/ui";

export default function WritePage() {
  return (
    <main className="page">
      <div className="container">
        <Nav />

        <PageHeader
          eyebrow="Writer Studio"
          title="Build stories people remember."
          description="Complete the Writer Course to unlock AI tools, comic creation, ghost jobs and publishing."
        />

        <div className="glass notice">
          <strong>Writer Course Required</strong>
          <p className="muted">
            Complete Ghostwriting Mastery and pass the 80% assessment to
            unlock the Free 3-Day AI Intense Bootcamp.
          </p>
          <button className="btn btn-primary">Start Writer Course</button>
        </div>

        <section className="section grid">
          <div className="glass story-card">
            <h3>🎨 Comic Studio</h3>
            <p className="muted">
              Build panels, add speech bubbles and prepare comic exports.
            </p>
            <button className="btn btn-secondary" disabled>
              Locked
            </button>
          </div>

          <div className="glass story-card">
            <h3>✍️ AI Writing Lab</h3>
            <p className="muted">
              Brainstorm titles, outlines, drafts, characters and marketing
              copy.
            </p>
            <button className="btn btn-secondary" disabled>
              Locked
            </button>
          </div>

          <div className="glass story-card">
            <h3>💼 Order Board</h3>
            <p className="muted">
              Browse ghostwriting jobs ranging from $40–$200 and submit bids.
            </p>
            <button className="btn btn-secondary" disabled>
              Locked
            </button>
          </div>

          <div className="glass story-card">
            <h3>📚 My Stories</h3>
            <p className="muted">
              Track views, earnings, tips and publishing status.
            </p>
            <button className="btn btn-secondary" disabled>
              Locked
            </button>
          </div>
        </section>
      </div>
    </main>
  );
}
