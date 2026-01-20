-- Chat Schema for Beacon
-- Phase 16: AI Chat Interface

-- Chat Threads
-- Stores conversation threads for the AI chat interface
CREATE TABLE IF NOT EXISTS chat_threads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    last_message_at TIMESTAMPTZ,
    message_count INTEGER DEFAULT 0
);

-- Index for listing threads sorted by most recent activity
CREATE INDEX IF NOT EXISTS idx_chat_threads_updated ON chat_threads(updated_at DESC);

-- Index for finding threads with recent messages
CREATE INDEX IF NOT EXISTS idx_chat_threads_last_message ON chat_threads(last_message_at DESC);

-- Chat Messages
-- Stores individual messages within a chat thread
CREATE TABLE IF NOT EXISTS chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    thread_id UUID REFERENCES chat_threads(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
    content TEXT NOT NULL,
    citations JSONB DEFAULT '[]',
    suggested_actions JSONB DEFAULT '[]',
    tokens_used INTEGER,
    model_used TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for efficient thread message queries (sorted by time)
CREATE INDEX IF NOT EXISTS idx_chat_messages_thread ON chat_messages(thread_id, created_at DESC);

-- Index for finding messages by role (useful for system message management)
CREATE INDEX IF NOT EXISTS idx_chat_messages_role ON chat_messages(role);

-- Trigger to update chat_threads.updated_at when messages are added
CREATE OR REPLACE FUNCTION update_chat_thread_on_message()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE chat_threads
    SET updated_at = NOW(),
        last_message_at = NEW.created_at,
        message_count = message_count + 1
    WHERE id = NEW.thread_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_thread_on_message ON chat_messages;
CREATE TRIGGER trigger_update_thread_on_message
    AFTER INSERT ON chat_messages
    FOR EACH ROW
    EXECUTE FUNCTION update_chat_thread_on_message();

-- Trigger to decrement message_count when messages are deleted
CREATE OR REPLACE FUNCTION update_chat_thread_on_message_delete()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE chat_threads
    SET updated_at = NOW(),
        message_count = GREATEST(0, message_count - 1),
        last_message_at = (
            SELECT MAX(created_at) FROM chat_messages WHERE thread_id = OLD.thread_id
        )
    WHERE id = OLD.thread_id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_thread_on_message_delete ON chat_messages;
CREATE TRIGGER trigger_update_thread_on_message_delete
    AFTER DELETE ON chat_messages
    FOR EACH ROW
    EXECUTE FUNCTION update_chat_thread_on_message_delete();

-- Function: Get recent threads with pagination
CREATE OR REPLACE FUNCTION get_recent_chat_threads(
    max_limit INT DEFAULT 20,
    offset_val INT DEFAULT 0
)
RETURNS TABLE (
    id UUID,
    title TEXT,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    last_message_at TIMESTAMPTZ,
    message_count INT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        ct.id,
        ct.title,
        ct.created_at,
        ct.updated_at,
        ct.last_message_at,
        ct.message_count
    FROM chat_threads ct
    ORDER BY ct.updated_at DESC
    LIMIT max_limit
    OFFSET offset_val;
END;
$$ LANGUAGE plpgsql;

-- Function: Get messages for a thread with pagination (oldest first for chat display)
CREATE OR REPLACE FUNCTION get_chat_messages(
    p_thread_id UUID,
    max_limit INT DEFAULT 50,
    offset_val INT DEFAULT 0
)
RETURNS TABLE (
    id UUID,
    thread_id UUID,
    role TEXT,
    content TEXT,
    citations JSONB,
    suggested_actions JSONB,
    tokens_used INT,
    model_used TEXT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        cm.id,
        cm.thread_id,
        cm.role,
        cm.content,
        cm.citations,
        cm.suggested_actions,
        cm.tokens_used,
        cm.model_used,
        cm.created_at
    FROM chat_messages cm
    WHERE cm.thread_id = p_thread_id
    ORDER BY cm.created_at ASC
    LIMIT max_limit
    OFFSET offset_val;
END;
$$ LANGUAGE plpgsql;

-- Cleanup: Delete old chat threads (keep last 30 days)
CREATE OR REPLACE FUNCTION cleanup_old_chat_threads()
RETURNS void AS $$
BEGIN
    DELETE FROM chat_threads
    WHERE updated_at < NOW() - INTERVAL '30 days';
END;
$$ LANGUAGE plpgsql;

COMMENT ON TABLE chat_threads IS 'Conversation threads for the AI chat interface';
COMMENT ON TABLE chat_messages IS 'Individual messages within chat threads, with citations and suggested actions';
