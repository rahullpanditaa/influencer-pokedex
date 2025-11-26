# influencer-pokedex

This repository contains the complete submission for a scalable, AI-powered influencer discovery system. The goal of the system is to aggregate creator data across multiple platforms, enrich it using LLMs and embeddings, and enable fast hybrid search for discovering relevant creators.

The project is built with an emphasis on clear system architecture, practical use of AI, and a realistic path to scaling from 1M creators to 250M+ creators across platforms.

---

## Repository Structure

```
influencer-pokedex/
│
├── design/
│   ├── design.md
│   └── architecture-diagram.png
│
├── artifacts/
│   ├── notebook/
│   │   ├── rankings.ipynb
│   │   └── .gitignore
│   │
│   ├── api_specs/
│   │   └── openapi.yaml
│   │
│   └── schema/
│       ├── 001_creators.sql
|       ├── 002_creator_accounts.sql
│       └── 003_content.sql
|       
└── README.md
```

---

## Overview

This system ingests creator data from YouTube and Instagram. The data is normalized, enriched using LLMs and embeddings, stored in structured and vector databases, and exposed via a hybrid search API. A notebook artifact illustrates BM25, semantic search, and RRF-based hybrid ranking.

The design focuses on:

* **AI-first enrichment** (embeddings + LLM classification)
* **Clear ingestion and normalization pipelines**
* **Hybrid search** combining keyword and semantic relevance
* **A scalable architecture roadmap** from MVP to 250M+ creators

---

## How to Run the Notebook

If you'd like to explore the hybrid search prototype:

```
cd artifacts/notebook
source .venv/bin/activate
uv sync
code . (I used VSCode)
open `rankings.ipynb` and select the `.venv` Python kernel
```

Open `rankings.ipynb` and run the cells.

---

## Included Components

### ✔ Architecture Diagram

A high-level diagram showing ingestion, normalization, AI enrichment, storage, and search layers.

### ✔ Design Write-up

A detailed explanation of the data model, ingestion strategy, identity resolution, enrichment, ranking pipeline, observability, and scaling roadmap.

### ✔ Technical Artifacts

* Notebook prototype for hybrid search (BM25 + embeddings)
* OpenAPI specification for the Search API
* PostgreSQL schema for core entities

### ✔ Trade-offs & Scaling Roadmap

A breakdown of what ships in the MVP and how the system evolves over the next 12–14 months.

---
