import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'node:path';

// Vite config for the React frontend.
// - Source root: ./web
// - Build output: ./web/dist (served by Express in production)
// - Dev mode proxies /api/* to the Express server on the same port (8765) when
//   we run `npm run dev` (vite dev server on 5173, server on 8765).
const UI_PORT = Number(process.env.NIGHTINGALE_UI_PORT ?? 8765);

export default defineConfig({
  root: path.resolve(__dirname, 'web'),
  plugins: [react()],
  server: {
    port: 5173,
    host: '127.0.0.1',
    proxy: {
      '/api': `http://127.0.0.1:${UI_PORT}`,
    },
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    sourcemap: false,
    rollupOptions: {
      output: {
        manualChunks: {
          vendor: ['react', 'react-dom', 'react-router-dom'],
          query: ['@tanstack/react-query'],
          markdown: ['marked', 'isomorphic-dompurify'],
        },
      },
    },
  },
});
