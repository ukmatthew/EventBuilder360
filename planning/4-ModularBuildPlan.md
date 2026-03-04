# Event Builder 360 — Provisional Modular Build Plan

**Status:** Draft for discussion  
**References:** [EventBuilder360TheApp.md](EventBuilder360TheApp.md), [1-HighLevelPlan.md](1-HighLevelPlan.md)

This document outlines a way to build Event Builder 360 in **modules** — discrete, shippable units that can be developed, tested, and (where intended) open-sourced independently, while still composing into one product.

---

## 1. What “modular” means here

- **Module** = a coherent slice of the product (feature area + its data and APIs), with clear boundaries and a minimal surface to the rest of the app.
- Modules are chosen so that:
  - We can ship **incrementally** (Simple Directory → MVP → full ecosystem).
  - Dependencies between modules are explicit and kept small.
  - Later phases can add or replace modules without rewriting the core.

---

## 2. Alignment with the vision stages

From the vision doc, we have three main stages:

| Stage | Focus | Outcome |
|-------|--------|---------|
| **Seed / Simple Directory** | Event directory, schedule, session detail, add activities, basic community contributions | Proof of concept, usability, flexibility |
| **MVP** | User profiles, saved schedules, ratings/notes, basic networking, organizer dashboards, real-time updates, multi-event support | Viable product for indie conferences, festivals, corporate events |
| **Beyond MVP** | Advanced community, commerce & logistics, intelligence layer, multi-event identity | Full event ecosystem |

The modular plan below maps each stage to a set of modules and suggests a build order.

---

## 3. Proposed modules by stage

### Stage 1 — Seed / Simple Directory (Prototype)

| Module | Description | Key boundaries |
|--------|--------------|----------------|
| **Event & venue core** | Single event + venues; event metadata, venue list, basic structure | No multi-event yet; no user accounts |
| **Schedule** | Sessions/activities tied to event + venue; times, locations, simple list and detail views | Read-first; “add activities” as simple create (e.g. organizer or demo flow) |
| **Session detail** | Single session/activity page: title, description, time, place, links | Consumes schedule data only |
| **Simple directory UI** | Browse events → venues → schedule → session detail; navigation and layout | Presentation only; delegates to the above |
| **Basic contributions** | e.g. tips, notes, or one simple UGC type attached to a session or venue | Minimal schema; no user identity beyond optional display name |

**Build order suggestion:** Event & venue core → Schedule → Session detail → Directory UI → Basic contributions.

---

### Stage 2 — MVP

| Module | Description | Depends on |
|--------|--------------|------------|
| **Identity & profiles** | User accounts, auth, basic profile (name, avatar, bio) | — |
| **Saved schedules** | “My schedule” — save/unsave sessions per user | Identity, Schedule |
| **Ratings & notes** | Star ratings and text notes on sessions; owned by user | Identity, Schedule |
| **Basic networking** | e.g. follow attendees, see “who’s going” to a session (opt-in) | Identity, Schedule |
| **Organizer dashboard** | Content management for one event: edit sessions, venues, publish/unpublish | Identity, Event & venue core, Schedule |
| **Real-time updates** | Live updates when schedule or event data changes | Event & venue core, Schedule; optional push/WS later |
| **Multi-event support** | Multiple events in one instance; event picker or context; basic listing | Event & venue core, Identity |

**Build order suggestion:** Identity & profiles first, then Saved schedules + Ratings & notes in parallel, then Basic networking, Organizer dashboard, Real-time updates, Multi-event support.

---

### Stage 3 — Beyond MVP (full ecosystem)

Grouped by the vision doc’s “Beyond MVP” areas:

| Area | Modules (provisional) |
|------|------------------------|
| **Advanced community** | Direct messaging; group chats; interest-based meetups; long-term communities (e.g. per-event or cross-event groups) |
| **Commerce & logistics** | Ticketing integration (read-only or deep link); housing/partner links; transport info; vendor management (internal or partner) |
| **Intelligence layer** | Engagement insights; heatmaps; trend tracking; sponsor analytics; predictive planning (reports, dashboards) |
| **Multi-event identity** | One profile across events/years; history, badges, “event season” home | Extends Identity & profiles |

These can be broken into smaller modules when we get closer (e.g. “Ticketing bridge” vs “Housing guide” as separate modules).

---

## 4. Cross-cutting concerns

These are not single modules but should be designed once and shared. They also drive two other planning assets:

| Asset | Purpose |
|-------|--------|
| **[Architecture diagram](5-Architecture.md)** | High-level system: User App(s), our API, Database, server-side processing (e.g. Lambda). |
| **[Database schema](6-DatabaseSchema.md)** | Tables and schema as we build; single DB for now; future scaling decisions (e.g. separate Auth, large events, ticketing). |

### System architecture (summary)

- **User App** — iOS, Android, Web. Clients never talk directly to the database; all access goes through our API (and, where needed, server-side processing).
- **API** — Our own API providing secure, authenticated client access to all capabilities, including richer functions (e.g. ticketing, session booking). Clients call endpoints like `bookSession`, `getSchedule`, etc.; the API enforces auth and delegates to the right backend.
- **Database** — Single database for now; schema and tables documented as we build. Architectural decisions (e.g. separate DB instances for Auth, single large events, or ticketing) can be revisited as we scale.
- **Server-side processing** — Medium term we expect to use **Lambda** (or similar) for backend processing and data fetching. Example: a **Session Booking** feature — the client sends a user-authenticated request to our API (`bookSession`); the API triggers a Lambda that decrements available seats for the session, updates busy status, and performs any other side effects. The client never touches the DB directly.

So: **API** + **Auth & permissions** + **Data model** (see schema doc) + **Real-time** strategy are the main cross-cutting concerns; the architecture diagram and database schema doc capture how they hang together and how we'll evolve them.


---

## 5. Open-source strategy (provisional)

- **Stage 1** is a natural first open-source slice: “Event Builder 360 — Simple Directory” (event + schedule + session detail + basic contributions).
- **Stage 2** modules can be released incrementally (e.g. “Saved schedules” and “Ratings” as add-ons or part of a single “MVP” repo).
- **Stage 3** can be split by area (e.g. community vs commerce vs intelligence) for different repos or packages if that helps adoption and contribution.

---

## 6. Next steps

1. **Validate** this module list and boundaries (e.g. with SXSW workshop scope and Phase 1 deliverables).
2. **Lock** Stage 1 modules and build order for the prototype; leave Stage 2/3 as a roadmap.
3. **Document** each chosen module with: purpose, data it owns, API surface, and dependencies (could live in this folder or a `planning/modules/` subfolder).
4. **Refine** as we build — e.g. split “Basic contributions” or merge “Saved schedules” and “Ratings” if it simplifies implementation.

---

*This plan is provisional and should be updated as we learn from the prototype and workshop.*
