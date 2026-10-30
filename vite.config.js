import { defineConfig } from 'vite';

// Relative base so the bundle loads from capacitor://localhost and file-like WebViews.
export default defineConfig({
  base: './',
  build: { target: 'es2020', chunkSizeWarningLimit: 1500 },
});
