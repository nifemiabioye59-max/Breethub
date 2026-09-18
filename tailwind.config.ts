import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        navy: "#0A1931",
        gold: "#D4AF37",
        cyan: "#00D1FF",
      },
      borderRadius: {
        glass: "24px",
      },
    },
  },
  plugins: [],
};

export default config;
