// Single entrypoint: starts a Node HTTP server. Used by `npm run dev` locally,
// by Docker Compose, and by Railway in production (Dockerfile CMD).

import { createApp } from "./app.js";

const port = Number(process.env.PORT ?? 3000);
const app = createApp();

app.listen(port, () => {
  console.log(`libolibo-api: слушаю http://localhost:${port}`);
});
