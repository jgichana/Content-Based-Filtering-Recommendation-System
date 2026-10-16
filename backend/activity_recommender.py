"""
Content-based activity recommender: sentence-transformers + PostgreSQL.

Embeddings are stored as a plain REAL[] column and similarity is computed in
Python with numpy, on just the rows that survive the age pre-filter (a few
dozen out of ~300). No PostgreSQL extension is required. See the note in
schema.sql for when this should be swapped for pgvector.


Usage:
    python activity_recommender.py ingest Child-Activity-Data-Filled.csv
    python activity_recommender.py recommend --age 14 --interests Music Reading
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path

import numpy as np
import pandas as pd
import psycopg

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://postgres:postgresql@localhost:5432/postgres")
MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"
_HERE = Path(__file__).resolve().parent
# Works both with a flat folder (schema.sql beside this script) and the
# restructured layout (backend/activity_recommender.py + sql/schema.sql).
SCHEMA_PATH = next(
    (p for p in (_HERE / "schema.sql", _HERE.parent / "sql" / "schema.sql") if p.exists()),
    _HERE.parent / "sql" / "schema.sql",
)
LAST_BAND_WIDTH = 12  # the final milestone (60) has no "next" one; give it a 12-month band (60..71)

_model = None


def get_model():
    """Load the embedding model once per process."""
    global _model
    if _model is None:
        from sentence_transformers import SentenceTransformer
        _model = SentenceTransformer(MODEL_NAME)
    return _model


# --------------------------------------------------------------------------- #
# Shared text template - documents and queries MUST use the same format so    #
# that they land in the same region of embedding space.                       #
# --------------------------------------------------------------------------- #
def build_document_text(interest: str, area: str, description: str) -> str:
    return f"Interest: {interest}. Developmental area: {area}. Activity: {description}"


def build_query_text(interest_tags: list[str]) -> str:
    return f"Interest: {', '.join(interest_tags)}."


def embed(texts: list[str]) -> np.ndarray:
    # normalize_embeddings=True -> unit vectors, so cosine distance == a monotone function of dot product
    return get_model().encode(texts, batch_size=64, normalize_embeddings=True, show_progress_bar=len(texts) > 64)


# --------------------------------------------------------------------------- #
# 1) Ingestion                                                                #
# --------------------------------------------------------------------------- #
def prepare_dataframe(csv_path: str) -> pd.DataFrame:
    df = pd.read_csv(csv_path)
    df.columns = [c.strip() for c in df.columns]
    df = df.rename(columns={"Activity description": "description"})

    for col in ("ActivityID", "description", "category", "interest", "target_developmental_area"):
        df[col] = df[col].astype(str).str.strip()
    df["requires_bool"] = df["requires device"].astype(str).str.strip().str.lower().eq("yes")

    # Age band: milestone m applies from m up to (next milestone - 1).
    milestones = sorted(int(m) for m in df["Age_in_months"].unique())
    next_milestone = dict(zip(milestones, milestones[1:]))
    df["age_min"] = df["Age_in_months"].astype(int)
    df["age_max"] = df["age_min"].map(lambda m: next_milestone.get(m, m + LAST_BAND_WIDTH) - 1)

    df["embedding_text"] = [
        build_document_text(i, a, d)
        for i, a, d in zip(df["interest"], df["target_developmental_area"], df["description"])
    ]
    return df


UPSERT_SQL = """
INSERT INTO activities (
    activity_id, age_in_months, age_min_months, age_max_months, activity_description,
    location, category, requires_device, materials_needed, interest,
    target_developmental_area, embedding_text, embedding
) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
ON CONFLICT (activity_id) DO UPDATE SET
    age_in_months = EXCLUDED.age_in_months,
    age_min_months = EXCLUDED.age_min_months,
    age_max_months = EXCLUDED.age_max_months,
    activity_description = EXCLUDED.activity_description,
    location = EXCLUDED.location,
    category = EXCLUDED.category,
    requires_device = EXCLUDED.requires_device,
    materials_needed = EXCLUDED.materials_needed,
    interest = EXCLUDED.interest,
    target_developmental_area = EXCLUDED.target_developmental_area,
    embedding_text = EXCLUDED.embedding_text,
    embedding = EXCLUDED.embedding;
"""


def ingest(csv_path: str) -> int:
    df = prepare_dataframe(csv_path)
    embeddings = embed(df["embedding_text"].tolist())

    with psycopg.connect(DATABASE_URL, autocommit=True) as conn:
        conn.execute(SCHEMA_PATH.read_text())

    rows = [
        (
            r.ActivityID, int(r.Age_in_months), int(r.age_min), int(r.age_max), r.description,
            r.location, r.category, bool(r.requires_bool),
            None if pd.isna(r.materials_needed) else str(r.materials_needed).strip(), r.interest,
            r.target_developmental_area, r.embedding_text, emb.tolist(),  # REAL[] wants a plain Python list
        )
        for r, emb in zip(df.itertuples(index=False), embeddings)
    ]

    with psycopg.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            cur.executemany(UPSERT_SQL, rows)
        conn.execute("ANALYZE activities;")
    return len(rows)


# --------------------------------------------------------------------------- #
# 3) Recommendation                                                           #
# --------------------------------------------------------------------------- #
CANDIDATES_SQL = """
SELECT activity_id,
       age_in_months,
       activity_description,
       category,
       interest,
       target_developmental_area,
       materials_needed,
       embedding
FROM activities
WHERE age_min_months - %(tol)s <= %(age)s      -- hard developmental pre-filter
  AND age_max_months + %(tol)s >= %(age)s;
"""


def recommend_activities(
    child_age_months: int,
    interest_tags: list[str],
    top_k: int = 5,
    age_tolerance_months: int = 2,
    conn: psycopg.Connection | None = None,
) -> list[dict]:
    """
    Top-k activities for a child.

    1. Hard filter (in SQL): only activities whose age band contains the
       child's age (widened by `age_tolerance_months` on both sides, 0 = strict).
    2. Rank the survivors (in Python, with numpy) by cosine similarity between
       the embedded interest tags and each activity's embedding. Embeddings
       are unit-normalised at ingest time, so cosine similarity is just a dot
       product.
    """
    if child_age_months < 0:
        raise ValueError("child_age_months must be >= 0")
    tags = [t.strip() for t in interest_tags if t and t.strip()]
    if not tags:
        raise ValueError("interest_tags must contain at least one non-empty tag")

    query_vec = embed([build_query_text(tags)])[0]  # shape (384,), unit norm
    params = {"age": child_age_months, "tol": age_tolerance_months}

    def run(c: psycopg.Connection) -> list[dict]:
        with c.cursor(row_factory=psycopg.rows.dict_row) as cur:
            cur.execute(CANDIDATES_SQL, params)
            candidates = cur.fetchall()
        if not candidates:
            return []
        matrix = np.array([row["embedding"] for row in candidates])  # (n, 384)
        similarities = matrix @ query_vec  # cosine similarity (both sides unit-norm)
        for row, sim in zip(candidates, similarities):
            row["similarity"] = float(sim)
            del row["embedding"]
        candidates.sort(key=lambda r: r["similarity"], reverse=True)
        return candidates[:top_k]

    if conn is not None:  # reuse a pooled / long-lived connection
        return run(conn)
    with psycopg.connect(DATABASE_URL) as c:
        return run(c)


# --------------------------------------------------------------------------- #
def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    a = sub.add_parser("ingest", help="embed the CSV and upsert it into PostgreSQL")
    a.add_argument("csv_path")

    b = sub.add_parser("recommend", help="get top-k activities")
    b.add_argument("--age", type=int, required=True, help="child age in months")
    b.add_argument("--interests", nargs="+", required=True)
    b.add_argument("--k", type=int, default=5)
    b.add_argument("--tolerance", type=int, default=2)

    args = p.parse_args()
    if args.cmd == "ingest":
        print(f"Upserted {ingest(args.csv_path)} activities.")
    else:
        for i, r in enumerate(recommend_activities(args.age, args.interests, args.k, args.tolerance), 1):
            print(f"{i}. [{r['activity_id']}] sim={r['similarity']:.3f} age={r['age_in_months']}m "
                  f"({r['interest']} / {r['target_developmental_area']})\n   {r['activity_description']}")


if __name__ == "__main__":
    main()