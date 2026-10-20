-- Run this after schema.sql. Adds caregiver accounts and child profiles on
-- top of the existing `activities` table.

CREATE TABLE IF NOT EXISTS caregivers (
    caregiver_id    BIGSERIAL PRIMARY KEY,
    name            TEXT NOT NULL,
    email           TEXT UNIQUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS children (
    child_id        BIGSERIAL PRIMARY KEY,
    caregiver_id    BIGINT NOT NULL REFERENCES caregivers(caregiver_id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    birth_date      DATE NOT NULL CHECK (birth_date <= CURRENT_DATE),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_children_caregiver ON children (caregiver_id);

-- A child's default interests (the same 5-value list used by `activities.interest`).
-- Kept separate from `children` so a child can have 0, 1 or several, and so the
-- recommend endpoint can still accept a one-off interest list that overrides these.
CREATE TABLE IF NOT EXISTS child_interests (
    child_id        BIGINT NOT NULL REFERENCES children(child_id) ON DELETE CASCADE,
    interest        TEXT NOT NULL,
    PRIMARY KEY (child_id, interest)
);

-- Convenience view: current age in months, computed on read so it never goes stale.
CREATE OR REPLACE VIEW children_with_age AS
SELECT
    c.child_id,
    c.caregiver_id,
    c.name,
    c.birth_date,
    (DATE_PART('year', age(CURRENT_DATE, c.birth_date)) * 12
     + DATE_PART('month', age(CURRENT_DATE, c.birth_date)))::INT AS age_in_months
FROM children c;