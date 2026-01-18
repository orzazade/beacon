-- Beacon Database Initialization
-- This script runs automatically when the pgvector container starts for the first time

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS vector;

-- Main table for unified task items with embeddings
CREATE TABLE IF NOT EXISTS beacon_items (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    item_type VARCHAR(20) NOT NULL CHECK (item_type IN ('task', 'email', 'calendar', 'teams', 'file')),
    source VARCHAR(50) NOT NULL,  -- 'azure_devops', 'outlook', 'gmail', 'teams', 'local'
    external_id VARCHAR(255),      -- ID from source system
    title TEXT NOT NULL,
    content TEXT,                  -- Full text content
    summary TEXT,                  -- AI-generated summary
    metadata JSONB DEFAULT '{}',   -- Flexible metadata storage
    embedding vector(768),         -- nomic-embed-text dimension
    priority VARCHAR(20),          -- AI-inferred priority
    status VARCHAR(50),            -- Current status
    due_date TIMESTAMPTZ,          -- Deadline if any
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    indexed_at TIMESTAMPTZ,        -- When embedding was generated

    UNIQUE(source, external_id)
);

-- HNSW index for fast similarity search (better for production)
CREATE INDEX IF NOT EXISTS idx_beacon_items_embedding_hnsw
ON beacon_items USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- Traditional indexes for filtering
CREATE INDEX IF NOT EXISTS idx_beacon_items_type ON beacon_items(item_type);
CREATE INDEX IF NOT EXISTS idx_beacon_items_source ON beacon_items(source);
CREATE INDEX IF NOT EXISTS idx_beacon_items_priority ON beacon_items(priority);
CREATE INDEX IF NOT EXISTS idx_beacon_items_created ON beacon_items(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_beacon_items_due_date ON beacon_items(due_date);
CREATE INDEX IF NOT EXISTS idx_beacon_items_metadata ON beacon_items USING GIN (metadata);

-- AI analysis results table
CREATE TABLE IF NOT EXISTS beacon_ai_analysis (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    item_id UUID REFERENCES beacon_items(id) ON DELETE CASCADE,
    analysis_type VARCHAR(50) NOT NULL,  -- 'priority', 'progress', 'briefing'
    model_used VARCHAR(100),             -- 'ollama:llama3.2:3b', 'openrouter:claude-sonnet-4'
    result JSONB NOT NULL,               -- Analysis result
    confidence FLOAT,                    -- Model confidence if available
    created_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(item_id, analysis_type)
);

CREATE INDEX IF NOT EXISTS idx_beacon_ai_analysis_item ON beacon_ai_analysis(item_id);
CREATE INDEX IF NOT EXISTS idx_beacon_ai_analysis_type ON beacon_ai_analysis(analysis_type);

-- Daily briefings table
CREATE TABLE IF NOT EXISTS beacon_briefings (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    briefing_date DATE NOT NULL UNIQUE,
    content TEXT NOT NULL,
    task_count INT,
    email_count INT,
    urgent_count INT,
    model_used VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_beacon_briefings_date ON beacon_briefings(briefing_date DESC);

-- Progress tracking table (AI-inferred progress)
CREATE TABLE IF NOT EXISTS beacon_progress (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    item_id UUID REFERENCES beacon_items(id) ON DELETE CASCADE,
    progress_percent INT CHECK (progress_percent >= 0 AND progress_percent <= 100),
    status_inference TEXT,           -- Why AI thinks this is the status
    evidence JSONB,                  -- Supporting evidence (email snippets, commits, etc.)
    inferred_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_beacon_progress_item ON beacon_progress(item_id);
CREATE INDEX IF NOT EXISTS idx_beacon_progress_date ON beacon_progress(inferred_at DESC);

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger for beacon_items
DROP TRIGGER IF EXISTS update_beacon_items_updated_at ON beacon_items;
CREATE TRIGGER update_beacon_items_updated_at
    BEFORE UPDATE ON beacon_items
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Helpful view: Items needing embedding
CREATE OR REPLACE VIEW beacon_items_pending_embedding AS
SELECT id, item_type, source, title, content
FROM beacon_items
WHERE embedding IS NULL
  AND content IS NOT NULL;

-- Helpful view: Recent items with AI analysis
CREATE OR REPLACE VIEW beacon_items_with_analysis AS
SELECT
    bi.*,
    ba.analysis_type,
    ba.result as ai_result,
    ba.confidence,
    ba.model_used
FROM beacon_items bi
LEFT JOIN beacon_ai_analysis ba ON bi.id = ba.item_id;

-- Grant permissions (if using specific user)
-- GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO beacon;
-- GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO beacon;

COMMENT ON TABLE beacon_items IS 'Unified storage for all work items (tasks, emails, etc.) with vector embeddings';
COMMENT ON TABLE beacon_ai_analysis IS 'AI analysis results for items (priority, progress inference)';
COMMENT ON TABLE beacon_briefings IS 'Daily AI-generated briefings';
COMMENT ON TABLE beacon_progress IS 'AI-inferred progress tracking over time';
