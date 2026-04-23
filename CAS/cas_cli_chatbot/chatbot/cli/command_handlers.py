"""
Command handler methods extracted from ChatbotCLI.
"""

from typing import Dict, Optional

from prompt_toolkit.completion import FuzzyCompleter, WordCompleter
from prompt_toolkit.shortcuts import confirm
from rich.panel import Panel
from rich.prompt import Confirm
from rich.table import Table

# Display constants
TABLE_COLUMN_WIDTH_INDEX = 4
TABLE_COLUMN_WIDTH_TIME = 20
TABLE_COLUMN_WIDTH_USER = 15
TABLE_COLUMN_WIDTH_VECTOR_STORE = 15
TABLE_COLUMN_WIDTH_COMMAND = 25
MAX_QUERY_HISTORY_DISPLAY = 20
MAX_QUERY_PREVIEW_LENGTH = 50



def cmd_vector_stores_list(self):
    """List vector stores accessible to user and all available vector stores in namespace"""
    all_vector_stores = self.services['vector store'].list_vector_stores(
        self.current_namespace)

    if not all_vector_stores:
        self.console.print(
            "[yellow]No vector stores/domains found in OpenShift[/]")
        return

    accessible_stores = self._accessible_vector_stores()
    self.render_vector_stores_tree(all_vector_stores, accessible_stores)


def cmd_vector_stores_select(self, vector_store_name: str | None = None):
    """Select a vector store."""
    all_vector_stores = self.services['vector store'].list_vector_stores(
        self.current_namespace)

    if not all_vector_stores:
        self.console.print("[red]No vector stores/domains available[/]")
        return

    accessible_stores = self._accessible_vector_stores()
    self.cmd_vector_stores_list()

    if vector_store_name:
        selected = vector_store_name.strip()
    else:
        completer = FuzzyCompleter(
            WordCompleter(all_vector_stores, ignore_case=True))
        selected = self.session.prompt(
            "Select vector store/domain (type to search): ",
            completer=completer).strip()

    self._set_vector_store(selected, all_vector_stores, accessible_stores)


def _set_vector_store(
    self,
    selected: str,
    all_vector_stores: list,
    accessible_vector_stores: list,
) -> None:
    """Helper to validate and set vector store selection."""
    if selected in all_vector_stores:
        if selected in accessible_vector_stores:
            self.current_vector_store = selected
            self.console.print(
                f"[bold green]✓ Selected vector store: {self.current_vector_store}[/]"
            )
            self.logger.info(
                f"Vector store selected: {self.current_vector_store}")

            if self.config_manager:
                try:
                    self.config_manager.update_default_vector_store(selected)
                except Exception as e:
                    self.logger.warning(f"Failed to update config file: {e}")

        else:
            self.console.print(
                f"[yellow]⚠ You selected '{selected}' but don't have access to it.[/]"
            )
            self.console.print(
                "[dim]To gain access, please assign your user to this vector store in the Fusion UI.[/]"
            )
            self.console.print(
                "[yellow]You can select a different vector store using 'vector-stores select' command.[/]"
            )
            self.current_vector_store = None
    else:
        self.console.print(f"[red]✗ Vector store not found: {selected}[/]")
        self.console.print(
            "[yellow]You can select a different vector store using 'vector stores select' command.[/]"
        )
        self.current_vector_store = None


def cmd_vector_stores_info(self):
    """Show detailed vector store information with assigned users"""
    if not self.current_vector_store:
        self.console.print(
            "[red]✗ No vector stores/domains selected. Use 'vector stores select' first.[/]"
        )
        return

    self.console.print(
        f"\n[bold cyan]Vector Store Information: {self.current_vector_store}[/]\n"
    )

    vector_store_service = self.services['vector store']
    try:
        vector_store_info = vector_store_service.get_vector_store_details(
            self.current_vector_store, self.current_namespace)
    except TypeError:
        vector_store_info = vector_store_service.get_vector_store_details(
            self.current_vector_store)

    if vector_store_info:
        info_table = Table(title=f"Vector Store: {self.current_vector_store}",
                           show_header=False)
        info_table.add_column("Property", style="cyan")
        info_table.add_column("Value", style="white")

        info_table.add_row("Vector Store Name",
                           vector_store_info.get('name', 'N/A'))
        info_table.add_row("Namespace", vector_store_info.get('namespace',
                                                              'N/A'))
        info_table.add_row("Created", vector_store_info.get('created', 'N/A'))

        assigned = vector_store_info.get('assigned_users', {})
        ocp_users = assigned.get('users', [])
        total = assigned.get('total', 0)

        info_table.add_row("Total Assigned Users", str(total))
        info_table.add_row("Users",
                           ", ".join(ocp_users) if ocp_users else "[dim]None[/]")

        self.console.print(info_table)
    else:
        self.console.print(
            f"[yellow]Could not fetch details for vector store/domain: {self.current_vector_store}[/]"
        )


def cmd_query_ask(self) -> None:
    """Ask a query using LLM with user-specific authentication"""
    if not self._user_in_vector_store(self.current_vector_store):
        return

    if not self._check_token():
        return

    if not self._ensure_llm_configured():
        return

    query = self._get_query_input()
    if not query:
        return

    self.console.print(
        "\n[bold cyan]Processing query with user-specific authentication...[/]\n"
    )

    try:
        self._execute_query_with_llm(query)
    except Exception as e:
        self.error_handler.handle_error(
            e, f"Query execution for user {self.current_user}")


def cmd_query_history(self):
    """Show query history"""
    queries = self.session_manager.get_history().get('queries', [])

    if not queries:
        self.console.print("[yellow]No queries in history[/]")
        return

    table = Table(title="Query History", show_header=True)
    table.add_column("#", style="dim", width=TABLE_COLUMN_WIDTH_INDEX)
    table.add_column("Time", style="cyan", width=TABLE_COLUMN_WIDTH_TIME)
    table.add_column("User", style="green", width=TABLE_COLUMN_WIDTH_USER)
    table.add_column("Vector Store", style="yellow", width=TABLE_COLUMN_WIDTH_VECTOR_STORE)
    table.add_column("Query", style="white")

    for idx, q in enumerate(queries[-MAX_QUERY_HISTORY_DISPLAY:], 1):
        query_text = q.get('query', 'N/A')
        display_query = (
            query_text[:MAX_QUERY_PREVIEW_LENGTH] + "..."
            if len(query_text) > MAX_QUERY_PREVIEW_LENGTH
            else query_text
        )
        table.add_row(
            str(idx),
            q.get('timestamp', 'N/A'),
            q.get('user', 'N/A'),
            q.get('vector store', 'N/A'),
            display_query
        )

    self.console.print(table)


def cmd_session_info(self):
    """Show comprehensive session information"""
    history = self.session_manager.get_history()
    stats = self.session_manager.get_statistics()

    status = Table.grid(padding=(0, 2))
    status.add_column(style="cyan", justify="right")
    status.add_column(style="green")

    status.add_row("Current User:", self.current_user or "[dim]None[/]")
    status.add_row("Current Vector Store:", self.current_vector_store or
                   "[dim]None[/]")

    self.console.print(
        Panel(status, title="Current Session", border_style="blue"))

    stats_table = Table(title="Session Statistics", show_header=True)
    stats_table.add_column("Metric", style="cyan")
    stats_table.add_column("Value", style="green")

    stats_table.add_row("Session Started", stats.get('session_start',
                                                     'Unknown'))
    stats_table.add_row("Last Updated", stats.get('last_updated', 'Unknown'))
    stats_table.add_row("Total Queries", str(stats.get('total_queries', 0)))
    stats_table.add_row("Total File Lookups",
                        str(len(history.get('file_lookups', []))))
    stats_table.add_row("Unique Vector Stores",
                        str(stats.get('unique_vector_stores', 0)))

    self.console.print(stats_table)


def cmd_session_export(self):
    """Export session to file"""
    filename = self.session.prompt(
        "Enter filename (default: session_export.json): ").strip(
        ) or "session_export.json"

    try:
        self.session_manager.export(filename)
        self.console.print(f"[green]✓ Session exported to {filename}[/]")
    except Exception as e:
        self.console.print(f"[red]✗ Export failed: {str(e)}[/]")


def cmd_session_clear(self):
    """Clear session history"""
    if confirm("Clear all session history? This cannot be undone."):
        self.session_manager.clear()
        self.console.print("[green]✓ Session history cleared[/]")


def cmd_metrics(self):
    """Show application metrics"""
    metrics = self.services['metrics'].get_all_metrics()

    table = Table(title="Application Metrics")
    table.add_column("Metric", style="cyan")
    table.add_column("Value", style="green")

    for key, value in metrics.items():
        table.add_row(key, str(value))

    self.console.print(table)


def cmd_health(self):
    """Run health checks"""
    from chatbot.utils.health_check import HealthChecker
    checker = HealthChecker(self.services, self.logger)
    results = checker.run_all_checks()

    table = Table(title="Health Check Results")
    table.add_column("Service", style="cyan")
    table.add_column("Status", style="white")
    table.add_column("Message", style="dim")

    for service, result in results.items():
        status = "[green]✓ Healthy[/]" if result[
            'healthy'] else "[red]✗ Unhealthy[/]"
        table.add_row(service, status, result['message'])

    self.console.print(table)


def cmd_clear(self):
    """Clear screen"""
    self.console.clear()
    self.display_welcome()


def _accessible_vector_stores(self) -> list[str]:
    """List vector_stores available to user"""
    if not self._check_token():
        return []

    vector_stores = self.services['query'].list_vector_stores()

    if not vector_stores:
        return []

    return vector_stores


def cmd_vector_search(self) -> None:
    """Execute vector search with user-specific authentication."""
    if not self._user_in_vector_store(self.current_vector_store):
        return

    if not self._check_token():
        return

    vector_store = self._get_active_vector_store()
    if not vector_store:
        return

    query = self._get_input(
        f"[{self.current_user}@{self.current_vector_store or 'global'}] Enter your query: "
    )

    limit_str = self._get_input(
        f"[{self.current_user}@{self.current_vector_store or 'global'}] Enter the number of chunks to retrieve: "
    )
    
    # Convert limit to integer
    try:
        limit = int(limit_str) if limit_str else None
    except ValueError:
        self.console.print(f"[red]✗ Invalid limit value: '{limit_str}'. Must be a number.[/]")
        return

    self.console.print("\n[bold cyan]Performing vector search...[/]\n")

    try:
        search_result = self._execute_vector_search(query, vector_store, limit)

        if search_result:
            data = search_result.get("data", [])
            if data:
                self._display_search_chunks(search_result)
                self._record_successful_query(query)
            else:
                self.console.print(
                    "[yellow]No chunks found matching your query.[/]\n"
                    "[dim]Try rephrasing your query or using different keywords.[/]"
                )

    except (KeyError, ValueError, ConnectionError) as e:
        self.error_handler.handle_error(
            e, f"Query execution for user {self.current_user}")
    except Exception as e:
        self.logger.critical(f"Unexpected error in vector search: {e}",
                             exc_info=True)
        self.error_handler.handle_error(
            e, f"Unexpected query error for user {self.current_user}")


def cmd_vector_search_filter(self):
    """Retrieve raw chunks with user-specific authentication and filters"""
    if not self._user_in_vector_store(self.current_vector_store):
        return

    if not self._check_token():
        return

    query = self._get_input(
        f"[{self.current_user}@{self.current_vector_store or 'global'}] Enter your query: "
    )

    limit_str = self._get_input(
        f"[{self.current_user}@{self.current_vector_store or 'global'}] Enter the number of chunks to retrieve: "
    )
    
    # Convert limit to integer
    try:
        limit = int(limit_str) if limit_str else None
    except ValueError:
        self.console.print(f"[red]✗ Invalid limit value: '{limit_str}'. Must be a number.[/]")
        return

    self.console.print(
        "\n[bold cyan]Performing vector search with filter...[/]\n")

    self.console.print("Enter your filter (key, type, value) \n")
    key = self.session.prompt(" - key: ").strip()
    operator = self.session.prompt(
        " - type (eq, ne, gt, gte, lt, lte, in, nin, contains): ").strip()
    raw_value = self.session.prompt(" - value: ").strip()

    if operator in {"in", "nin"}:
        value = [v.strip() for v in raw_value.split(",")]
    else:
        value = raw_value

    query_filter = {"key": key, "type": operator, "value": value}

    try:
        self.logger.info(
            f"Executing filtered query for user {self.current_user} ({self.user_type})"
        )

        search_result = self.services['query'].query_with_filters(
            user_query=query,
            filters=query_filter,
            vector_store=self.current_vector_store,
            limit=limit)

        if self._retrieved_result_valid(search_result, "Query"):
            self._display_search_chunks(search_result)

            self.session_manager.add_query(user=self.current_user,
                                           query=query,
                                           vector_store=self.current_vector_store,
                                           user_type=self.user_type,
                                           authenticated=True)

            self.logger.info(
                f"Filtered query completed successfully for {self.current_user}"
            )

    except (KeyError, ValueError, ConnectionError) as e:
        self.error_handler.handle_error(
            e, f"Filtered query execution for user {self.current_user}")
    except Exception as e:
        self.logger.critical(
            f"Unexpected error in filtered vector search: {e}")
        self.error_handler.handle_error(
            e, f"Unexpected filtered query error for user {self.current_user}")


def cmd_casapi_show_file_content(self):
    """Returns all the content (text chunks) for a specific vector-store and file by their IDs"""
    if not self._user_in_vector_store(self.current_vector_store):
        return

    if not self._check_token():
        return

    identifiers = self._get_file_identifiers()
    if not identifiers:
        return

    vector_store_id, file_id = identifiers

    try:
        file_content = self._retrieve_file_content(vector_store_id, file_id)
        if not file_content:
            return

        self._display_file_content(file_content)
        self._record_file_lookup(vector_store_id, file_id)

    except Exception as e:
        self.error_handler.handle_error(
            e, f"File content retrieval for user {self.current_user}")


def cmd_casapi_query_file(self):
    """Query a specific file from a vector store using LLM"""
    if not self._user_in_vector_store(self.current_vector_store):
        return

    if not self._check_token():
        return

    if not self._ensure_llm_configured():
        return

    identifiers = self._get_file_identifiers()
    if not identifiers:
        return

    vector_store_id, file_id = identifiers

    query = self._get_input(
        f"[{self.current_user}@{self.current_vector_store or 'global'}] Enter your query: "
    )
    self.console.print(
        "\n[bold cyan]Processing query with user-specific authentication...[/]\n"
    )

    try:
        file_content = self._retrieve_file_content(vector_store_id, file_id)
        if not file_content:
            return

        self.console.print("\n[bold cyan]Getting AI response...[/]\n")
        self.services['llm'].call_llm(file_content, query)

        self.session_manager.add_query(user=self.current_user,
                                       query=query,
                                       vector_store=self.current_vector_store,
                                       user_type=self.user_type,
                                       authenticated=True)

        self.logger.info(
            f"Query completed successfully for {self.current_user}")

    except Exception as e:
        self.error_handler.handle_error(
            e,
            f"Query execution of specified file for user {self.current_user}")


def cmd_casapi_vector_stores_info(self):
    """Show detailed vector store information with assigned users"""
    if not self.current_vector_store:
        self.console.print(
            "[red]✗ No vector stores/domains selected. Use 'vector_stores select' first.[/]"
        )
        return

    self.console.print(
        f"\n[bold cyan]Vector Store Information: {self.current_vector_store}[/]\n"
    )

    vector_store_info = self.services['query'].get_vector_store_info(
        self.current_vector_store)

    if vector_store_info:
        name = vector_store_info.get('name')
        vs_id = vector_store_info.get('id')
        created_at = vector_store_info.get('created_at')
        vs_bytes = vector_store_info.get('bytes')
        file_counts = vector_store_info.get('file_counts')
        vs_object = vector_store_info.get('object')

        info_table = Table(title=f"Vector Store: {self.current_vector_store}",
                           show_header=False)
        info_table.add_column("Property", style="cyan")
        info_table.add_column("Value", style="white")

        info_table.add_row("Vector Store Name", "N/A" if name is None else name)
        info_table.add_row("ID", "N/A" if vs_id is None else vs_id)
        info_table.add_row("Created",
                           "N/A" if created_at is None else created_at)
        info_table.add_row("Bytes", "N/A" if vs_bytes is None else vs_bytes)
        info_table.add_row("File Count",
                           "N/A" if file_counts is None else file_counts)
        info_table.add_row("Object", "N/A" if vs_object is None else vs_object)

        self.console.print(info_table)
    else:
        self.console.print(
            f"[yellow]Could not fetch details for vector store/domain: {self.current_vector_store}[/]"
        )


def _prompt_vector_store_selection(self) -> None:
    """Prompt user to select a vector store at startup."""
    vector_stores_list = self.services["vector store"].list_vector_stores(
        self.current_namespace)
    if not vector_stores_list:
        self.console.print("[red]No vector stores found. Please create one.[/]")
        return

    default_vector_store = self.config.get("default_vector_store")

    placeholders = ["<default-vector-store-name>", ""]
    if default_vector_store in placeholders:
        default_vector_store = None

    if default_vector_store:
        self.console.print(
            f"\n[bold cyan]Default vector store '{default_vector_store}' detected in config. Validating...[/]\n"
        )

        valid_store = self._user_in_vector_store(default_vector_store)
        if not valid_store:
            self.cmd_vector_stores_select()
        else:
            self.console.print(
                f"[bold green]✓ {default_vector_store} is validated[/]")
            use_default = Confirm.ask("[yellow]Use this vector store?[/]",
                                      default=True)

            if use_default:
                self.current_vector_store = default_vector_store
                self.console.print(
                    f"[bold green]✓ Using vector store: {default_vector_store}[/]"
                )
            else:
                self.cmd_vector_stores_select()
    else:
        self.console.print(
            "\n[bold cyan]No default vector store configured. Please select one:[/]\n"
        )
        self.cmd_vector_stores_select()


def cmd_llm_setup(self) -> None:
    """Interactively configure an LLM provider."""
    self._prompt_llm_setup()


def execute_command(self, command: str):
    """Execute a CLI command"""
    if command.startswith('vector stores select'):
        parts = command.split(maxsplit=3)
        if len(parts) == 4:
            vector_store_name = parts[3]
            self.cmd_vector_stores_select(vector_store_name)
        else:
            self.cmd_vector_stores_select()
        return

    command_map = {
        'vector search': self.cmd_vector_search,
        'vector search filter': self.cmd_vector_search_filter,
        'show file content': self.cmd_casapi_show_file_content,
        'vector stores info files': self.cmd_casapi_vector_stores_info,
        'llm query file': self.cmd_casapi_query_file,
        'help': self.display_help,
        'vector stores list': self.cmd_vector_stores_list,
        'vector stores select': self.cmd_vector_stores_select,
        'vector stores info users': self.cmd_vector_stores_info,
        'llm query ask': self.cmd_query_ask,
        'llm setup': self.cmd_llm_setup,
        'query history': self.cmd_query_history,
        'session info': self.cmd_session_info,
        'session export': self.cmd_session_export,
        'session clear': self.cmd_session_clear,
        'config show': self.cmd_config_show,
        'metrics': self.cmd_metrics,
        'health': self.cmd_health,
        'clear': self.cmd_clear,
        'exit': lambda: setattr(self, 'running', False),
        'quit': lambda: setattr(self, 'running', False)
    }

    handler = command_map.get(command)
    if handler:
        handler()
    else:
        matches = [cmd for cmd in command_map.keys() if cmd.startswith(command)]
        if len(matches) == 1:
            command_map[matches[0]]()
        elif len(matches) > 1:
            self.console.print(f"[yellow]Ambiguous command. Did you mean:[/]")
            for match in matches:
                self.console.print(f"  - {match}")
        else:
            self.console.print(f"[red]Unknown command: {command}[/]")
            self.console.print("[dim]Type 'help' for available commands[/]")
