import { Nav, StoryCard, PageHeader } from "../../components/ui";

const stories = [
  ["The Last Promise", "Love", "🇳🇬 Nigeria", "12.4k", "₦300"],
  ["Midnight Blood", "Supernatural", "🇬🇭 Ghana", "9.8k", "₦500"],
  ["High Society Rules", "High Society", "🇺🇸 USA", "8.1k", "₦400"],
  ["Campus Hearts", "High School Romance", "🇰🇪 Kenya", "7.5k", "₦300"],
  ["Moon Magic", "Magic", "🇬🇧 UK", "6.9k", "₦500"],
  ["After the War", "Historical", "🇳🇬 Nigeria", "5.4k", "₦700"],
  ["Her Secret", "Lesbian", "🇺🇸 USA", "4.8k", "₦400"],
  ["His Secret", "Gay", "🇬🇧 UK", "4.2k", "₦400"],
  ["Broken Crown", "Dark Romance", "🇬🇭 Ghana", "3.9k", "₦500"],
  ["Panel One", "Comics", "🇳🇬 Nigeria", "3.4k", "₦300"],
  ["The Heir", "High Society", "🇰🇪 Kenya", "2.8k", "₦500"],
  ["Forever Us", "Love", "🇺🇸 USA", "2.1k", "₦300"],
];

export default function ReadPage() {
  return (
    <main className="page">
      <div className="container">
        <Nav />

        <PageHeader
          eyebrow="Reader Space"
          title="Find your next story."
          description="Explore stories from creators around the world. Chapter 1 is free on every story."
        />

        <div className="glass" style={{ padding: 18, marginBottom: 20 }}>
          <div className="actions">
            <button className="btn btn-primary">All genres</button>
            <button className="btn btn-secondary">All countries</button>
            <button className="btn btn-secondary">Trending</button>
            <button className="btn btn-secondary">Newest</button>
          </div>
        </div>

        <div className="grid">
          {stories.map(([title, genre, country, views, price]) => (
            <StoryCard
              key={title}
              title={title}
              genre={genre}
              country={country}
              views={views}
              price={price}
            />
          ))}
        </div>
      </div>
    </main>
  );
}
