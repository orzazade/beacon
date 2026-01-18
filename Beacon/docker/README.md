# Beacon AI Infrastructure

Documentation and setup for Beacon's AI backend services.

## Quick Start (Using dev-stacks)

Beacon uses the shared dev-stacks infrastructure at `~/Projects/dev-stacks`.

```bash
# 1. Start dev-stacks services
cd ~/Projects/dev-stacks
docker compose --profile db --profile ai up -d

# 2. Create Beacon database (first time only)
psql -h localhost -p 5432 -U admin -d postgres -c "CREATE DATABASE beacon;"
psql -h localhost -p 5432 -U admin -d beacon -f ~/Projects/scifi/beacon/Beacon/docker/init/01-init-beacon.sql

# 3. Pull Ollama models (if not already done)
curl http://localhost:11434/api/pull -d '{"name": "nomic-embed-text"}'
curl http://localhost:11434/api/pull -d '{"name": "llama3.2:3b"}'
```

## Service Endpoints

| Service | Host | Port | Credentials |
|---------|------|------|-------------|
| pgvector | localhost | 5432 | admin / secret |
| ollama | localhost | 11434 | - |

## Database Schema

The init script (`init/01-init-beacon.sql`) creates:

### Tables

| Table | Purpose |
|-------|---------|
| `beacon_items` | Unified task/email storage with 768-dim vector embeddings |
| `beacon_ai_analysis` | AI analysis results (priority, progress inference) |
| `beacon_briefings` | Daily AI-generated briefings |
| `beacon_progress` | Progress tracking history |

### Key Features

- **HNSW Index**: Fast approximate nearest neighbor search on embeddings
- **JSONB Metadata**: Flexible storage for source-specific data
- **Auto-updated timestamps**: Triggers maintain `updated_at` fields

## Verify Setup

```bash
# Check pgvector
psql -h localhost -p 5432 -U admin -d beacon -c "SELECT COUNT(*) FROM beacon_items;"

# Check Ollama
curl http://localhost:11434/api/tags

# Test embedding
curl http://localhost:11434/api/embed -d '{
  "model": "nomic-embed-text",
  "input": ["test embedding"]
}'
```

## Standalone Docker (Alternative)

The `docker-compose.yml` in this folder is provided for documentation and can be used if you need a standalone setup:

```bash
cd docker
docker compose --profile all up -d
docker compose --profile init up  # Pull models
```

This runs on different ports (5433, 11435) to avoid conflicts with dev-stacks.

## OpenRouter Setup

1. Sign up at https://openrouter.ai
2. Create API key and add credits
3. Configure in Beacon Settings UI (stored in macOS Keychain)
