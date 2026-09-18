import Link from "next/link";
import { Nav, StoryCard } from "../components/ui";

const stories = [
  {
    title: "The Last Promise",
    genre: "Love",
    country: "🇳🇬 Nigeria",
    views: "12.4k",
    price: "₦300",
  },
  {
    title: "Midnight Blood",
    genre: "Supernatural",
    country: "🇬🇧 UK",
    views: "9.8k",
    price: "₦500",
  },
  {
    title: "High Society Rules",
    genre: "Romance",
    country: "🇺🇸 USA",
    views: "8.1k",
    price: "₦400",
  },
];

export default function Home() {
  return (
    <main className="page">
      <div className="container">
        <Nav />

        <section className="hero">
          <div className="gold">A global creative platform</div>
          <h1>
            Read stories.
            <br />
            Write boldly.
            <br />
            <span className="cyan">Earn fairly.</span>
          </h1>

          <p>
            Breethub connects readers, writers, affiliates and advertisers in
            one premium global creative ecosystem.
          </p>

          <div className="actions">
            <Link href="/read" className="btn btn-primary">
              Explore stories
            </Link>
            <Link href="/auth/signup" className="btn btn-secondary">
              Create account
            </Link>
          </div>
        </section>

        <section className="stats">
          <div className="glass stat">
            <span className="muted">Readers</span>
            <strong>10k+</strong>
          </div>
          <div className="glass stat">
            <span className="muted">Stories</span>
            <strong>1,200+</strong>
          </div>
          <div className="glass stat">
            <span className="muted">Countries</span>
            <strong>30+</strong>
          </div>
          <div className="glass stat">
            <span className="muted">Creator economy</span>
            <strong>$50k</strong>
          </div>
        </section>

        <section className="section">
          <div className="section-title">
            <h2>Trending stories</h2>
            <Link href="/read" className="cyan">
              View all →
            </Link>
          </div>

          <div className="grid">
            {stories.map((story) => (
              <StoryCard key={story.title} {...story} />
            ))}
          </div>
        </section>
      </div>
    </main>
  );
}
