# CAS Chatbot CLI

CLI application for exploring and demonstrating the CAS vector search API from the terminal.

## Project Layout

- `chatbot/` - application package and runtime documentation
- `tests/` - unit and integration tests
- `requirements.txt` - project dependencies for app and test execution
- `pytest.ini` - pytest configuration

## Quick Start

From the `cas_cli_chatbot` project root:

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

## Using the Chatbot

Refer to [chatbot/README.md](chatbot/README.md) and [GETTING_STARTED.md](GETTING_STARTED.md) for detailed usage of the chatbot.

## Running Tests

From the project root:

```bash
pytest
```

Common variants:

```bash
pytest -m unit
pytest -m integration
pytest --cov=chatbot --cov-report=term-missing
```

See [tests/README.md](tests/README.md) for detailed test guidance.

## Documentation Map

- `chatbot/README.md` - CLI overview, commands, and CAS workflow
- `chatbot/GETTING_STARTED.md` - setup and configuration details
- `tests/README.md` - testing guide
- `chatbot/LLM_SETUP.md` - optional LLM provider setup
- `chatbot/VECTOR_STORE_STARTUP_SELECTION.md` - startup vector store behavior

## Notes

- Create one virtual environment at the project root.
- Install dependencies from the root `requirements.txt`.