import Link from "next/link";
import { Nav, PageHeader } from "../../components/ui";

export default function CartPage() {
  return (
    <main className="page">
      <div className="container">
        <Nav />

        <PageHeader
          eyebrow="Your Cart"
          title="Ready when you are."
          description="Stories and other purchases you select will appear here."
        />

        <div
          className="glass"
          style={{
            padding: 35,
            textAlign: "center",
            maxWidth: 650,
            margin: "0 auto",
          }}
        >
          <div style={{ fontSize: 48 }}>🛒</div>

          <h2>Your cart is empty</h2>

          <p className="muted">
            Browse the story store and add chapters or complete stories to
            your cart.
          </p>

          <Link
            href="/read"
            className="btn btn-primary"
            style={{ marginTop: 12 }}
          >
            Browse stories
          </Link>
        </div>
      </div>
    </main>
  );
}
