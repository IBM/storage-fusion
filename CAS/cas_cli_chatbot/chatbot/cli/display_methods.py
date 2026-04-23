"""
Display-related methods extracted from ChatbotCLI.
"""

import json
import re
from typing import Dict, Optional

from rich.markdown import Markdown
from rich.panel import Panel
from rich.table import Table
from rich.tree import Tree

# Display constants
TABLE_COLUMN_WIDTH_COMMAND = 30


def display_welcome(self):
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
        Panel(Markdown(welcome_text), title="Welcome", border_style="cyan"))


def display_help(self, command: Optional[str] = None):
    """Display help information"""
    if command and command in self.COMMANDS:
        self.console.print(
            f"\n[bold cyan]{command}[/]: {self.COMMANDS[command]}")
        return

    table = Table(title="Available Commands",
                  show_header=True,
                  header_style="bold magenta")
    table.add_column("Command", style="cyan", width=TABLE_COLUMN_WIDTH_COMMAND)
    table.add_column("Description", style="white")

    categories = {
        'Vector stores': [
            k for k in self.COMMANDS.keys() if k.startswith('vector stores')
        ],
        'Vector search': [
            k for k in self.COMMANDS.keys()
            if k.startswith('vector search') or
            k.startswith('show file content')
        ],
        'Queries': [
            k for k in self.COMMANDS.keys()
            if k.startswith('query') or k.startswith('llm')
        ],
        'Session': [
            k for k in self.COMMANDS.keys() if k.startswith('session')
        ],
        'System': [
            k for k in self.COMMANDS.keys() if k in [
                'help', 'config show', 'config reload', 'metrics', 'health',
                'clear', 'exit', 'quit'
            ]
        ]
    }

    for category, commands in categories.items():
        table.add_row(f"[bold yellow]{category}[/]", "", style="bold")
        for cmd in commands:
            table.add_row(f"  {cmd}", self.COMMANDS[cmd])

    self.console.print(table)


def display_status(self):
    """Display current CLI status"""
    status = Table.grid(padding=(0, 2))
    status.add_column(style="cyan")
    status.add_column(style="green")

    status.add_row("Current User:", self.current_user or "[dim]None[/]")
    status.add_row("Current Vector Store:", self.current_vector_store or
                   "[dim]None[/]")
    status.add_row(
        "Session Queries:",
        str(len(self.session_manager.get_history().get('queries', []))))

    self.console.print(Panel(status, title="Status", border_style="blue"))


def cmd_config_show(self):
    """Show current configuration (sanitized)"""
    sanitized = self._sanitize_config(self.config)
    self.console.print(
        Panel(json.dumps(sanitized, indent=2),
              title="Current Configuration",
              border_style="cyan"))


def _sanitize_config(self, config: Dict) -> Dict:
    """Remove sensitive information from config"""
    sensitive_keys = ['password', 'secret', 'token', 'api_key']
    sanitized = {}

    for key, value in config.items():
        if isinstance(value, dict):
            sanitized[key] = self._sanitize_config(value)
        elif any(sk in key.lower() for sk in sensitive_keys):
            sanitized[key] = "***REDACTED***"
        else:
            sanitized[key] = value

    return sanitized


def _display_file_content(self, file_content: Dict) -> None:
    """Display file content with formatting."""
    self.console.print("\n[bold cyan]Retrieving file content...[/]\n")

    filename = file_content.get("filename", self.UNKNOWN_FILENAME)
    file_id = file_content.get("file_id", self.UNKNOWN_FILE_ID)

    self.console.print(
        f"[bold]\\[filename: {filename}]\n\\[file ID: {file_id}]\n[/bold]")

    for chunk in file_content.get("content", []):
        for text in chunk.get("text", "").splitlines():
            cleaned_text = text.strip()
            if cleaned_text:
                self.console.print(cleaned_text)


def _clean_chunk_text(self, text: str) -> str:
    """Normalize whitespace in chunk text"""
    return re.sub(r"\s+", " ", text).strip()


def _display_search_chunks(self, search_result: Dict) -> None:
    """Display search result chunks with formatting"""
    self.console.print("\n[bold cyan]Retrieving text chunks...[/]\n")

    for chunk_idx, item in enumerate(search_result.get("data", []), start=1):
        filename = item.get("filename", self.UNKNOWN_FILENAME)
        file_id = item.get("file_id", self.UNKNOWN_FILE_ID)

        for chunk in item.get("content", []):
            text = chunk.get("text", self.NO_TEXT_PLACEHOLDER)
            cleaned_text = self._clean_chunk_text(text)

            self.console.print(
                f"[bold]Chunk {chunk_idx}:[/bold]\n\\[filename: {filename}]\n"
                f"\\[file ID: {file_id}]\n{cleaned_text}\n")


def _build_prompt(self) -> str:
    """Build dynamic prompt with context"""
    parts = []

    if self.current_user:
        parts.append(f"[cyan]{self.current_user}[/]")

    if self.current_vector_store:
        parts.append(f"[yellow]{self.current_vector_store}[/]")

    prefix = "@".join(parts) if parts else "cas"
    return f"{prefix}> "


def render_vector_stores_tree(self, all_vector_stores, accessible_stores):
    """Render vector stores tree."""
    tree = Tree(
        f"\n[bold cyan]Vector Stores[/] ({len(all_vector_stores)} total, "
        f"{len(accessible_stores)} accessible)")
    for vector_store in all_vector_stores:
        if (vector_store == self.current_vector_store
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
