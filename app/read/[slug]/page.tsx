
import Link from "next/link";
import { Nav } from "../../../components/ui";

const stories: Record<
  string,
  { title: string; genre: string; country: string; chapter: string }
> = {
  "the-last-promise": {
    title: "The Last Promise",
    genre: "Love",
    country: "Nigeria",
    chapter:
      "The rain fell softly against the window as Amara unfolded the letter she had kept hidden for years. Three words stared back at her: I will return. She had waited long enough, but tonight, everything was about to change.",
  },
  "midnight-blood": {
    title: "Midnight Blood",
    genre: "Supernatural",
    country: "Ghana",
    chapter:
      "The clock struck midnight, and the forest fell silent. Kofi felt a strange chill crawl down his spine. Something was watching him from the shadows, and it knew his name.",
  },
  "high-society-rules": {
    title: "High Society Rules",
    genre: "High Society",
    country: "USA",
    chapter:
      "The ballroom glittered beneath golden chandeliers. Everyone smiled, but Elena knew that behind every smile was a secret. Tonight, she would discover who had betrayed her family.",
  },
  "campus-hearts": {
    title: "Campus Hearts",
    genre: "Romance",
    country: "Kenya",
    chapter:
      "Maya rushed across campus, clutching her books. She turned a corner and collided with a stranger. Her notes scattered everywhere, and when she looked up, he was smiling at her.",
  },
  "moon-magic": {
    title: "Moon Magic",
    genre: "Fantasy",
    country: "UK",
    chapter:
      "Under the silver moon, Lily discovered a glowing symbol on her palm. The old book had been right. Her magic had finally awakened, and the world would never be the same.",
  },
  "after-the-war": {
    title: "After the War",
    genre: "Historical",
    country: "Nigeria",
    chapter:
      "When the fighting ended, the village stood in silence. Amina returned to the home she barely recognized, carrying only a small bag and the hope of finding her brother alive.",
  },
  "her-secret": {
    title: "Her Secret",
    genre: "Drama",
    country: "USA",
    chapter:
      "Every morning, Grace wore the same smile. Nobody knew about the letters hidden beneath her floorboards or the truth she had promised never to reveal.",
  },
  "his-secret": {
    title: "His Secret",
    genre: "Drama",
    country: "UK",
    chapter:
      "Daniel had built his life around one carefully guarded secret. But when an old friend appeared at his door, the past came rushing back.",
  },
  "broken-crown": {
    title: "Broken Crown",
    genre: "Dark Romance",
    country: "Ghana",
    chapter:
      "The crown lay shattered on the marble floor. Princess Adjoa stared at it, knowing that the kingdom she had fought to protect was slipping away.",
  },
  "panel-one": {
    title: "Panel One",
    genre: "Comics",
    country: "Nigeria",
    chapter:
      "The city lights flickered as a mysterious figure landed on the rooftop. A single message flashed across the hero's screen: Your time is up.",
  },
  "the-heir": {
    title: "The Heir",
    genre: "High Society",
    country: "Kenya",
    chapter:
      "The lawyer placed a sealed envelope on the table. Inside was a name that would change everything. Nia was the unexpected heir to a fortune she never knew existed.",
  },
  "forever-us": {
    title: "Forever Us",
    genre: "Romance",
    country: "USA",
    chapter:
      "After five years apart, Olivia saw Noah standing across the street. The city seemed to fade around them. Some stories, she realized, were never truly over.",
  },
};

export default function StoryPage({
  params,
}: {
  params: { slug: string };
}) {
  const story = stories[params.slug];

  if (!story) {
    return (
      <main className="page">
        <div className="container">
          <Nav />
          <div className="glass notice">
            <h1>Story not found</h1>
            <p className="muted">
              This story is not available yet.
            </p>
            <Link href="/read" className="btn btn-primary">
              Back to stories
            </Link>
          </div>
        </div>
      </main>
    );
  }

  return (
    <main className="page">
      <div className="container">
        <Nav />

        <article className="glass" style={{ padding: 28, marginTop: 30 }}>
          <Link href="/read" className="cyan">
            ← Back to stories
          </Link>

          <div className="gold" style={{ marginTop: 24 }}>
            {story.genre} · {story.country}
          </div>

          <h1 style={{ marginTop: 12 }}>{story.title}</h1>

          <div className="muted" style={{ marginTop: 12 }}>
            Chapter 1 · The Beginning
          </div>

          <div
            style={{
              lineHeight: 2,
              fontSize: 18,
              marginTop: 28,
              whiteSpace: "pre-wrap",
            }}
          >
            {story.chapter}
          </div>

          <div className="glass notice" style={{ marginTop: 30 }}>
            <h3>You've reached the end of Chapter 1</h3>
            <p className="muted">
              Chapter 2 is not available yet.
            </p>
            <Link href="/read" className="btn btn-primary">
              Explore more stories
            </Link>
          </div>
        </article>
      </div>
    </main>
  );
}
