/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ["./app/**/*.{js,jsx,ts,tsx}", "./components/**/*.{js,jsx,ts,tsx}"],
  presets: [require("nativewind/preset")],
  theme: {
    extend: {
      colors: {
        // Mirror the daisyUI OKLCH palette from assets/css/app.css as hex approximations
        primary: "#7c3aed",
        "primary-content": "#f5f3ff",
        secondary: "#7c3aed",
        "secondary-content": "#f5f3ff",
        accent: "#9333ea",
        "accent-content": "#faf5ff",
        base: {
          100: "#1e1b4b",
          200: "#18162f",
          300: "#110e24",
        },
      },
      fontFamily: {
        sans: ["System"],
      },
    },
  },
  plugins: [],
};
