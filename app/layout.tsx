import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Breethub — Read, Write, Earn",
  description:
    "A global platform for readers, writers, affiliates and advertisers.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
