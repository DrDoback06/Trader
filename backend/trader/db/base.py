"""SQLAlchemy engine / session helpers.

Uses ``create_all`` for now (SQLite by default, Postgres in prod via the
connection string). Alembic migrations can be layered on later for schema
evolution; the `db` extra already pulls Alembic in.
"""

from __future__ import annotations

from sqlalchemy import Engine, create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker


class Base(DeclarativeBase):
    pass


def make_engine(url: str) -> Engine:
    connect_args = {"check_same_thread": False} if url.startswith("sqlite") else {}
    return create_engine(url, future=True, connect_args=connect_args)


def init_db(engine: Engine) -> None:
    from . import models  # noqa: F401  -- register tables on Base.metadata

    Base.metadata.create_all(engine)


def session_factory(engine: Engine) -> sessionmaker:
    return sessionmaker(bind=engine, expire_on_commit=False, future=True)
