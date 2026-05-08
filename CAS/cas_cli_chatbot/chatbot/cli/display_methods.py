"""
Display-related methods extracted from ChatbotCLI.
"""

import json
import re
from typing import Any, Protocol

from rich.markdown import Markdown
from rich.panel import Panel
from rich.table import Table
from rich.tree import Tree

# Display constants
TABLE_COLUMN_WIDTH_COMMAND = 30
UNKNOWN_FILENAME = "unknown"
UNKNOWN_FILE_ID = "unknown"
NO_TEXT_PLACEHOLDER = "No text"


class DisplayMethodsCLIProtocol(Protocol):
    """Protocol describing CLI attributes used by extracted display methods."""

    COMMANDS: dict[str, str]
    console: Any
    config: dict[str, Any]
    current_user: Any
    current_vector_store: Any
    session_manager: Any

    def _sanitize_config(self, config: dict[str, Any]) -> dict[str, Any]: ...

    def _clean_chunk_text(self, text: str) -> str: ...


def display_welcome(self: DisplayMethodsCLIProtocol) -> None:
    """Display welcome message"""
    welcome_text = """
        # Welcome to CAS Chatbot CLI

        **Features:**
        - OCP user authentication and token management
        - Vector store browsing and selection
        - Vector similarity search with filtering
        - LLM-powered queries and file operations
        - Session tracking and export
        - System health monitoring

        Type `help` to see all available commands.
    """
    self.console.print(
        Panel(Markdown(welcome_text), title="Welcome", border_style="cyan")
    )


def display_help(self: DisplayMethodsCLIProtocol, command: str | None = None) -> None:
    """Display help information"""
    if command and command in self.COMMANDS:
        self.console.print(f"\n[bold cyan]{command}[/]: {self.COMMANDS[command]}")
        return

    table = Table(
        title="Available Commands", show_header=True, header_style="bold magenta"
    )
    table.add_column("Command", style="cyan", width=TABLE_COLUMN_WIDTH_COMMAND)
    table.add_column("Description", style="white")

    categories = {
        "Vector Stores": [
            k for k in self.COMMANDS.keys() if k.startswith("vector stores")
        ],
        "Vector Search": [
            k
            for k in self.COMMANDS.keys()
            if k.startswith("vector search") or k.startswith("show file content")
        ],
        "LLM-Assisted Query": [
            k
            for k in self.COMMANDS.keys()
            if k.startswith("llm")
        ],
        "Session": [k for k in self.COMMANDS.keys() if k.startswith("session") or k.startswith("query history")],
        "System": [
            k
            for k in self.COMMANDS.keys()
            if k
            in [
                "help",
                "config show",
                "config reload",
                "metrics",
                "health",
                "clear",
                "exit",
            ]
        ],
    }

    for category, commands in categories.items():
        table.add_row(f"[bold yellow]{category}[/]", "", style="bold")
        for cmd in commands:
            table.add_row(f"  {cmd}", self.COMMANDS[cmd])

    self.console.print(table)


def display_status(self: DisplayMethodsCLIProtocol) -> None:
    """Display current CLI status"""
    status = Table.grid(padding=(0, 2))
    status.add_column(style="cyan")
    status.add_column(style="green")

    status.add_row("Current User:", self.current_user or "[dim]None[/]")
    status.add_row("Current Vector Store:", self.current_vector_store or "[dim]None[/]")
    status.add_row(
        "Session Queries:",
        str(len(self.session_manager.get_history().get("queries", []))),
    )

    self.console.print(Panel(status, title="Status", border_style="blue"))


def cmd_config_show(self: DisplayMethodsCLIProtocol) -> None:
    """Show current configuration (sanitized)"""
    sanitized = self._sanitize_config(self.config)
    self.console.print(
        Panel(
            json.dumps(sanitized, indent=2),
            title="Current Configuration",
            border_style="cyan",
        )
    )


def _sanitize_config(
    self: DisplayMethodsCLIProtocol, config: dict[str, Any]
) -> dict[str, Any]:
    """Remove sensitive information from config"""
    sensitive_keys = ["password", "secret", "token", "api_key"]
    sanitized: dict[str, Any] = {}

    for key, value in config.items():
        if isinstance(value, dict):
            sanitized[key] = self._sanitize_config(value)
        elif any(sk in key.lower() for sk in sensitive_keys):
            sanitized[key] = "***REDACTED***"
        else:
            sanitized[key] = value

    return sanitized


def _display_file_content(
    self: DisplayMethodsCLIProtocol, file_content: dict[str, Any]
) -> None:
    """Display file content with formatting."""
    self.console.print("\n[bold cyan]Retrieving file content...[/]\n")

    filename = file_content.get("filename", UNKNOWN_FILENAME)
    file_id = file_content.get("file_id", UNKNOWN_FILE_ID)

    self.console.print(
        f"[bold]\\[filename: {filename}]\n\\[file ID: {file_id}]\n[/bold]"
    )

    for chunk in file_content.get("content", []):
        for text in chunk.get("text", "").splitlines():
            cleaned_text = text.strip()
            if cleaned_text:
                self.console.print(cleaned_text)


def _clean_chunk_text(self: DisplayMethodsCLIProtocol, text: str) -> str:
    """Normalize whitespace in chunk text"""
    return re.sub(r"\s+", " ", text).strip()


def _display_search_chunks(
    self: DisplayMethodsCLIProtocol,
    search_result: dict[str, Any],
    show_metadata: bool = True,
) -> None:
    """Display search result chunks with formatting"""
    self.console.print("\n[bold cyan]Retrieving text chunks...[/]\n")

    for chunk_idx, item in enumerate(search_result.get("data", []), start=1):
        # Build file_info with known fields
        file_info = {
            "filename": item.get("filename", UNKNOWN_FILENAME),
            "file_id": item.get("file_id", UNKNOWN_FILE_ID),
        }

        # Add metadata fields if present
        metadata = item.get("metadata", {})
        if metadata:
            file_info.update(metadata)

        # Add all dynamic attributes if present
        attributes = item.get("attributes", {})
        if attributes:
            for attr_key, attr_value in attributes.items():
                file_info[f"attr_{attr_key}"] = attr_value

        for chunk in item.get("content", []):
            text = chunk.get("text", NO_TEXT_PLACEHOLDER)
            cleaned_text = self._clean_chunk_text(text)

            if show_metadata:
                # Format file_info as readable key-value pairs
                metadata_str = "\n".join([f"  {k}: {v}" for k, v in file_info.items()])
                self.console.print(
                    f"[bold]Chunk {chunk_idx}:[/bold]\n\n{metadata_str}\n\n{cleaned_text}\n"
                )
            else:
                self.console.print(f"[bold]Chunk {chunk_idx}:[/bold]\n{cleaned_text}\n")


def _build_prompt(self: DisplayMethodsCLIProtocol) -> str:
    """Build dynamic prompt with context"""
    parts = []

    if self.current_user:
        parts.append(f"[cyan]{self.current_user}[/]")

    if self.current_vector_store:
        parts.append(f"[yellow]{self.current_vector_store}[/]")

    prefix = "@".join(parts) if parts else "cas"
    return f"{prefix}> "


def render_vector_stores_tree(
    self: DisplayMethodsCLIProtocol,
    all_vector_stores: list[str],
    accessible_stores: list[str],
) -> None:
    """Render vector stores tree."""
    tree = Tree(
        f"\n[bold cyan]Vector Stores[/] ({len(all_vector_stores)} total, "
        f"{len(accessible_stores)} accessible)"
    )
    for vector_store in all_vector_stores:
        if (
            vector_store == self.current_vector_store
        ) and vector_store in accessible_stores:
            icon = "➤"
            style = "bold green"
            access_badge = "[green]✓[/]"
        elif vector_store == self.current_vector_store:
            icon = "➤"
            style = "bold white"
            access_badge = "[red]✗[/]"
        elif vector_store in accessible_stores:
            icon = "○"
            style = "white"
            access_badge = "[green]✓[/]"
        else:
            icon = "○"
            style = "dim"
            access_badge = "[red]✗[/]"

        tree.add(f"{icon} [{style}]{vector_store}[/] {access_badge}")

    self.console.print(tree)
    self.console.print()
