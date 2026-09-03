/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter', '-apple-system', 'BlinkMacSystemFont', 'Segoe UI', 'sans-serif'],
      },
      colors: {
        brand: '#4F8EF7',
        'brand-dark': '#2D6BE4',
        surface: '#0D1117',
        'surface-2': '#111620',
        'surface-3': '#161B26',
        'surface-4': '#1C2333',
        border: 'rgba(255,255,255,0.07)',
        muted: '#64748B',
        subtle: '#94A3B8',
        primary: '#E2E8F0',
        secondary: '#CBD5E1',
      },
    },
  },
  plugins: [],
}
