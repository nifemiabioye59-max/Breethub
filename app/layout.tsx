import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Breethub — Read, Write, Earn",
  description:
    "Read stories, write, earn, discover creators, learn, and grow with Breethub.",
  metadataBase: new URL(
    process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000"
  ),
  openGraph: {
    title: "Breethub — Read, Write, Earn",
    description:
      "A global platform for readers, writers, creators, affiliates, advertisers and more.",
    type: "website"
  },
  twitter: {
    card: "summary_large_image",
    title: "Breethub — Read, Write, Earn",
    description:
      "A global platform for readers, writers, creators, affiliates, advertisers and more."
  }
};

export default function RootLayout({
  children
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
