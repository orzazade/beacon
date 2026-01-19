-- Priority Analysis Schema for Beacon
-- Phase 13: AI Priority Analysis

-- Enum type for priority levels (matches Swift AIPriorityLevel)
DO $$ BEGIN
    CREATE TYPE priority_level AS ENUM ('P0', 'P1', 'P2', 'P3', 'P4');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Priority scores table
-- Stores AI analysis results for each BeaconItem
CREATE TABLE IF NOT EXISTS beacon_priority_scores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_id UUID NOT NULL REFERENCES beacon_items(id) ON DELETE CASCADE,
    level priority_level NOT NULL,
    confidence FLOAT CHECK (confidence >= 0 AND confidence <= 1),
    reasoning TEXT,
    signals JSONB DEFAULT '[]'::jsonb,
    is_manual_override BOOLEAN DEFAULT FALSE,
    analyzed_at TIMESTAMPTZ DEFAULT NOW(),
    model_used VARCHAR(100),
    token_cost INT,
    UNIQUE(item_id)
);

-- Indexes for priority scores
CREATE INDEX IF NOT EXISTS idx_priority_scores_item ON beacon_priority_scores(item_id);
CREATE INDEX IF NOT EXISTS idx_priority_scores_level ON beacon_priority_scores(level);
CREATE INDEX IF NOT EXISTS idx_priority_scores_analyzed ON beacon_priority_scores(analyzed_at DESC);

-- VIP contacts table
-- Stores user-configured important senders
CREATE TABLE IF NOT EXISTS beacon_vip_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL UNIQUE,
    name VARCHAR(255),
    added_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for VIP email lookups (case-insensitive)
CREATE INDEX IF NOT EXISTS idx_vip_email ON beacon_vip_contacts(LOWER(email));

-- Cost tracking table
-- Logs each priority analysis run for spending limits
CREATE TABLE IF NOT EXISTS beacon_priority_cost_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_date DATE NOT NULL,
    items_processed INT NOT NULL,
    tokens_used INT NOT NULL,
    model_used VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for daily cost aggregation
CREATE INDEX IF NOT EXISTS idx_cost_log_date ON beacon_priority_cost_log(run_date);

-- Add analyzed_at column to beacon_items if not exists
-- This tracks when an item was last analyzed to avoid re-processing unchanged items
DO $$ BEGIN
    ALTER TABLE beacon_items ADD COLUMN priority_analyzed_at TIMESTAMPTZ;
EXCEPTION
    WHEN duplicate_column THEN null;
END $$;

-- Index for finding items needing analysis
CREATE INDEX IF NOT EXISTS idx_items_priority_pending
    ON beacon_items(updated_at, priority_analyzed_at)
    WHERE priority_analyzed_at IS NULL OR updated_at > priority_analyzed_at;

-- View: Items with their priority scores
CREATE OR REPLACE VIEW beacon_items_with_priority AS
SELECT
    i.*,
    p.level as priority_level,
    p.confidence as priority_confidence,
    p.reasoning as priority_reasoning,
    p.signals as priority_signals,
    p.is_manual_override as priority_is_manual,
    p.analyzed_at as priority_analyzed_at,
    p.model_used as priority_model
FROM beacon_items i
LEFT JOIN beacon_priority_scores p ON i.id = p.item_id;

-- View: Daily cost summary
CREATE OR REPLACE VIEW beacon_priority_daily_costs AS
SELECT
    run_date,
    SUM(items_processed) as total_items,
    SUM(tokens_used) as total_tokens,
    COUNT(*) as batch_count
FROM beacon_priority_cost_log
GROUP BY run_date
ORDER BY run_date DESC;

-- Function: Get items pending priority analysis
-- Returns items that have never been analyzed OR have been updated since last analysis
CREATE OR REPLACE FUNCTION get_items_pending_priority(batch_limit INT DEFAULT 10)
RETURNS SETOF beacon_items AS $$
BEGIN
    RETURN QUERY
    SELECT *
    FROM beacon_items
    WHERE priority_analyzed_at IS NULL
       OR updated_at > priority_analyzed_at
    ORDER BY
        CASE WHEN priority_analyzed_at IS NULL THEN 0 ELSE 1 END,  -- New items first
        updated_at DESC
    LIMIT batch_limit;
END;
$$ LANGUAGE plpgsql;
