import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    strictPort: true,
  },
  preview: {
    port: 4173,
    strictPort: true,
  },
  test: {
    environment: "jsdom",
    exclude: ["node_modules", "dist", "e2e"],
    globals: true,
    setupFiles: "./tests/setup.ts",
    css: true,
  },
});
