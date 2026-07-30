# PREREQUISITES (install these yourself before running anything):
#   - Python 3.9+      https://www.python.org/downloads/
#   - Node.js + npm    https://nodejs.org/
#
# LLM CONFIGURATION:
#   This app works with any OpenAI-compatible /v1/chat/completions API.
#   Set LLM_BASE_URL and LLM_MODEL in backend/.env to point at your LLM.
#
#   To swap the LLM, update these two lines in backend/.env:
#     LLM_BASE_URL=http://localhost:8001   # URL of your LLM service
#     LLM_MODEL=meta/llama-3.1-8b-instruct # model name to request
#
#   If your service requires authentication, also set:
#     LLM_API_KEY=<your-api-key>
#
#   Common setups:
#     NVIDIA NIM via port-forward: oc port-forward -n nv-ingest service/meta-llama-3-1-8b-instruct 8001:8000
#                                  LLM_BASE_URL=http://localhost:8001
#     Local Ollama:                LLM_BASE_URL=http://localhost:11434
#     OpenAI:                      LLM_BASE_URL=https://api.openai.com
#                                  LLM_API_KEY=sk-...
#
# QUICK START:
#   make all   — setup + run backend + frontend together
#
# Ctrl+C will shut down both the backend and the frontend.
#
# =============================================================================

.PHONY: help setup run dev all clean test test-unit test-file test-case

# --- Configuration -----------------------------------------------------------

VENV   := venv
PYTHON := $(VENV)/bin/python
PIP    := $(VENV)/bin/pip

# --- Help --------------------------------------------------------------------

help:
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "  make all            Full start: setup + backend + frontend (recommended)"
	@echo "  make setup          Create Python venv, install deps, npm install frontend"
	@echo "  make run            Run backend only"
	@echo "  make dev            Run backend in dev mode — DEBUG=true, auto-reload on file changes"
	@echo "  make clean          Delete venv and node_modules to start fresh"
	@echo ""
	@echo "  make test           Run the full unit test suite"
	@echo "  make test-unit      Same as make test (alias)"
	@echo "  make test-file F=<file>   Run one test file, e.g.:"
	@echo "                        make test-file F=test_cas_agent"
	@echo "                        make test-file F=test_validators"
	@echo "                        make test-file F=test_chunk_processor"
	@echo "                        make test-file F=test_llm_service"
	@echo "  make test-case K=<name>   Run tests whose name contains <name>, e.g.:"
	@echo "                        make test-case K=build_cas_url"
	@echo "                        make test-case K=TC-CAS-011"
	@echo "                        make test-case K=weather"
	@echo ""
	@echo "NOTE: Port-forward the NIM service before running:"
	@echo "      oc port-forward -n <your-namespace> service/meta-llama-3-1-8b-instruct 8001:8000"
	@echo ""

# --- Setup -------------------------------------------------------------------

$(VENV)/bin/activate:
	python3 -m venv $(VENV)

setup: $(VENV)/bin/activate
	$(PIP) install --upgrade pip
	$(PIP) install -r backend/requirements.txt
	cd frontend && npm install

# --- Run targets -------------------------------------------------------------

run: setup
	cd backend && ../$(PYTHON) api_server.py

dev: setup
	cd backend && DEBUG=true ../$(PYTHON) api_server.py

all: setup
	@trap 'echo "Shutting down..."; exit 0' INT; \
	( cd backend && ../$(PYTHON) api_server.py ) & \
	( cd frontend && npm run dev ) & \
	wait

# --- Clean -------------------------------------------------------------------

clean:
	rm -rf $(VENV) frontend/node_modules
	find . -type d -name "__pycache__" -exec rm -rf {} +
	find . -type d -name ".pytest_cache" -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete

# --- Test targets ------------------------------------------------------------
# These targets do NOT depend on setup — deps are assumed to already be
# installed.  Run `make setup` once first if you get import errors.

_check-venv:
	@test -f $(PYTHON) || (echo ""; echo "  ERROR: venv not found. Run 'make setup' first."; echo ""; exit 1)

# Run the full unit test suite — quiet mode: one dot per test, summary at end.
# If a test fails the full -v output is much easier to read; run make test-file
# or make test-case to drill into the failure with verbose output.
test: _check-venv
	@cd backend && ../$(PYTHON) -W ignore -m pytest testing/unit/ -q -p no:warnings

# Alias — same as test.
test-unit: test

# Run a single test file — verbose so you can see every test name.
# Usage: make test-file F=test_cas_agent
test-file: _check-venv
	@cd backend && ../$(PYTHON) -W ignore -m pytest testing/unit/$(F).py -v -p no:warnings

# Run tests whose name (or TC-ID) contains a keyword — verbose for the same reason.
# Usage: make test-case K=build_cas_url
#        make test-case K=TC-CAS-011
#        make test-case K=weather
test-case: _check-venv
	@cd backend && ../$(PYTHON) -W ignore -m pytest testing/unit/ -v -p no:warnings -k "$(K)"