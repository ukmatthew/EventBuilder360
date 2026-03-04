# Event Builder 360 — Architecture

**Status:** Draft  
**References:** [4-ModularBuildPlan.md](4-ModularBuildPlan.md) (Cross-cutting concerns)

This document describes the high-level architecture: User App(s), our API, Database, and server-side processing. It is the single place for the **architecture diagram** and the rationale behind it.

---

## Main elements

| Element | Description |
|--------|-------------|
| **User App** | iOS, Android, Web. The only client-facing surface; all data and actions go through our API (no direct DB access from clients). |
| **API** | Our own API. Secures and authenticates all client access; exposes endpoints for directory, schedule, booking, ticketing, etc. |
| **Database** | Persistent store for events, venues, sessions, users, bookings, and all other domain data. Single instance for now; see [6-DatabaseSchema.md](6-DatabaseSchema.md) for schema and future scaling. |
| **Server-side processing** | Backend logic that shouldn’t run in the client or in a single request/response. Medium term: **Lambda** (or similar) for things like booking workflows, data fetching from external systems, and heavy or sensitive operations. |

---

## Architecture diagram

```mermaid
flowchart TB
    subgraph Clients["User App"]
        IOS[iOS App]
        Android[Android App]
        Web[Web App]
    end

    subgraph OurSystem["Event Builder 360"]
        API[Our API\n(authenticated, secure)]
        Lambda[Server-side processing\n(e.g. Lambda)]
        DB[(Database)]
    end

    IOS --> API
    Android --> API
    Web --> API

    API --> Lambda
    API --> DB
    Lambda --> DB
```

**Flow (example — Session Booking):**

1. User taps “Book session” in the app (iOS / Android / Web).
2. App sends an authenticated request to our API: e.g. `POST /bookSession` (or `bookSession` in a unified API).
3. API validates the user and calls server-side processing (e.g. invokes a Lambda).
4. Lambda (or equivalent) runs the booking workflow: decrease available seats, update busy status, write audit/log, any other side effects.
5. Lambda reads/writes the Database as needed; API returns a success or error response to the client.
6. Client never talks to the Database or Lambda directly — only to the API.

---

## Decisions and rationale

- **Our own API** — Gives us a single, secure boundary. We can add rate limiting, auth, and richer features (ticketing, booking) without exposing the database or internal services to clients.
- **Lambda for back-end processing** — Keeps request/response fast and stateless; booking, integrations, and heavy work run in a controlled, scalable way. We can adopt this in the medium term as we add features like Session Booking.
- **Single database (for now)** — Simplifies the prototype and MVP. Schema and scaling (e.g. separate DBs for Auth, large events, ticketing) are documented and decided over time in [6-DatabaseSchema.md](6-DatabaseSchema.md).

---

*Update this diagram and narrative as we add or change components (e.g. message queues, caches, or separate services).*
