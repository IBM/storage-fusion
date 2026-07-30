"""Query parsing utilities."""

import re
from typing import List


def split_query(text: str) -> List[str]:
    """Split a multi-question string into individual questions.

    Splits on every '?' boundary, then on newlines within each segment.
    List markers (e.g. "1." "2)" "-" "*") are stripped from the front.
    Segments shorter than 5 characters are discarded as punctuation noise.
    Returns [text] unchanged when there is no '?' or only one question survives.
    """
    if "?" not in text:
        return [text]

    candidates = []
    for seg in re.split(r"\?\s*", text):
        for line in re.split(r"\n+", seg):
            line = line.strip()
            line = re.sub(r"^[\d]+[.)]\s*|^[-*]\s*", "", line).strip()
            if len(line) >= 5:
                candidates.append(line + "?")

    return candidates if len(candidates) > 1 else [text]
