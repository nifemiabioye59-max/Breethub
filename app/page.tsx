import Link from "next/link";
import { Nav } from "../components/ui";

const stories = [
  {
    title: "The Last Promise",
    genre: "Love",
    country: "Nigeria",
  },
  {
    title: "Midnight Blood",
    genre: "Supernatural",
    country: "UK",
  },
  {
    title: "High Society Rules",
    genre: "Romance",
    country: "USA",
  },
];

const benefits = [
  {
    title: "Read",
    text: "Discover original stories from writers around the world, from free chapters to premium stories.",
  },
  {
    title: "Write",
    text: "Turn your ideas into stories, build your audience and grow as a creator.",
  },
  {
    title: "Earn",
    text: "Unlock real earning opportunities through approved reading, reviews, referrals and creator activities.",
  },
];

export default function Home() {
  return (
    <main className="page">
      <div className="container">
        <Nav />

        {/* HERO */}
        <section
          style={{
            padding: "70px 0 80px",
            maxWidth: "900px",
          }}
        >
          <div className="gold" style={{ letterSpacing: "3px", fontSize: "13px" }}>
            THE GLOBAL STORY & CREATOR PLATFORM
          </div>

          <h1
            style={{
              fontSize: "clamp(46px, 9vw, 86px)",
              lineHeight: "0.98",
              letterSpacing: "-4px",
              margin: "18px 0 25px",
            }}
          >
            Read.
            <br />
            Write.
            <br />
            <span className="cyan">Earn.</span>
          </h1>

          <p
            style={{
              color: "var(--muted)",
              fontSize: "20px",
              lineHeight: "1.7",
              maxWidth: "700px",
            }}
          >
            Breethub brings readers, writers, affiliates and brands together
            in one premium global platform built around stories,
            creativity and opportunity.
          </p>

          <div className="actions" style={{ marginTop: "30px" }}>
            <Link href="/auth/signup" className="btn btn-primary">
              Join Breethub
            </Link>

            <Link href="/read" className="btn btn-secondary">
              Explore stories
            </Link>
          </div>
        </section>

        {/* WHAT BREETHUB OFFERS */}
        <section className="section">
          <div className="gold" style={{ letterSpacing: "2px", fontSize: "12px" }}>
            ONE PLATFORM. THREE POSSIBILITIES.
          </div>

          <h2 style={{ fontSize: "34px", marginTop: "8px" }}>
            Your story can go further.
          </h2>

          <div
            style={{
              display: "grid",
              gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))",
              gap: "18px",
              marginTop: "25px",
            }}
          >
            {benefits.map((item) => (
              <div
                key={item.title}
                className="glass"
                style={{ padding: "28px", minHeight: "210px" }}
              >
                <div
                  className="cyan"
                  style={{
                    fontSize: "30px",
                    fontWeight: 800,
                    marginBottom: "18px",
                  }}
                >
                  {item.title}
                </div>

                <p
                  style={{
                    color: "var(--muted)",
                    lineHeight: "1.7",
                    margin: 0,
                  }}
                >
                  {item.text}
                </p>
              </div>
            ))}
          </div>
        </section>

        {/* WHY BREETHUB */}
        <section
          className="glass"
          style={{
            marginTop: "70px",
            padding: "40px",
          }}
        >
          <div className="gold" style={{ letterSpacing: "2px", fontSize: "12px" }}>
            BUILT FOR THE GLOBAL CREATIVE ECONOMY
          </div>

          <h2 style={{ fontSize: "34px", margin: "12px 0" }}>
            More than a place to read.
          </h2>

          <p
            style={{
              color: "var(--muted)",
              lineHeight: "1.8",
              maxWidth: "720px",
            }}
          >
            Breethub gives people different ways to participate. Readers
            discover stories. Writers build and monetize their work.
            Affiliates access approved earning opportunities. Advertisers
            connect with real audiences.
          </p>
        </section>

        {/* THREE STORY COVERS ONLY */}
        <section className="section">
          <div
            style={{
              display: "flex",
              justifyContent: "space-between",
              alignItems: "center",
              gap: "15px",
            }}
          >
            <div>
              <div className="gold" style={{ letterSpacing: "2px", fontSize: "12px" }}>
                A GLIMPSE INSIDE
              </div>

              <h2 style={{ fontSize: "30px", margin: "8px 0 0" }}>
                Featured stories
              </h2>
            </div>

            <Link href="/read" className="cyan">
              View all →
            </Link>
          </div>

          <div
            style={{
              display: "grid",
              gridTemplateColumns: "repeat(3, 1fr)",
              gap: "18px",
              marginTop: "25px",
            }}
          >
            {stories.map((story, index) => (
              <Link href="/read" key={story.title}>
                <div
                  className="glass"
                  style={{
                    aspectRatio: "2 / 3",
                    padding: "25px",
                    display: "flex",
                    flexDirection: "column",
                    justifyContent: "flex-end",
                    background:
                      index === 0
                        ? "linear-gradient(145deg, rgba(0,209,255,.18), rgba(212,175,55,.12))"
                        : index === 1
                        ? "linear-gradient(145deg, rgba(80,70,130,.35), rgba(0,209,255,.08))"
                        : "linear-gradient(145deg, rgba(212,175,55,.18), rgba(255,255,255,.05))",
                    transition: "transform .2s ease",
                  }}
                >
                  <div
                    className="gold"
                    style={{
                      fontSize: "10px",
                      letterSpacing: "2px",
                    }}
                  >
                    BREETHUB ORIGINAL
                  </div>

                  <strong
                    style={{
                      fontSize: "25px",
                      lineHeight: "1.1",
                      marginTop: "10px",
                    }}
                  >
                    {story.title}
                  </strong>

                  <span
                    style={{
                      color: "var(--muted)",
                      marginTop: "8px",
                      fontSize: "13px",
                    }}
                  >
                    {story.genre} · {story.country}
                  </span>
                </div>
              </Link>
            ))}
          </div>
        </section>

        {/* FINAL CTA */}
        <section
          className="glass"
          style={{
            marginTop: "70px",
            padding: "45px 30px",
            textAlign: "center",
          }}
        >
          <div className="gold">WELCOME TO BREETHUB</div>

          <h2 style={{ fontSize: "38px", margin: "12px 0" }}>
            Your next chapter starts here.
          </h2>

          <p
            style={{
              color: "var(--muted)",
              maxWidth: "600px",
              margin: "0 auto 25px",
              lineHeight: "1.7",
            }}
          >
            Whether you want to read, create or earn, Breethub gives you
            somewhere to start.
          </p>

          <Link href="/auth/signup" className="btn btn-primary">
            Create your account
          </Link>
        </section>
      </div>
    </main>
  );
}
