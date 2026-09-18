import Link from "next/link";

export function Logo() {
  return (
    <Link href="/" className="logo">
      <span className="gold">Breet</span>
      <span>hub</span>
    </Link>
  );
}

export function Nav() {
  return (
    <nav className="nav">
      <Logo />

      <div className="nav-links">
        <Link href="/read">Read</Link>
        <Link href="/earn">Earn</Link>
        <Link href="/write">Write</Link>
        <Link href="/advertise">Advertise</Link>
        <Link href="/courses">Courses</Link>
        <Link href="/cart">Cart</Link>
      </div>

      <div className="actions">
        <Link href="/auth" className="btn btn-secondary">
          Sign in
        </Link>
        <Link href="/auth/signup" className="btn btn-primary">
          Join
        </Link>
      </div>
    </nav>
  );
}

export function StoryCard({
  title,
  genre,
  country,
  views,
  price,
}: {
  title: string;
  genre: string;
  country: string;
  views: string;
  price: string;
}) {
  return (
    <article className="glass story-card">
      <div className="cover">📖</div>
      <h3>{title}</h3>
      <div className="story-meta">
        {genre} · {country}
      </div>
      <div className="story-meta" style={{ marginTop: 8 }}>
        {views} views · From {price}
      </div>
      <div style={{ marginTop: 15 }}>
        <Link href="/read" className="btn btn-primary">
          Read Chapter 1
        </Link>
      </div>
    </article>
  );
}

export function PageHeader({
  eyebrow,
  title,
  description,
}: {
  eyebrow: string;
  title: string;
  description: string;
}) {
  return (
    <div className="hero">
      <div className="gold">{eyebrow}</div>
      <h1>{title}</h1>
      <p>{description}</p>
    </div>
  );
}
