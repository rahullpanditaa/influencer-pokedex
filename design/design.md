# Influencer Pokedex — Design Document

## 1. System Overview

This system is designed to help users discover influencers across multiple platforms by unifying creator data, enriching it with AI, and supporting fast, high-quality search. The initial goal is to support around one million creators across YouTube and Instagram, with a roadmap that scales to hundreds of millions.

At its core, the system collects creator data from platform APIs, normalizes it into a consistent structure, enriches it using embeddings and LLMs, and stores everything in a combination of relational and vector databases. A hybrid search layer (keyword + semantic -> RRF) enables users to find creators based on interests, niches, and content themes.

The design aims for simplicity in the early stages while leaving room for growth and more sophisticated features as the product matures.

---

## 2. Data Model and Partitioning

The system relies on a small, well-defined set of entities:

* **Creator** — a single real person or brand, regardless of how many platforms they exist on. This is the central identity in the system.
* **CreatorAccount** — a platform-specific account (a YouTube channel or Instagram profile). A creator can have several of these.
* **ContentItem** — a post or video belonging to a creator’s account.

This structure prevents duplication and makes it easy to extend the system when new platforms are added. For now, partitioning is kept simple; content items may later be partitioned by date, and creator accounts by platform or hashed ID as the volume grows. Embeddings live in a vector database.

---

## 3. Ingestion Cadence, Scaling, Retries, and Backfills

Creators are updated on different schedules depending on their activity:

* **Active creators** — updated daily.
* **Semi-active creators** — updated every 72 hours.
* **Inactive creators** — updated weekly.

A scheduler determines when each creator should be refreshed and pushes jobs into a queue. Platform-specific workers pull jobs, fetch API data, and handle platform rate limits. Automatic retries and backoff logic ensure resilience against temporary API failures.

As the system grows, more workers can be added horizontally. Backfills run when schemas change or new enrichment steps are introduced.

---

## 4. Identity Resolution Across Platforms

Many creators exist on multiple platforms, and the system needs to unify them into a single Creator entity.

The MVP uses a combination of:

* Simple heuristics (name similarity, linked usernames, overlapping handles)
* Embedding similarity between bios and captions

If two accounts score highly enough, they are merged under a single creator. Over time, this can evolve into a more sophisticated identity resolution pipeline that combines graph signals, richer metadata, and scoring models.

---

## 5. Retrieval and Ranking Flow

The search layer brings together different signals to deliver high-quality results.

* A **BM25 keyword index** helps match exact words in bios, captions, and descriptions.
* A **vector search index** helps capture semantic meaning and related concepts.
* A **hybrid ranking step** (using Reciprocal Rank Fusion) blends the strengths of both.

A query is embedded using the same model used during enrichment. BM25 returns a ranked list of creators from keyword matches in their bio, vector search returns semantically similar creators, and hybrid fusion produces the final ranking. This helps avoid cases where purely keyword-based or purely semantic search would fail.

---

## 6. AI Usage: Embeddings, Metadata Extraction, and LLM Scoring

AI is used to add structure and meaning to otherwise sparse creator metadata.

* **Embeddings** are generated for:

  * YouTube bios
  * Titles and descriptions of recent videos
  * Instagram bios
  * Captions of recent posts

  These embeddings allow for semantic search and also help with identity resolution.

* **LLM Classification** produces:

  * Primary niche
  * Secondary niches
  * Content style
  * A concise summary

This standardized metadata helps improve search precision and makes the system more usable by non-technical users.

---

## 7. Monitoring, Observability, and Cost Expectations

Monitoring focuses on:

* The freshness of creator data
* How often ingestion jobs fail or retry
* Search latency and API performance
* Storage growth across Postgres, S3, and the vector database

Costs primarily come from enrichment jobs (LLM usage), storage of raw and processed data, and compute for ingestion workers. Costs can be controlled by adjusting update frequency, batching enrichment, and choosing smaller models for long-tail creators.

---

## 8. Security and Multi-Tenancy

For the MVP, the system keeps security simple: a single tenant model with basic API authentication and rate limits.

As customers grow:

* Tenant filtering may be enforced at the database level
* Row-level security can protect cross-tenant visibility
* Vector databases may maintain separate namespaces per tenant
* Access logs and audit trails become more important

These changes allow the system to support multiple organizations safely.

---

## 9. Trade-offs and Scaling Roadmap

### What I would ship now (Pre-PMF)

* Support only YouTube and Instagram, focusing on core use cases.
* Use a simple ingestion pipeline with a scheduler and workers.
* Use embeddings, BM25, and basic LLM enrichment for ranking and metadata.

This keeps the system small, inexpensive, and fast to iterate on.

### What I would build after PMF

* Add TikTok and X as new data sources.
* Introduce more advanced ranking models based on user interactions.
* Move from simple workers toward orchestration tools like Airflow or Dagster.

This only becomes worth it once usage and customer demand justify the complexity.

### Evolution over the next 12–14 months

* Replace cron-style workers with Airflow or Dagster for scalable scheduling.
* Migrate from local or single-node vector DBs to fully managed, scalable vector databases.
* Improve identity resolution and strengthen multi-tenant architecture.

These steps prepare the system for growth as it scales from one million creators to tens of millions and eventually to hundreds of millions.

---
