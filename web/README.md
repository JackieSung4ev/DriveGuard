# DriveGuard Web

Vue 3 + Vite frontend for the DriveGuard Web UI.

```bash
npm install
npm run dev
```

The development server proxies `/api` to `http://127.0.0.1:8080`. Auth APIs are real by default so login and logout state is not hidden by mock data.

For a standalone UI preview without the Go API service, use mock mode:

```bash
npm run dev:mock
```

```bash
npm run build
```
