import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
    "./lib/**/*.{js,ts,jsx,tsx,mdx}"
  ],
  theme: {
    extend: {
      colors: {
        breethub: {
          background: "#171218",
          surface: "#211922",
          plum: "#3A2636",
          gold: "#D6B06A",
          goldSoft: "#E8CC91",
          ivory: "#FFF8ED",
          muted: "#C9BBC0",
          success: "#7FB89A",
          danger: "#D77A7A"
        }
      },
      borderRadius: {
        glass: "24px"
      },
      boxShadow: {
        glass: "0 20px 60px rgba(0,0,0,0.28)"
      }
    }
  },
  plugins: []
};

export default config;
