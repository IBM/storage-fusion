"""
Unit tests for SessionStore, Session, and Turn

Covers:
  - Turn / Session dataclasses — default field values
  - SessionStore.create()        — generates a valid UUID, stores the session
  - SessionStore.get()           — hit, miss, last_accessed updated
  - SessionStore.add_turn()      — appends to known session, no-op on unknown
  - SessionStore.set_summary()   — atomically replaces summary + turns, no-op on unknown
  - SessionStore.sweep_expired() — removes stale sessions, keeps fresh ones

Naming convention:  test_<method>_<condition>_<expected_outcome>
TC-ID convention:   TC-SS-<NNN> — matches the project's test catalogue format.

SessionStore is pure Python with no I/O — no mocks or patches needed here.
"""

import time

import pytest

from session_store import Session, SessionStore, Turn


# ---------------------------------------------------------------------------
# Turn dataclass
# ---------------------------------------------------------------------------

class TestTurnDataclass:

    @pytest.mark.unit
    @pytest.mark.session
    def test_turn_stores_query_and_answer(self) -> None:
        """TC-SS-001: Turn must store query and answer fields as given."""
        turn = Turn(query="What is CAS?", answer="CAS is a storage system.", sources=[])
        assert turn.query == "What is CAS?"
        assert turn.answer == "CAS is a storage system."

    @pytest.mark.unit
    @pytest.mark.session
    def test_turn_stores_sources_list(self) -> None:
        """TC-SS-002: sources field must be stored as-is."""
        turn = Turn(query="q", answer="a", sources=["doc.pdf"])
        assert turn.sources == ["doc.pdf"]

    @pytest.mark.unit
    @pytest.mark.session
    def test_turn_timestamp_defaults_to_recent_time(self) -> None:
        """TC-SS-003: timestamp default_factory must produce a float close to time.time()."""
        before = time.time()
        turn = Turn(query="q", answer="a", sources=[])
        after = time.time()
        assert before <= turn.timestamp <= after


# ---------------------------------------------------------------------------
# Session dataclass
# ---------------------------------------------------------------------------

class TestSessionDataclass:

    @pytest.mark.unit
    @pytest.mark.session
    def test_session_stores_session_id(self) -> None:
        """TC-SS-004: Session must store the given session_id."""
        s = Session(session_id="abc-123")
        assert s.session_id == "abc-123"

    @pytest.mark.unit
    @pytest.mark.session
    def test_session_turns_default_to_empty_list(self) -> None:
        """TC-SS-005: turns must default to an empty list, not shared state across instances."""
        s1 = Session(session_id="s1")
        s2 = Session(session_id="s2")
        s1.turns.append(Turn(query="q", answer="a", sources=[]))
        assert s2.turns == [], "Default list must not be shared between instances"

    @pytest.mark.unit
    @pytest.mark.session
    def test_session_running_summary_defaults_to_empty_string(self) -> None:
        """TC-SS-006: running_summary must default to empty string."""
        s = Session(session_id="x")
        assert s.running_summary == ""

    @pytest.mark.unit
    @pytest.mark.session
    def test_session_last_accessed_defaults_to_recent_time(self) -> None:
        """TC-SS-007: last_accessed default_factory must produce a float close to time.time()."""
        before = time.time()
        s = Session(session_id="x")
        after = time.time()
        assert before <= s.last_accessed <= after


# ---------------------------------------------------------------------------
# SessionStore.create
# ---------------------------------------------------------------------------

class TestSessionStoreCreate:

    @pytest.mark.unit
    @pytest.mark.session
    def test_create_returns_a_string(self) -> None:
        """TC-SS-008: create() must return a string."""
        store = SessionStore()
        sid = store.create()
        assert isinstance(sid, str)

    @pytest.mark.unit
    @pytest.mark.session
    def test_create_returns_unique_ids(self) -> None:
        """TC-SS-009: Two consecutive create() calls must return different IDs."""
        store = SessionStore()
        assert store.create() != store.create()

    @pytest.mark.unit
    @pytest.mark.session
    def test_create_stores_session_retrievable_by_get(self) -> None:
        """TC-SS-010: Session created via create() must be immediately retrievable via get()."""
        store = SessionStore()
        sid = store.create()
        session = store.get(sid)
        assert session is not None
        assert session.session_id == sid


# ---------------------------------------------------------------------------
# SessionStore.get
# ---------------------------------------------------------------------------

class TestSessionStoreGet:

    @pytest.mark.unit
    @pytest.mark.session
    def test_get_returns_none_for_unknown_id(self) -> None:
        """TC-SS-011: get() must return None for an ID that was never created."""
        store = SessionStore()
        assert store.get("00000000-0000-0000-0000-000000000000") is None

    @pytest.mark.unit
    @pytest.mark.session
    def test_get_updates_last_accessed(self) -> None:
        """TC-SS-012: Each get() call must update last_accessed to approximately now."""
        store = SessionStore()
        sid = store.create()
        # Backdate last_accessed so we can verify it gets refreshed.
        store._sessions[sid].last_accessed = time.time() - 1000
        before = time.time()
        store.get(sid)
        after = time.time()
        assert before <= store._sessions[sid].last_accessed <= after


# ---------------------------------------------------------------------------
# SessionStore.add_turn
# ---------------------------------------------------------------------------

class TestSessionStoreAddTurn:

    @pytest.mark.unit
    @pytest.mark.session
    def test_add_turn_appends_to_known_session(self) -> None:
        """TC-SS-013: add_turn() must append the turn to an existing session."""
        store = SessionStore()
        sid = store.create()
        turn = Turn(query="Q", answer="A", sources=[])
        store.add_turn(sid, turn)
        session = store.get(sid)
        assert len(session.turns) == 1
        assert session.turns[0].query == "Q"

    @pytest.mark.unit
    @pytest.mark.session
    def test_add_turn_noop_on_unknown_session(self) -> None:
        """TC-SS-014: add_turn() on an unknown session_id must not raise and must not create a session."""
        store = SessionStore()
        # Must not raise; unknown session is a no-op.
        store.add_turn("no-such-id", Turn(query="q", answer="a", sources=[]))
        assert store.get("no-such-id") is None


# ---------------------------------------------------------------------------
# SessionStore.set_summary
# ---------------------------------------------------------------------------

class TestSessionStoreSetSummary:

    @pytest.mark.unit
    @pytest.mark.session
    def test_set_summary_replaces_summary_and_turns(self) -> None:
        """TC-SS-015: set_summary() must atomically replace running_summary and turns."""
        store = SessionStore()
        sid = store.create()
        store.add_turn(sid, Turn(query="Q1", answer="A1", sources=[]))
        store.add_turn(sid, Turn(query="Q2", answer="A2", sources=[]))

        keep = [Turn(query="Q2", answer="A2", sources=[])]
        store.set_summary(sid, "Summary of Q1.", keep)

        session = store.get(sid)
        assert session.running_summary == "Summary of Q1."
        assert len(session.turns) == 1
        assert session.turns[0].query == "Q2"

    @pytest.mark.unit
    @pytest.mark.session
    def test_set_summary_noop_on_unknown_session(self) -> None:
        """TC-SS-016: set_summary() on an unknown session_id must not raise."""
        store = SessionStore()
        # Must not raise.
        store.set_summary("no-such-id", "summary text", [])


# ---------------------------------------------------------------------------
# SessionStore.sweep_expired
# ---------------------------------------------------------------------------

class TestSessionStoreSweepExpired:

    @pytest.mark.unit
    @pytest.mark.session
    def test_sweep_removes_expired_sessions(self) -> None:
        """TC-SS-017: Sessions not accessed within ttl_seconds must be removed by sweep_expired()."""
        store = SessionStore(ttl_seconds=60)
        sid = store.create()
        # Backdate so it looks expired.
        store._sessions[sid].last_accessed = time.time() - 3600
        store.sweep_expired()
        assert store.get(sid) is None

    @pytest.mark.unit
    @pytest.mark.session
    def test_sweep_keeps_fresh_sessions(self) -> None:
        """TC-SS-018: Sessions accessed within ttl_seconds must survive sweep_expired()."""
        store = SessionStore(ttl_seconds=3600)
        sid = store.create()
        store.sweep_expired()
        assert store.get(sid) is not None
