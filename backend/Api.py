"""
FastAPI backend: caregiver/child profiles + activity recommendations.

Setup (in addition to activity_recommender.py's requirements):
    pip install fastapi uvicorn psycopg[binary]

Run:
    uvicorn api:app --reload
Docs:
    http://localhost:8000/docs
"""
from __future__ import annotations

import datetime as dt
import os

import psycopg
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from psycopg.rows import dict_row
from pydantic import BaseModel, EmailStr, Field

from backend.activity_recommender import get_model, recommend_activities

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/postgres")
VALID_INTERESTS = {"General Play", "Games", "Reading", "Music", "Art"}

app = FastAPI(title="Activity Recommender API")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],  # add your frontend's real origin(s) here
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
class CaregiverCreate(BaseModel):
    name: str = Field(min_length=1)
    email: EmailStr | None = None


class ChildCreate(BaseModel):
    caregiver_id: int
    name: str = Field(min_length=1)
    birth_date: dt.date
    interests: list[str] = Field(default_factory=list)

    def validated_interests(self) -> list[str]:
        bad = set(self.interests) - VALID_INTERESTS
        if bad:
            raise ValueError(f"Unknown interest(s): {sorted(bad)}. Valid: {sorted(VALID_INTERESTS)}")
        return self.interests


class RecommendByChild(BaseModel):
    child_id: int
    interests: list[str] | None = None  # override the child's saved interests for this one call
    k: int = 5


# --------------------------------------------------------------------------- #
# Caregivers
# --------------------------------------------------------------------------- #
@app.post("/caregivers")
def create_caregiver(body: CaregiverCreate):
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO caregivers (name, email) VALUES (%s, %s) RETURNING caregiver_id, name, email",
            (body.name, body.email),
        )
        return cur.fetchone()


# --------------------------------------------------------------------------- #
# Children
# --------------------------------------------------------------------------- #
@app.post("/children")
def create_child(body: ChildCreate):
    interests = body.validated_interests()
    if body.birth_date > dt.date.today():
        raise HTTPException(400, "birth_date cannot be in the future")

    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO children (caregiver_id, name, birth_date) VALUES (%s, %s, %s) RETURNING child_id",
            (body.caregiver_id, body.name, body.birth_date),
        )
        child_id = cur.fetchone()["child_id"]
        for interest in interests:
            cur.execute(
                "INSERT INTO child_interests (child_id, interest) VALUES (%s, %s)",
                (child_id, interest),
            )
        conn.commit()
    return get_child(child_id)


@app.get("/children/{child_id}")
def get_child(child_id: int):
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute("SELECT * FROM children_with_age WHERE child_id = %s", (child_id,))
        child = cur.fetchone()
        if not child:
            raise HTTPException(404, "Child not found")
        cur.execute("SELECT interest FROM child_interests WHERE child_id = %s", (child_id,))
        child["interests"] = [r["interest"] for r in cur.fetchall()]
        return child


@app.get("/caregivers/{caregiver_id}/children")
def list_children(caregiver_id: int):
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT child_id FROM children_with_age WHERE caregiver_id = %s ORDER BY child_id",
            (caregiver_id,),
        )
        return [get_child(row["child_id"]) for row in cur.fetchall()]



@app.post("/recommend")
def recommend_for_child(body: RecommendByChild):
    child = get_child(body.child_id)  # 404s if missing
    interests = body.interests or child["interests"]
    if not interests:
        raise HTTPException(400, "This child has no saved interests; pass `interests` for this call.")
    return {
        "child_name": child["name"],
        "age_in_months": child["age_in_months"],
        "interests_used": interests,
        "results": recommend_activities(child["age_in_months"], interests, top_k=body.k),
    }