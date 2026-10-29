"""
FastAPI backend: caregiver accounts, child profiles, activity recommendations
and caregiver feedback (ratings + comments) on those activities.

Setup (in addition to activity_recommender.py's requirements):
    pip install -r backend/requirements.txt

Database (once, in this order):
    sql/schema.sql  ->  sql/children_schema.sql  ->  sql/feedback_schema.sql

Run (from the repository root):
    uvicorn backend.Api:app --reload --host 0.0.0.0
Docs:
    http://localhost:8000/docs
"""
from __future__ import annotations

import datetime as dt
import os

import psycopg
from fastapi import Depends, FastAPI, HTTPException, Response, status
from fastapi.middleware.cors import CORSMiddleware
from psycopg.rows import dict_row
from pydantic import BaseModel, EmailStr, Field, field_validator

from backend.activity_recommender import DATABASE_URL, get_model, recommend_activities
from backend.auth import (
    MAX_PASSWORD_BYTES,
    create_access_token,
    current_caregiver_id,
    hash_password,
    verify_google_id_token,
    verify_password,
)

VALID_INTERESTS = {"General Play", "Games", "Reading", "Music", "Art"}

app = FastAPI(title="Activity Recommender API")
app.add_middleware(
    CORSMiddleware,
    # Native mobile apps don't need CORS; this only matters for browser clients (e.g. Flutter web).
    allow_origins=[o for o in os.environ.get("CORS_ORIGINS", "http://localhost:3000").split(",") if o],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def warm_up():
    get_model()  # load MiniLM once at startup, not on the first request


def get_conn():
    return psycopg.connect(DATABASE_URL, row_factory=dict_row)


# --------------------------------------------------------------------------- #
# Schemas
# --------------------------------------------------------------------------- #
def _check_interests(values: list[str]) -> list[str]:
    bad = set(values) - VALID_INTERESTS
    if bad:
        raise ValueError(f"Unknown interest(s): {sorted(bad)}. Valid: {sorted(VALID_INTERESTS)}")
    return list(dict.fromkeys(values))  # de-duplicate, keep order


class RegisterBody(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    email: EmailStr
    password: str = Field(min_length=8)

    @field_validator("password")
    @classmethod
    def password_fits_bcrypt(cls, v: str) -> str:
        if len(v.encode("utf-8")) > MAX_PASSWORD_BYTES:
            raise ValueError(f"Password must be at most {MAX_PASSWORD_BYTES} bytes")
        return v


class LoginBody(BaseModel):
    email: EmailStr
    password: str


class GoogleLoginBody(BaseModel):
    id_token: str = Field(min_length=1)


class ChildBody(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    birth_date: dt.date
    interests: list[str] = Field(default_factory=list)

    @field_validator("interests")
    @classmethod
    def interests_valid(cls, v: list[str]) -> list[str]:
        return _check_interests(v)

    @field_validator("birth_date")
    @classmethod
    def not_in_future(cls, v: dt.date) -> dt.date:
        if v > dt.date.today():
            raise ValueError("birth_date cannot be in the future")
        return v


class RecommendByChild(BaseModel):
    child_id: int
    interests: list[str] | None = None  # override the child's saved interests for this one call
    k: int = Field(default=5, ge=1, le=50)

    @field_validator("interests")
    @classmethod
    def interests_valid(cls, v: list[str] | None) -> list[str] | None:
        return None if v is None else _check_interests(v)


class RatingBody(BaseModel):
    rating: int = Field(ge=1, le=5)


class CommentBody(BaseModel):
    body: str = Field(min_length=1, max_length=2000)

    @field_validator("body")
    @classmethod
    def not_blank(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Comment cannot be empty")
        return v


# --------------------------------------------------------------------------- #
# Auth
# --------------------------------------------------------------------------- #
CAREGIVER_COLUMNS = "caregiver_id, name, email"


def _session(caregiver: dict) -> dict:
    return {"access_token": create_access_token(caregiver["caregiver_id"]), "token_type": "bearer", "caregiver": caregiver}


@app.post("/auth/register", status_code=201)
def register(body: RegisterBody):
    email = body.email.lower()
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute("SELECT 1 FROM caregivers WHERE LOWER(email) = %s", (email,))
        if cur.fetchone():
            raise HTTPException(409, "An account with this email already exists")
        cur.execute(
            f"INSERT INTO caregivers (name, email, password_hash) VALUES (%s, %s, %s) RETURNING {CAREGIVER_COLUMNS}",
            (body.name.strip(), email, hash_password(body.password)),
        )
        return _session(cur.fetchone())


@app.post("/auth/login")
def login(body: LoginBody):
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(
            f"SELECT {CAREGIVER_COLUMNS}, password_hash FROM caregivers WHERE LOWER(email) = %s",
            (body.email.lower(),),
        )
        row = cur.fetchone()
    if not row or not verify_password(body.password, row.pop("password_hash")):
        raise HTTPException(401, "Incorrect email or password")
    return _session(row)


@app.post("/auth/google")
def login_with_google(body: GoogleLoginBody):
    claims = verify_google_id_token(body.id_token)
    sub, email = claims["sub"], claims["email"].lower()
    name = claims.get("name") or email.split("@")[0]

    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(f"SELECT {CAREGIVER_COLUMNS} FROM caregivers WHERE google_sub = %s", (sub,))
        row = cur.fetchone()
        if row is None:
            # Link to an existing email/password account (Google has verified the email), or create one.
            cur.execute(
                f"UPDATE caregivers SET google_sub = %s WHERE LOWER(email) = %s AND google_sub IS NULL "
                f"RETURNING {CAREGIVER_COLUMNS}",
                (sub, email),
            )
            row = cur.fetchone()
        if row is None:
            cur.execute(
                f"INSERT INTO caregivers (name, email, google_sub) VALUES (%s, %s, %s) RETURNING {CAREGIVER_COLUMNS}",
                (name, email, sub),
            )
            row = cur.fetchone()
        return _session(row)


@app.get("/auth/me")
def me(caregiver_id: int = Depends(current_caregiver_id)):
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(f"SELECT {CAREGIVER_COLUMNS} FROM caregivers WHERE caregiver_id = %s", (caregiver_id,))
        row = cur.fetchone()
    if not row:
        raise HTTPException(401, "Account no longer exists")
    return row


# --------------------------------------------------------------------------- #
# Children (always scoped to the signed-in caregiver)
# --------------------------------------------------------------------------- #
CHILD_SQL = """
SELECT c.child_id, c.caregiver_id, c.name, c.birth_date, c.age_in_months,
       COALESCE(ARRAY_AGG(ci.interest ORDER BY ci.interest) FILTER (WHERE ci.interest IS NOT NULL), '{{}}') AS interests
FROM children_with_age c
LEFT JOIN child_interests ci ON ci.child_id = c.child_id
WHERE c.caregiver_id = %(caregiver_id)s {extra}
GROUP BY c.child_id, c.caregiver_id, c.name, c.birth_date, c.age_in_months
ORDER BY c.child_id
"""


def fetch_child(cur, child_id: int, caregiver_id: int) -> dict:
    """The child if it belongs to this caregiver, else 404 (never reveal other families' children)."""
    cur.execute(CHILD_SQL.format(extra="AND c.child_id = %(child_id)s"), {"caregiver_id": caregiver_id, "child_id": child_id})
    child = cur.fetchone()
    if not child:
        raise HTTPException(404, "Child not found")
    return child


def _save_interests(cur, child_id: int, interests: list[str]) -> None:
    cur.execute("DELETE FROM child_interests WHERE child_id = %s", (child_id,))
    for interest in interests:
        cur.execute("INSERT INTO child_interests (child_id, interest) VALUES (%s, %s)", (child_id, interest))


@app.get("/children")
def list_children(caregiver_id: int = Depends(current_caregiver_id)):
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(CHILD_SQL.format(extra=""), {"caregiver_id": caregiver_id})
        return cur.fetchall()


@app.post("/children", status_code=201)
def create_child(body: ChildBody, caregiver_id: int = Depends(current_caregiver_id)):
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO children (caregiver_id, name, birth_date) VALUES (%s, %s, %s) RETURNING child_id",
            (caregiver_id, body.name.strip(), body.birth_date),
        )
        child_id = cur.fetchone()["child_id"]
        _save_interests(cur, child_id, body.interests)
        return fetch_child(cur, child_id, caregiver_id)


@app.get("/children/{child_id}")
def get_child(child_id: int, caregiver_id: int = Depends(current_caregiver_id)):
    with get_conn() as conn, conn.cursor() as cur:
        return fetch_child(cur, child_id, caregiver_id)


@app.put("/children/{child_id}")
def update_child(child_id: int, body: ChildBody, caregiver_id: int = Depends(current_caregiver_id)):
    with get_conn() as conn, conn.cursor() as cur:
        fetch_child(cur, child_id, caregiver_id)  # ownership check
        cur.execute(
            "UPDATE children SET name = %s, birth_date = %s WHERE child_id = %s",
            (body.name.strip(), body.birth_date, child_id),
        )
        _save_interests(cur, child_id, body.interests)
        return fetch_child(cur, child_id, caregiver_id)


@app.delete("/children/{child_id}", status_code=204)
def delete_child(child_id: int, caregiver_id: int = Depends(current_caregiver_id)):
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute("DELETE FROM children WHERE child_id = %s AND caregiver_id = %s", (child_id, caregiver_id))
        if cur.rowcount == 0:
            raise HTTPException(404, "Child not found")
    return Response(status_code=204)


# --------------------------------------------------------------------------- #
# Recommendations
# --------------------------------------------------------------------------- #
@app.post("/recommend")
def recommend_for_child(body: RecommendByChild, caregiver_id: int = Depends(current_caregiver_id)):
    with get_conn() as conn:
        with conn.cursor() as cur:
            child = fetch_child(cur, body.child_id, caregiver_id)
        interests = body.interests or child["interests"]
        if not interests:
            raise HTTPException(400, "This child has no saved interests; pass `interests` for this call.")

        results = recommend_activities(child["age_in_months"], interests, top_k=body.k, conn=conn)

        # Attach this child's existing feedback so the app can show it on each card.
        ids = [r["activity_id"] for r in results]
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT a.activity_id, r.rating,
                       (SELECT COUNT(*) FROM activity_comments c
                         WHERE c.child_id = %(child)s AND c.activity_id = a.activity_id) AS comment_count
                FROM UNNEST(%(ids)s::text[]) AS a(activity_id)
                LEFT JOIN activity_ratings r ON r.child_id = %(child)s AND r.activity_id = a.activity_id
                """,
                {"child": body.child_id, "ids": ids},
            )
            feedback = {row["activity_id"]: row for row in cur.fetchall()}
        for r in results:
            fb = feedback.get(r["activity_id"], {})
            r["my_rating"] = fb.get("rating")
            r["comment_count"] = fb.get("comment_count", 0)

    return {
        "child_name": child["name"],
        "age_in_months": child["age_in_months"],
        "interests_used": interests,
        "results": results,
    }


# --------------------------------------------------------------------------- #
# Feedback: ratings + comments, per child and activity
# --------------------------------------------------------------------------- #
def _check_activity(cur, activity_id: str) -> None:
    cur.execute("SELECT 1 FROM activities WHERE activity_id = %s", (activity_id,))
    if not cur.fetchone():
        raise HTTPException(404, "Activity not found")


def _comments(cur, child_id: int, activity_id: str) -> list[dict]:
    cur.execute(
        """
        SELECT c.comment_id, c.body, c.created_at, c.caregiver_id, g.name AS author_name
        FROM activity_comments c JOIN caregivers g ON g.caregiver_id = c.caregiver_id
        WHERE c.child_id = %s AND c.activity_id = %s
        ORDER BY c.created_at, c.comment_id
        """,
        (child_id, activity_id),
    )
    return cur.fetchall()


@app.get("/children/{child_id}/activities/{activity_id}/feedback")
def get_feedback(child_id: int, activity_id: str, caregiver_id: int = Depends(current_caregiver_id)):
    with get_conn() as conn, conn.cursor() as cur:
        fetch_child(cur, child_id, caregiver_id)
        _check_activity(cur, activity_id)
        cur.execute(
            "SELECT rating, updated_at FROM activity_ratings WHERE child_id = %s AND activity_id = %s",
            (child_id, activity_id),
        )
        rating = cur.fetchone()
        return {
            "child_id": child_id,
            "activity_id": activity_id,
            "rating": rating["rating"] if rating else None,
            "rated_at": rating["updated_at"] if rating else None,
            "comments": _comments(cur, child_id, activity_id),
        }


@app.put("/children/{child_id}/activities/{activity_id}/rating")
def rate_activity(child_id: int, activity_id: str, body: RatingBody, caregiver_id: int = Depends(current_caregiver_id)):
    with get_conn() as conn, conn.cursor() as cur:
        fetch_child(cur, child_id, caregiver_id)
        _check_activity(cur, activity_id)
        cur.execute(
            """
            INSERT INTO activity_ratings (child_id, activity_id, rating) VALUES (%s, %s, %s)
            ON CONFLICT (child_id, activity_id) DO UPDATE SET rating = EXCLUDED.rating, updated_at = now()
            RETURNING child_id, activity_id, rating, updated_at AS rated_at
            """,
            (child_id, activity_id, body.rating),
        )
        return cur.fetchone()


@app.delete("/children/{child_id}/activities/{activity_id}/rating", status_code=204)
def clear_rating(child_id: int, activity_id: str, caregiver_id: int = Depends(current_caregiver_id)):
    with get_conn() as conn, conn.cursor() as cur:
        fetch_child(cur, child_id, caregiver_id)
        cur.execute("DELETE FROM activity_ratings WHERE child_id = %s AND activity_id = %s", (child_id, activity_id))
    return Response(status_code=204)


@app.post("/children/{child_id}/activities/{activity_id}/comments", status_code=201)
def add_comment(child_id: int, activity_id: str, body: CommentBody, caregiver_id: int = Depends(current_caregiver_id)):
    with get_conn() as conn, conn.cursor() as cur:
        fetch_child(cur, child_id, caregiver_id)
        _check_activity(cur, activity_id)
        cur.execute(
            """
            WITH c AS (
                INSERT INTO activity_comments (child_id, activity_id, caregiver_id, body)
                VALUES (%s, %s, %s, %s)
                RETURNING comment_id, body, created_at, caregiver_id
            )
            SELECT c.*, g.name AS author_name FROM c JOIN caregivers g ON g.caregiver_id = c.caregiver_id
            """,
            (child_id, activity_id, caregiver_id, body.body),
        )
        return cur.fetchone()


@app.delete("/comments/{comment_id}", status_code=204)
def delete_comment(comment_id: int, caregiver_id: int = Depends(current_caregiver_id)):
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(
            "DELETE FROM activity_comments WHERE comment_id = %s AND caregiver_id = %s",
            (comment_id, caregiver_id),
        )
        if cur.rowcount == 0:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Comment not found")
    return Response(status_code=204)
