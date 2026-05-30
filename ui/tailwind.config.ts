import type { Config } from 'tailwindcss';

const config: Config = {
  content: ['./web/index.html', './web/src/**/*.{ts,tsx}'],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        // Brand accent — kept neutral so the UI feels at home in either
        // light or dark mode and doesn't look corporate-template.
        accent: {
          50: '#eef2ff',
          100: '#e0e7ff',
          500: '#6366f1',
          600: '#4f46e5',
          700: '#4338ca',
        },
      },
      fontFamily: {
        sans: ['system-ui', '-apple-system', 'Segoe UI', 'Inter', 'sans-serif'],
        mono: ['ui-monospace', 'SFMono-Regular', 'Cascadia Code', 'Menlo', 'monospace'],
      },
    },
  },
  plugins: [],
};

export default config;
