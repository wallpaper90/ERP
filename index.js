// Vercel serverless entry that wraps the TanStack Start SSR handler.
// Built output is produced by `vite build` (see vercel.json buildCommand).
import server from "../dist/server/server.js";

export const config = {
  runtime: "edge",
};

export default async function handler(request) {
  return server.fetch(request);
}
