"""In-memory session history store."""

import logging
import threading
import time
import uuid
from dataclasses import dataclass, field
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)


@dataclass
class Turn:
    """A single question-answer exchange within a session."""

    query: str
    answer: str
    sources: List[str]
    timestamp: float = field(default_factory=time.time)


@dataclass
class Session:
    """A conversation session comprising an ordered sequence of turns."""

    session_id: str
    turns: List[Turn] = field(default_factory=list)
    last_accessed: float = field(default_factory=time.time)
    running_summary: str = ""
    # The subject last established by a resolved *question*, independent of
    # whether that question's retrieval succeeded. Tracked separately from
    # turns/running_summary because deriving "what are we talking about" from
    # answer text is unreliable — an answer can correctly address the right
    # subject without ever restating its name, and a failed retrieval
    # ("not available") shouldn't erase a subject the user explicitly named.
    active_subject: str = ""


class SessionStore:
    """Thread-safe in-memory store for active conversation sessions."""

    def __init__(self, ttl_seconds: int = 3600) -> None:
        self._sessions: Dict[str, Session] = {}
        self._lock = threading.Lock()
        self._ttl_seconds = ttl_seconds

    def set_summary(self, session_id: str, summary: str, turns_to_keep: List[Turn]) -> None:
        """Replace the session's turns with *turns_to_keep* and store *summary*."""
        with self._lock:
            session = self._sessions.get(session_id)
            if session is None:
                logger.warning("set_summary_skipped unknown session_id=%s", session_id)
                return
            session.running_summary = summary
            session.turns = list(turns_to_keep)

    def set_active_subject(self, session_id: str, subject: str) -> None:
        """Record the subject established by the most recently resolved question.

        Called after resolving a query's retrieval text — regardless of
        whether retrieval later succeeds — so a subject the user explicitly
        named survives even a "not available" answer for that turn.
        """
        if not subject:
            return
        with self._lock:
            session = self._sessions.get(session_id)
            if session is None:
                logger.warning("set_active_subject_skipped unknown session_id=%s", session_id)
                return
            session.active_subject = subject

    def create(self) -> str:
        """Create a new session and return its id."""
        session_id = str(uuid.uuid4())
        session = Session(session_id=session_id)
        with self._lock:
            self._sessions[session_id] = session
        logger.debug("session_created id=%s", session_id)
        return session_id

    def get(self, session_id: str) -> Optional[Session]:
        """Return the session for *session_id*, or None if it does not exist."""
        with self._lock:
            session = self._sessions.get(session_id)
            if session is not None:
                session.last_accessed = time.time()
            return session

    def add_turn(self, session_id: str, turn: Turn) -> None:
        """Append *turn* to the session identified by *session_id*."""
        with self._lock:
            session = self._sessions.get(session_id)
            if session is None:
                logger.warning("add_turn_skipped unknown session_id=%s", session_id)
                return
            session.turns.append(turn)

    def delete(self, session_id: str) -> bool:
        """Delete a session immediately. Returns True if it existed, False otherwise."""
        with self._lock:
            existed = session_id in self._sessions
            if existed:
                del self._sessions[session_id]
        if existed:
            logger.debug("session_deleted id=%s", session_id)
        return existed

    def needs_compaction(self, session_id: str, max_tokens: int, threshold: float) -> bool:
        """Return True when the session's history exceeds the compaction budget.

        Moved here from LLMService so that the decision about whether session
        state needs trimming is owned by the session layer, not the LLM I/O layer.

        Args:
            session_id:  The session to check.
            max_tokens:  Token budget ceiling (e.g. SESSION_MAX_CONTEXT_TOKENS).
            threshold:   Fraction of the budget at which compaction fires (e.g. 0.80).
        """
        with self._lock:
            session = self._sessions.get(session_id)
        if session is None or not session.turns:
            return False
        full_text = " ".join(f"{t.query} {t.answer}" for t in session.turns)
        budget = int(max_tokens * threshold)
        # 1 token ≈ 4 characters (same heuristic as LLMService.estimate_tokens)
        return len(full_text) // 4 > budget

    def sweep_expired(self) -> None:
        """Remove sessions that have not been accessed within the TTL window."""
        cutoff = time.time() - self._ttl_seconds
        with self._lock:
            expired = [sid for sid, s in self._sessions.items() if s.last_accessed < cutoff]
            for sid in expired:
                del self._sessions[sid]
        if expired:
            logger.info("session_sweep removed=%d", len(expired))