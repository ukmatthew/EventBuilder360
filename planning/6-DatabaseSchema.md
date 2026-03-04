# Event Builder 360 — Database schema and tables

**Status:** Living document — we document tables and schema as we build.  
**References:** [4-ModularBuildPlan.md](4-ModularBuildPlan.md) (Cross-cutting concerns), [5-Architecture.md](5-Architecture.md)

This document is the single place to record **database tables and schema** as we add functionality. We will make **architectural decisions over time** (e.g. separate DB instances for Auth, single large events, ticketing); for now we target a **single database**.

---

## Current stance

| Decision | Choice | Notes |
|----------|--------|--------|
| **Number of DB instances** | **Single database** | One instance for all data (events, venues, sessions, users, auth-related tables, future ticketing/booking, etc.). Simplifies prototype and MVP. |
| **Future scaling** | Revisit as we grow | If we scale heavily, we may introduce separate instances for e.g. **Auth**, **single large events**, or **ticketing**. Those choices will be recorded here when we make them. |
| **Schema ownership** | Document as we build | Tables and columns are added below as we implement each module (e.g. Event & venue core, Schedule, Identity, Session booking). |

---

## Tables and schema (as we build)

*Tables will be listed here as we add them. For each table we’ll record: name, purpose, main columns, and key relationships.*

### events

| Column | Type (inferred) | Purpose |
|--------|------------------|--------|
| `id` | text / uuid | Primary key. |
| `created_at` | timestamptz | When the row was created. |
| `name` | text | Event display name. |

**Purpose:** Core event entity (Event & venue core module). One row per event.

**Current state:** One row in DB — `SXSW 2026` (id `1`). Seed data: [sql/events_rows.sql](../sql/events_rows.sql).

---

## Architectural decisions log

Decisions that affect the database or schema will be noted here so we don’t lose context.

| Date | Decision | Rationale |
|------|----------|-----------|
| *(draft)* | Single database for all functionality | Keep prototype and MVP simple; revisit splitting (Auth, large events, ticketing) when scale or compliance demands it. |

---

*Update this document whenever we add or change tables, or when we decide to split or introduce new DB instances.*
