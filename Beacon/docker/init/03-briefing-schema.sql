-- Briefing Schema for Beacon
-- Phase 15: Daily AI Briefing

-- Briefings table
-- Stores AI-generated briefings with caching support
CREATE TABLE IF NOT EXISTS beacon_briefings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content JSONB NOT NULL,
    generated_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    data_hash VARCHAR(64),  -- Hash of input data for change detection
    tokens_used INT,
    model_used VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for finding valid cached briefings
CREATE INDEX IF NOT EXISTS idx_briefings_expires ON beacon_briefings(expires_at DESC);

-- Index for finding latest briefing
CREATE INDEX IF NOT EXISTS idx_briefings_generated ON beacon_briefings(generated_at DESC);

-- View: Priority items for briefing (P0-P2 items with their scores)
-- Used to aggregate high-priority items for the briefing prompt
CREATE OR REPLACE VIEW beacon_briefing_priority_items AS
SELECT
    bi.id,
    bi.title,
    bi.source,
    bi.item_type,
    bi.content,
    bi.metadata,
    bi.created_at,
    bi.updated_at,
    ps.level as priority_level,
    ps.confidence as priority_confidence,
    ps.reasoning as priority_reasoning
FROM beacon_items bi
INNER JOIN beacon_priority_scores ps ON bi.id = ps.item_id
WHERE ps.level IN ('P0', 'P1', 'P2')
  AND bi.item_type != 'commit'  -- Exclude commits from briefing
ORDER BY
    CASE ps.level
        WHEN 'P0' THEN 0
        WHEN 'P1' THEN 1
        WHEN 'P2' THEN 2
    END,
    ps.confidence DESC;

-- View: Items with upcoming deadlines (next 7 days)
-- Used to surface time-sensitive items in the briefing
CREATE OR REPLACE VIEW beacon_briefing_deadline_items AS
SELECT
    bi.id,
    bi.title,
    bi.source,
    bi.item_type,
    bi.metadata,
    bi.created_at,
    bi.updated_at,
    (bi.metadata->>'due_date')::timestamptz as due_date,
    EXTRACT(DAY FROM (bi.metadata->>'due_date')::timestamptz - NOW()) as days_remaining
FROM beacon_items bi
WHERE bi.metadata->>'due_date' IS NOT NULL
  AND (bi.metadata->>'due_date')::timestamptz > NOW()
  AND (bi.metadata->>'due_date')::timestamptz < NOW() + INTERVAL '7 days'
ORDER BY (bi.metadata->>'due_date')::timestamptz ASC;

-- View: Blocked items with progress scores
-- Used to highlight items needing attention
CREATE OR REPLACE VIEW beacon_briefing_blocked_items AS
SELECT
    bi.id,
    bi.title,
    bi.source,
    bi.item_type,
    bi.metadata,
    bi.created_at,
    bi.updated_at,
    prs.state as progress_state,
    prs.reasoning as blocked_reason,
    prs.last_activity_at
FROM beacon_items bi
INNER JOIN beacon_progress_scores prs ON bi.id = prs.item_id
WHERE prs.state = 'blocked'
ORDER BY prs.last_activity_at ASC NULLS FIRST;

-- View: Stale items with progress scores
-- Used to surface forgotten work items
CREATE OR REPLACE VIEW beacon_briefing_stale_items AS
SELECT
    bi.id,
    bi.title,
    bi.source,
    bi.item_type,
    bi.metadata,
    bi.created_at,
    bi.updated_at,
    prs.state as progress_state,
    prs.reasoning as stale_reason,
    prs.last_activity_at,
    EXTRACT(DAY FROM NOW() - COALESCE(prs.last_activity_at, bi.updated_at)) as days_since_activity
FROM beacon_items bi
INNER JOIN beacon_progress_scores prs ON bi.id = prs.item_id
WHERE prs.state = 'stale'
ORDER BY prs.last_activity_at ASC NULLS FIRST;

-- Function: Get items pending for briefing by priority levels
-- Filters for specific priority levels and excludes done/snoozed items
CREATE OR REPLACE FUNCTION get_briefing_priority_items(
    priority_levels TEXT[] DEFAULT ARRAY['P0', 'P1', 'P2'],
    max_limit INT DEFAULT 15
)
RETURNS TABLE (
    id UUID,
    title TEXT,
    source TEXT,
    item_type TEXT,
    metadata JSONB,
    priority_level TEXT,
    priority_confidence FLOAT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        bi.id,
        bi.title,
        bi.source,
        bi.item_type,
        bi.metadata,
        ps.level::TEXT as priority_level,
        ps.confidence as priority_confidence
    FROM beacon_items bi
    INNER JOIN beacon_priority_scores ps ON bi.id = ps.item_id
    LEFT JOIN beacon_progress_scores prs ON bi.id = prs.item_id
    LEFT JOIN snoozed_tasks st ON bi.external_id = st.task_id AND bi.source = st.task_source
    WHERE ps.level::TEXT = ANY(priority_levels)
      AND bi.item_type != 'commit'
      AND (prs.state IS NULL OR prs.state != 'done')
      AND (st.snooze_until IS NULL OR st.snooze_until < NOW())
    ORDER BY
        CASE ps.level::TEXT
            WHEN 'P0' THEN 0
            WHEN 'P1' THEN 1
            WHEN 'P2' THEN 2
            ELSE 3
        END,
        ps.confidence DESC
    LIMIT max_limit;
END;
$$ LANGUAGE plpgsql;

-- Function: Get new high-priority items since a given date
-- Used to highlight items added since last briefing
CREATE OR REPLACE FUNCTION get_new_high_priority_items(
    since_date TIMESTAMPTZ,
    priority_levels TEXT[] DEFAULT ARRAY['P0', 'P1'],
    max_limit INT DEFAULT 5
)
RETURNS TABLE (
    id UUID,
    title TEXT,
    source TEXT,
    item_type TEXT,
    metadata JSONB,
    priority_level TEXT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        bi.id,
        bi.title,
        bi.source,
        bi.item_type,
        bi.metadata,
        ps.level::TEXT as priority_level,
        bi.created_at
    FROM beacon_items bi
    INNER JOIN beacon_priority_scores ps ON bi.id = ps.item_id
    WHERE ps.level::TEXT = ANY(priority_levels)
      AND bi.created_at > since_date
      AND bi.item_type != 'commit'
    ORDER BY bi.created_at DESC
    LIMIT max_limit;
END;
$$ LANGUAGE plpgsql;

-- Function: Get latest valid (non-expired) briefing
CREATE OR REPLACE FUNCTION get_latest_valid_briefing()
RETURNS SETOF beacon_briefings AS $$
BEGIN
    RETURN QUERY
    SELECT *
    FROM beacon_briefings
    WHERE expires_at > NOW()
    ORDER BY generated_at DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Cleanup: Delete old expired briefings (keep last 7 days for history)
CREATE OR REPLACE FUNCTION cleanup_old_briefings()
RETURNS void AS $$
BEGIN
    DELETE FROM beacon_briefings
    WHERE expires_at < NOW() - INTERVAL '7 days';
END;
$$ LANGUAGE plpgsql;
