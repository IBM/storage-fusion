"""Query parsing and classification utilities."""

import re
from typing import List


def split_query(text: str) -> List[str]:
    """Split only explicit multi-line requests into individual questions."""
    lines = []
    for raw_line in re.split(r"\n+", text):
        line = raw_line.strip()
        line = re.sub(r"^[\d]+[.)]\s*|^[-*]\s*", "", line).strip()
        if len(line) >= 5:
            lines.append(line)
    return lines if len(lines) > 1 else [text]


# ---------------------------------------------------------------------------
# Query classification helpers
# Used by LLMService._resolve_query_from_block to decide the rewrite strategy.
# Pure functions — no LLM calls, no external state.
# ---------------------------------------------------------------------------

# Dangling-pronoun pattern — queries containing these cannot be self-contained
# because the subject is only implicit.
_DANGLING_PRONOUN = re.compile(
    r'\b(there|here|that|those|this|these|it|they|them|their|those|such)\b',
    re.IGNORECASE,
)

# Trailing location pronoun — "there", "here", "it", "those", "that" appearing
# at the very END of a short fragment (optionally before a "?").  When a fragment
# is otherwise a bare metric name (no verb, no wh-word) the trailing pronoun
# just means "for [the active subject]" and should be stripped before templating.
_TRAILING_LOCATION_PRONOUN = re.compile(
    r'\s+(there|here|it|those|that)\s*\??\s*$',
    re.IGNORECASE,
)

# Wh-question words that indicate a query states its own metric intention.
_WH_PATTERN = re.compile(
    r'\b(how many|how much|what is|what was|what are|what were|what percentage|'
    r'when did|where is|which|who|tell me|give me|list|describe|explain)\b',
    re.IGNORECASE,
)

# Explicit topic-switch dash: a space before the dash, meaning it separates
# two distinct phrases (e.g. "Subject X — metric?"), not a hyphenated word.
_TOPIC_SWITCH_PATTERN = re.compile(r'\s[—–\-]\s*\w', re.UNICODE)

# A verb suggests the fragment is already a real clause (something for an
# LLM to legitimately paraphrase), not a bare noun-phrase metric name.
_VERB_HINT = re.compile(
    r'\b(is|are|was|were|do|does|did|has|have|had|will|would|can|could|should)\b',
    re.IGNORECASE,
)

# Named-entity indicator: any capitalised word that is NOT the first word of
# the query.  Used by api_server to decide whether to persist active_subject —
# even single-word names ("Milton", "FEMA") should trigger a subject update.
_NAMED_ENTITY = re.compile(r'(?<!\A)(?<=\s)[A-Z][a-zA-Z]+')

# Named-subject indicator (stricter): two or more capitalised non-first words.
# Used by is_self_contained() so that bare single-word state/city names
# ("Georgia", "Tennessee") do NOT bypass the rewriter — they need event
# context that only history can provide.
_NAMED_SUBJECT = re.compile(r'(?<!\A)(?<=\s)[A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+)+')

# Question-starter phrases that indicate a partial sentence rather than a
# bare metric fragment — e.g. "How about X?" or "What about Y?".  These
# need a full LLM rewrite, not template concatenation.
_QUESTION_STARTER = re.compile(
    r'^(how about|what about|and what|tell me about|give me)\b',
    re.IGNORECASE,
)


def is_self_contained(query: str) -> bool:
    """Return True when a query should bypass the LLM rewriter.

    A query is self-contained when it already expresses BOTH its subject
    AND its metric intention unambiguously, making rewriting unnecessary
    and potentially harmful (the rewriter can corrupt metric types).

    Conditions:
    1. Longer than 6 chars (not a bare fragment).
    2. No dangling pronoun that requires history to resolve.
    3a. Contains an explicit topic-switch dash ("Subject — metric?"), OR
    3b. Contains a wh-question word AND a named subject (a capitalised
        non-first word, e.g. "Kentucky", "Blair", "FEMA").

    Condition 3b requires the named-subject check so that generic
    follow-ups like "How many cases were made" (wh-question, no named
    subject) are NOT treated as self-contained — they still need the
    session rewriter to inject the active subject from history.
    """
    stripped = query.strip()
    if len(stripped) <= 6:
        return False
    if _DANGLING_PRONOUN.search(stripped):
        return False
    if _TOPIC_SWITCH_PATTERN.search(stripped):
        return True
    # Require ≥2 capitalised tokens (enforced by _NAMED_SUBJECT regex) so that
    # bare single-word state names ("Georgia") don't bypass the rewriter.
    if _WH_PATTERN.search(stripped) and _NAMED_SUBJECT.search(stripped):
        return True
    return False


def is_bare_metric_fragment(query: str) -> bool:
    """Return True for short noun-phrase fragments that name a metric but
    omit the subject — e.g. "Organizations?", "Muck-out percentage?",
    "Volunteer value?" — with no pronoun and no verb, i.e. nothing an LLM
    rewrite step needs to genuinely paraphrase.

    Also returns True for fragments with a trailing location pronoun
    ("Organizations there?", "Cases here?") where the pronoun is simply
    shorthand for "for [the active subject]" and carries no real clause
    content.  The pronoun is stripped by the caller before templating.

    These are handled by template concatenation in _resolve_query_from_block
    instead of a full LLM rewrite, because letting the rewriter re-author the
    metric wording causes metric-type corruption.
    """
    stripped = query.strip()
    if not stripped or len(stripped) > 40:
        return False
    # Allow a trailing location pronoun ("there", "here", "it", "those",
    # "that") — strip it first, then check the remaining metric noun phrase.
    core = _TRAILING_LOCATION_PRONOUN.sub("", stripped).strip()
    if _DANGLING_PRONOUN.search(core):
        return False
    if _WH_PATTERN.search(core):
        return False
    if _VERB_HINT.search(core):
        return False
    if _QUESTION_STARTER.search(core):
        return False
    return True


def strip_trailing_pronoun(query: str) -> str:
    """Remove a trailing location pronoun from a bare metric fragment.

    Used by _resolve_query_from_block to clean "Organizations there?" →
    "Organizations" before templating as "Organizations for {subject}".
    """
    return _TRAILING_LOCATION_PRONOUN.sub("", query.strip()).strip()
