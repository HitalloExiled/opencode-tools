-- Migration 005: add `pinned` column to notes table.
-- A pinned note is one the agent has explicitly kept in session context.
-- Non-pinned notes remain searchable but are NOT injected.

ALTER TABLE notes ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_notes_pinned ON notes(pinned, timestamp DESC);
