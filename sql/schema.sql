

CREATE TABLE IF NOT EXISTS activities (
    activity_id                TEXT PRIMARY KEY,               -- e.g. 'A1'
    age_in_months              SMALLINT NOT NULL CHECK (age_in_months >= 0),  -- milestone from the CSV

    -- Developmental age band derived at ingest time: an activity tagged with
    -- milestone 12 (next milestone 15) applies to children aged 12..14 months.
    age_min_months             SMALLINT NOT NULL,
    age_max_months             SMALLINT NOT NULL,

    activity_description       TEXT NOT NULL,
    location                   TEXT,                           -- Any / Indoor / Outdoor
    category                   TEXT NOT NULL,
    requires_device            BOOLEAN NOT NULL DEFAULT FALSE,
    materials_needed           TEXT,                           -- nullable (~2/3 of rows are empty)
    interest                   TEXT NOT NULL,
    target_developmental_area  TEXT NOT NULL,

    embedding_text             TEXT NOT NULL,                  -- exact string that was embedded (debugging / re-embedding)
    embedding                  REAL[] NOT NULL,                -- all-MiniLM-L6-v2 -> 384 dims, L2-normalised

    CONSTRAINT age_band_valid CHECK (age_min_months <= age_max_months)
);

-- Hard pre-filter on the age band.
CREATE INDEX IF NOT EXISTS idx_activities_age_band
    ON activities (age_min_months, age_max_months);

