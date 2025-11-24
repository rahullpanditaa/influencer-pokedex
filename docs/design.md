# Design Document (MVP: 1M Creators)

## 1. System Overview

The **influencer-pokedex** is an influencer discovery platform that scales to ~1M creators across YouTube and Instagram in the MVP

At a high level, the system:

1. Ingests creator and content data from YouTube and Instagram at different cadences based on creator activity levels.
2. Normalizes different platform payloads (i.e. API responses) into a unified internal schema.
3. Generates embeddings and resolves platform accounts into canonical creators.
4. Runs LLM-based enrichment to assign each creator a primary niche, secondary niches, content style, and a short summary.
5. Stores structured metadata in a relational database and embeddings in a vector index.
6. Exposes a search API that combines keyword-based retrieval with semantic vector search and simple ranking to return relevant creators.

Operationally, the system is split into:

- **Offline / batch layer (Python):** ingestion, normalization, embeddings, LLM classification, identity resolution, indexing.
- **Online / serving layer (Go):** search API, hybrid retrieval, ranking, and per-request orchestration.

MVP focuses on YouTube + Instagram and 1M creators, but the design anticipates integrating TikTok and X, scaling upto 250M+ creators.

---

## 2. Ingestion Pipeline

<!-- ### 2.1 Goals & Assumptions

- Keep creator and content data fresh enough for discovery use cases.
- Respect platform rate limits and avoid bans.
- Support incremental scaling from thousands to millions of creators. -->

### 2.1 Update Cadence and Activity Buckets

Creators are bucketed by activity:

- **Active creators:**  
  - At least one YouTube video (long-form or YT shorts) in the past 7 days  
  - OR at least one Instagram post in the past 7 days  
  → **Refresh daily**

- **Semi-active creators:**  
  - Some content in the last 30 days but not meeting “active” criteria  
  → **Refresh every 72 hours**

- **Long-tail creators:**  
  - No recent activity, or low-priority for customers  
  → **Refresh weekly**

The **Scheduler** periodically recomputes these buckets based on recent content timestamps.

### 2.2 Scheduling, Job Dispatch, and Workers

The ingestion pipeline has three main components:

- **Scheduler**
  - Periodically selects creators due for refresh based on activity bucket.
  - Gives out ingestion jobs of the form `(creator_id, platform, priority)`.

- **Job Queue**
  - Stores ingestion jobs and smooths bursts of work.
  - Priority or separate queues can be used to ensure active creators are refreshed first.

- **Per-platform Ingestion Workers**
  - Pull jobs from the queue.
  - Call platform APIs (YouTube, Instagram) to fetch:
    - profile/channel info
    - recent content (last N videos/posts)
    - stats (followers/subscribers, views, likes, comments)
  - Push raw API responses into the normalization pipeline and raw store.

### 2.3 Rate Limiting, Retries, and Backfills

- **Rate-limit tracker**
  - Maintains per-platform and per-API-key counters and known reset windows.
  - Workers consult this tracker before making calls.
  - When close to limit, workers will (should 🙂) back off, or reduce concurrency.

- **Retry strategy**
  - Transient failures (network, 5xx code) → exponential backoff with a small max retry count.
  - Hard failures (4xx like auth issues) → job moved to a dead-letter queue (DLQ) with alerting.
  - Rate-limit failures → job added back to queue with a delay aligned to limit reset.

- **Backfills**
  - For new creators or large historical refreshes, the scheduler gives out lower-priority backfill jobs.
  - Backfills run with lower concurrency, can be throttled so they don’t interfere with ongoing freshness.

This design allows scaling ingestion by horizontally scaling workers and splitting queues per platform or activity tier as creator count grows.

---

## 3. Normalization & Raw Storage

### 3.1 Motivation

YouTube and Instagram APIs return different payloads: different field names, nesting, and semantics. Feeding raw platform data directly into LLMs, has several downsides:

- Prompts become complex.
- LLM outputs become inconsistent across platforms.
- Storage and indexing become harder to manage and evolve.
- Adding new platforms later becomes difficult.

Normalization solves this by converting all payloads into a unified internal schema.

### 3.2 Unified Schema: Core Entities

Normalization produces three main entity types:

- **CreatorAccount**
  - Represents an account on a specific platform (YouTube channel or Instagram profile).
  - Fields: `platform`, `platform_user_id`, `display_name`, `handle`, `bio`, `profile_image_url`, basic follower/subscriber stats, etc.

- **ContentItem**
  - Represents a unit of content (video/post).
  - Fields: `creator_account_id`, `content_type` (video/post/short), `title_or_caption`, `description`, `published_at`, and engagement stats (views, likes, comments).

<!-- - **MetricSnapshot** (optional for MVP, but anticipated)
  - Time-series metrics per creator account or content item (e.g., daily counters).
  - Enables trend and growth analysis without overloading main content tables. -->

### 3.3 Raw Storage

- Full, unmodified API responses are stored in a **raw data store** for:
  - Auditing issues,
  - Reprocessing with improved logic,
  - Debugging data anomalies.

- Normalized `CreatorAccount`, `ContentItem`, and `MetricSnapshot` records form the input to embedding generation, identity resolution, and enrichment.

---

## 4. Identity Resolution

Creators often have multiple accounts across platforms (e.g., YouTube + Instagram). The system needs to connect these into a single **canonical creator** to:

- Present a unified profile to users.
- Aggregate metrics across platforms.
- Avoid duplicate search results.

### 4.1 Canonical Creator Model

- **Creator** (canonical entity)
  - Internal `creator_id`.
  - Linked to one or more `CreatorAccount` records (YT, IG).
  - Later enriched with final niche, style, and summary.

### 4.2 MVP Identity Resolution Logic

Identity resolution runs after normalization and after an initial round of basic embeddings, and before final creator-level enrichment.

MVP rules:

- **Deterministic matching**
  - Exact or near-exact handle/username match.
  - Matching website or email in profiles.
  - Cross-linked bios (e.g., YouTube bio links to Instagram profile).

- **Light semantic similarity**
  - Compare bio embeddings across accounts (cosine similarity above a high min).
  - Optional?? basic image similarity between profile pictures (if available).

If/when match found:

- Accounts merged under a single `creator_id`.
- A confidence score can be recorded for future improvement or human review.

This step ensures that expensive LLM enrichment is performed **once per real creator**, not once per account.

---

## 5. AI Enrichment (Embeddings + LLM Classification)

AI enrichment has two conceptual phases:

1. **Per-account embeddings** to support identity resolution and later aggregation.
2. **Creator-level enrichment** (after identity resolution) to produce final embeddings and labels used in search.

### 5.1 Embeddings

For the MVP, the system generates 4 main embeddings per canonical creator:

- **YouTube bio embedding**
- **YouTube content embedding**
  - Derived from titles + descriptions of the last N videos (mix of long-form and Shorts).
- **Instagram bio embedding**
- **Instagram captions embedding**
  - Derived from last N post captions.

Workflow:

1. Compute text embeddings per `CreatorAccount` and `ContentItem` where relevant.
2. After identity resolution, aggregate per-account embeddings to produce per-creator embeddings:
   - e.g., averaging or weighted average by recency or engagement.
3. Store final per-creator embeddings in a vector index with fields indicating source (YT bio, YT content, IG bio, IG captions).

These embeddings power semantic similarity search and can also be used as features in later ML ranking models.

### 5.2 LLM Classification

Once a canonical creator exists and embeddings/content are available, the system runs LLM-based enrichment:

- Input: normalized bio + sampled content titles/captions for the creator across platforms.
- Output:
  - `primary_niche` (e.g., tech, fitness, beauty, finance, etc.)
  - `secondary_niches` (up to a few additional categories)
  - `content_style` (e.g., educational, lifestyle, entertainment, review)
  - `llm_summary` (short natural-language description: ~20 words)

This classification runs in batch, not per search request:

- Triggered when:
  - A creator is first ingested.
  - A creator’s content changes significantly (e.g., content drift detection or periodic re-enrichment).
- Uses a structured prompt to enforce consistent JSON-like output.
- Results are written into the Creator metadata store and used directly as filterable fields and ranking signals.

LLMs are **not** in the online search path for MVP; they are used only offline for enrichment.

---

## 6. Data Model & Storage Layer

### 6.1 Core Entities

- **Creator**
  - `creator_id` (PK)
  - name, canonical handle, profile image
  - `primary_niche`, `secondary_niches`, `content_style`, `llm_summary`
  - aggregate stats (e.g., total followers across platforms)

- **CreatorAccount**
  - `creator_account_id` (PK)
  - `creator_id` (FK)
  - `platform` (yt/ig)
  - platform-specific handle, platform_user_id
  - platform-level stats (followers/subscribers, etc.)

- **ContentItem**
  - `content_id` (PK)
  - `creator_account_id` (FK)
  - `content_type` (video/post/short)
  - `title_or_caption`, `description`, `published_at`
  - engagement stats (views, likes, comments)

- **EmbeddingRecord** (conceptual; may be a table or implicit in vector DB)
  - `creator_id`
  - `embedding_type` (yt_bio, yt_content, ig_bio, ig_captions)
  - `vector` (stored in vector index)
  - `updated_at`

- **MetricSnapshot** (optional for MVP)
  - time-series metrics (daily/weekly aggregates) for creator or content.

### 6.2 Partitioning and Scaling

For the MVP scale of 1M creators:

- A single relational database instance (e.g., Postgres/Aurora) is sufficient.
- Partitioning strategy is more important for content growth than for creators:
  - `ContentItem` and `MetricSnapshot` can be partitioned by date (e.g., monthly).
- Indexes on:
  - `creator_id` for joins.
  - `platform`, `platform_user_id`, and `creator_account_id` for lookups.
  - Filterable fields used in search: follower counts, primary_niche, platform, language/region (later).

As the system scales toward 250M+ creators:

- **Horizontal sharding** of the Creator and CreatorAccount tables by `creator_id` hash.
- **Time-based partitioning** for large content/metrics tables.
- Vector index scaling via:
  - sharding by embedding type and/or region,
  - or using a managed vector database.

Raw data (API responses and historical snapshots) can be stored in an object store to control storage costs.

---

## 7. Retrieval & Ranking Flow

### 7.1 Query Types

Search queries typically include:

- **Filters:**
  - platforms (YT, IG)
  - follower/subscriber band
  - primary/secondary niche
  - geography (if available)
  - content style

- **Free-text intent:**
  - e.g. “backend engineering creators under 500k followers”
  - e.g. “emerging fitness creators for a new gym launch”

### 7.2 Retrieval Pipeline

At query time:

1. **Parse filters and query text.**
2. **Keyword retrieval:**
   - Use creator metadata (niche, summary, bio text) and content titles for keyword or BM25-style search.
3. **Semantic retrieval:**
   - Embed the query text into a vector.
   - Query the vector index against all four embedding fields:
     - YT bio, YT content, IG bio, IG captions.
   - Retrieve top-K candidates per embedding type.

4. **Candidate union:**
   - Combine candidates from keyword and semantic retrieval into a unified candidate set.

### 7.3 Hybrid Scoring & Ranking

Each candidate creator receives:

- `keyword_score` (from textual relevance)
- `similarity_scores` for each embedding type:
  - `sim_yt_bio`, `sim_yt_content`, `sim_ig_bio`, `sim_ig_captions`
- `quality_signals`, e.g.:
  - follower band
  - engagement rate
  - activity status (active / semi-active / long-tail)

A simple scoring function in MVP:

- `semantic_score = w1 * sim_yt_bio + w2 * sim_yt_content + w3 * sim_ig_bio + w4 * sim_ig_captions`
- `final_score = α * keyword_score + β * semantic_score + γ * quality_score`

Weights `(w1–w4, α, β, γ)` are tunable configuration parameters and can be evolved based on feedback or offline evaluation. For MVP, they can be hand-tuned.

The ranked list is returned through the **Search API** alongside explanatory fields (e.g., why this creator was selected: niche match, semantic similarity, etc.).

LLMs are intentionally not used inline in this path for MVP to keep latency and cost under control. They can be introduced later to re-rank a small top-N candidate set if needed.

---

## 8. Monitoring, Observability & Cost Expectations

### 8.1 Monitoring & Metrics

Key metrics:

- **Ingestion freshness**
  - % of tracked creators updated within their target freshness window.
  - Per-platform API error rates and latency.

- **Enrichment coverage**
  - % of creators with up-to-date embeddings.
  - % of creators successfully enriched by LLM in the last N days.
  - LLM error/timeout rate.

- **Search health**
  - Search API QPS, latency (P50/P95/P99).
  - Error rates and timeout rates.
  - Vector index query latency and failure rate.

- **Pipeline health**
  - Queue depths for ingestion jobs.
  - Worker utilization.
  - DLQ volume for failing jobs.

These metrics feed into dashboards and alerting (e.g., if ingestion falls behind, if enrichment error rate spikes, or if search latency regresses).

### 8.2 Cost Drivers & Expectations

At 1M creators, major cost buckets:

- **Compute:**
  - Ingestion workers.
  - Batch enrichment jobs (embeddings + LLM).
  - Vector index and database compute.

- **Storage:**
  - Creator metadata (small relative to content).
  - Content and metrics tables.
  - Raw API responses (ideally in cheap storage).
  - Vector storage for embeddings.

- **AI:**
  - Text embedding model calls for creator bios and content snippets.
  - LLM classification calls per creator, on a periodic schedule (e.g., initial + occasional refresh).

First-order cost controls:

- Limit enrichment frequency for low-activity creators.
- Truncate historical content used for embeddings (e.g., last 10–20 items).
- Use cheaper embedding models and only promote to more expensive ones if necessary.
- Batch and cache LLM calls wherever possible.

As the system grows toward 50M and 250M creators, cost mitigation strategies include:

- Tiering creators (e.g., “premium” tracked more frequently).
- Moving raw data and old metrics to colder, cheaper storage.
- Optimizing LLM prompts and batching to reduce usage.

---

## 9. Security & Multi-Tenancy

### 9.1 Multi-Tenancy Model

MVP assumes a multi-tenant SaaS model where:

- **Global creator graph** (Creator, CreatorAccount, ContentItem, embeddings) is mostly shared.
- **Tenant-specific metadata** (e.g., notes, lists, hidden creators) is stored in separate tables keyed by `tenant_id`.

Access control:

- Requests are authenticated (e.g., API keys, OAuth).
- All queries are scoped by `tenant_id` for tenant-specific data.
- Shared creator data is read-only and common to all tenants.

If needed in future, high-revenue tenants can be moved to dedicated databases or isolated indexes.

### 9.2 Security Considerations

- All services run in a private network with restricted ingress.
- Data in transit is encrypted (HTTPS), and data at rest is encrypted in underlying stores.
- AI providers (embeddings/LLMs) are called through secure channels; prompts avoid sending unnecessary user-specific data.
- Secrets (API keys, database credentials) are managed by a secrets manager, not hard-coded.

Audit logs can track:

- Which tenant searched for what.
- Configuration changes (e.g., scoring weights, niche taxonomies).

---

## 10. Evolution to 250M+ Creators

While the MVP targets 1M creators and two platforms, the architecture is designed to scale:

- **More platforms:** new platform-specific ingestion workers and normalization adapters feeding the same unified schema.
- **More creators:** sharded metadata stores by `creator_id`, partitioned content, and scalable vector indexes.
- **More sophisticated ranking:** log per-query candidate sets and features to train ML ranking models later.
- **More real-time behavior:** partial support for near-real-time ingestion for high-value creators via higher-priority queues and shorter cadences.

Core separations (offline enrichment vs online search, creator vs account vs content, embeddings vs metadata) remain stable as scale and product surface grow.

