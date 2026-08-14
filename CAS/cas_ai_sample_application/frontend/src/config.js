/**
 * Shared application configuration constants.
 *
 * Any value that appears in more than one component, or that an operator might
 * need to tune without touching component logic, lives here.
 */

/** Base URL of the FastAPI backend.  Reads from the Vite environment variable
 *  VITE_API_URL (set in .env or at build time) and falls back to the local
 *  dev server port. */
export const API_BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000';

/** Default number of CAS chunks to request per question.
 *  Matches the server-side default in llm_service.py (RAG_MAX_RESULTS). */
export const DEFAULT_MAX_RESULTS = 10;

/** Minimum relevance score for a CAS chunk to be included in the prompt.
 *  Matches the server-side default in llm_service.py (RAG_MIN_SCORE). */
export const DEFAULT_MIN_SCORE = 0.1;
