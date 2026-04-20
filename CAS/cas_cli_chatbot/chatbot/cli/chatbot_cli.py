"""
Enhanced Chatbot CLI with advanced enterprise features
"""

from openai import NoneType
import json
from datetime import datetime
from typing import Optional, Dict, List
from prompt_toolkit import PromptSession
from prompt_toolkit.completion import WordCompleter, FuzzyCompleter, Completer, Completion
from prompt_toolkit.shortcuts import confirm
from prompt_toolkit.validation import Validator, ValidationError
from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.progress import Progress, SpinnerColumn, TextColumn
from rich.tree import Tree
from rich.markdown import Markdown
from rich.prompt import Confirm
import re


class CommandValidator(Validator):
    """Validate user commands"""

    def __init__(self, valid_commands: List[str]):
        self.valid_commands = valid_commands

    def validate(self, document):
        text = document.text.strip()
        if text and not any(
                text.startswith(cmd) for cmd in self.valid_commands):
            raise ValidationError(
                message="Invalid command. Type 'help' for available commands.",
                cursor_position=len(text))


class ChatbotCLI:
    """Enhanced Interactive CLI for CAS Chatbot"""

    # Display constants
    UNKNOWN_FILENAME = "unknown"
    UNKNOWN_FILE_ID = "unknown"
    NO_TEXT_PLACEHOLDER = "No text"

    COMMANDS = {
        'vector search': 'Retrieve relevant chunks without LLM processing',
        'vector search filter': 'Retrieve specific chunks using filters',
        'show file content': 'Show the content of a specified file',
        'vector stores info': 'Show vector store info from CAS API',
        'query file': 'Query a specific file from a vector store',
        'help': 'Show available commands',
        'vector stores list': 'List all available vector stores',
        'vector stores select': 'Select a vector store to work with',
        'vector stores info': 'Show detailed vector store information',
        'query ask': 'Ask a query using LLM',
        'query history': 'Show query history',
        'query export': 'Export query results',
        'session view': 'View current session info',
        'session history': 'Show session history',
        'session stats': 'Show session statistics',
        'session export': 'Export session to file',
        'session clear': 'Clear session history',
        'config show': 'Show current configuration',
        'config reload': 'Reload configuration',
        'metrics': 'Show application metrics',
        'health': 'Run health checks',
        'clear': 'Clear screen',
        'exit': 'Exit application',
        'quit': 'Exit application'
    }

    def __init__(self,
                 services: Dict,
                 config: Dict,
                 logger,
                 console: Console,
                 error_handler,
                 session_manager,
                 config_manager=None):
        self.services = services
        self.config = config
        self.logger = logger
        self.console = Console(markup=True, force_terminal=True)
        self.error_handler = error_handler
        self.session_manager = session_manager
        self.config_manager = config_manager

        # CLI state
        self.current_user = config.get("oc_username")
        self.user_type = "ocp"
        self.current_namespace = config.get("cas_namespace")
        self.current_vector_store = config.get("default_vector_store")
        self.running = True

        # Setup prompt session
        self.session = PromptSession()
        self.command_completer = FuzzyCompleter(
            WordCompleter(list(self.COMMANDS.keys()), ignore_case=True))

    def display_welcome(self):
        """Display welcome message"""
        welcome_text = """
            # Welcome to CAS Chatbot CLI

            **Features:**
            - User authentication
            - Vector store administration
            - LLM-powered queries
            - Session persistence
            - Health monitoring

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
        table.add_column("Command", style="cyan", width=20)
        table.add_column("Description", style="white")

        # Group commands by category
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
                k for k in self.COMMANDS.keys() if k.startswith('query')
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
        status.add_row(
            "Session Assignments:",
            str(len(self.session_manager.get_history().get('assignments', []))))

        self.console.print(Panel(status, title="Status", border_style="blue"))

    # ==================== VECTOR STORE COMMANDS ====================

    def cmd_vector_stores_list(self):
        """List vector stores accessible to user and all available vector stores in namespace"""
        # Get user-specific vector stores
        accessible_stores = self._accessible_vector_stores()

        all_vector_stores = self.services['vector store'].list_vector_stores(
            self.current_namespace)

        if not all_vector_stores:
            self.console.print(
                "[yellow]No vector stores/domains found in OpenShift[/]")
            return

        # If store is selected but not accessible, show a message
        assignment_info_msg = False

        tree = Tree(
            f"[bold cyan]Vector Stores[/] ({len(all_vector_stores)} total, "
            f"{len(accessible_stores)} accessible)")
        for vector_store in all_vector_stores:
            # Build the display string with indicators
            if (vector_store == self.current_vector_store
               ) and vector_store in accessible_stores:
                # Current selection - green with arrow
                icon = "➤"
                style = "bold green"
                access_badge = "[green]✓[/]"
            elif vector_store == self.current_vector_store:
                # Current selection but not accessible
                icon = "➤"
                style = "bold white"
                access_badge = "[red]✗[/]"
                assignment_info_msg = True  # Mark that user is in a store they can't access
            elif vector_store in accessible_stores:
                # Accessible but not selected
                icon = "○"
                style = "white"
                access_badge = "[green]✓[/]"
            else:
                # Not accessible
                icon = "○"
                style = "dim"
                access_badge = "[red]✗[/]"

            tree.add(f"{icon} [{style}]{vector_store}[/] {access_badge}")

        self.console.print(tree)

        # If user is in a vector store they can't access, show a message
        if assignment_info_msg:
            self._user_in_vector_store()

    def cmd_vector_stores_select(self, vector_store_name: str | None = None):
        """Select a vector store
        
        Args:
            vector_store_name: Optional vector store name. If provided,
                              selects directly. Otherwise, prompts interactively.
        """
        all_vector_stores = self.services['vector store'].list_vector_stores(
            self.current_namespace)

        if not all_vector_stores:
            self.console.print("[red]No vector stores/domains available[/]")
            return

        accessible_stores = self._accessible_vector_stores()

        # Show available stores
        self.cmd_vector_stores_list()

        # Get selection (parameter or interactive)
        if vector_store_name:
            selected = vector_store_name.strip()
        else:
            completer = FuzzyCompleter(
                WordCompleter(all_vector_stores, ignore_case=True))
            selected = self.session.prompt(
                "Select vector store/domain (type to search): ",
                completer=completer).strip()

        # Validate and set selection
        self._set_vector_store(selected, all_vector_stores, accessible_stores)

    def _set_vector_store(
        self,
        selected: str,
        all_vector_stores: list,
        accessible_vector_stores: list,
    ) -> None:
        """Helper to validate and set vector store selection
        
        Args:
            selected: The vector store name to set
            accessible_vector_stores: List of accessible vector stores
            store_list: List of vector stores for display purposes
            show_available: Whether to show available stores on error
        """
        if selected in all_vector_stores:
            if selected in accessible_vector_stores:
                self.current_vector_store = selected
                self.console.print(
                    f"[bold green]✓ Selected vector store: {self.current_vector_store}[/]"
                )
                self.logger.info(
                    f"Vector store selected: {self.current_vector_store}")

                # Save to config file if config_manager is available
                if self.config_manager:
                    try:
                        self.config_manager.update_default_vector_store(
                            selected)
                    except Exception as e:
                        self.logger.warning(
                            f"Failed to update config file: {e}")

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

        # Get vector store details
        vector_store_info = self.services[
            'vector store'].get_vector_store_details(self.current_vector_store)

        if vector_store_info:
            info_table = Table(
                title=f"Vector Store: {self.current_vector_store}",
                show_header=False)
            info_table.add_column("Property", style="cyan")
            info_table.add_column("Value", style="white")

            info_table.add_row("Vector Store Name",
                               vector_store_info.get('name', 'N/A'))
            info_table.add_row("Namespace",
                               vector_store_info.get('namespace', 'N/A'))
            info_table.add_row("Created",
                               vector_store_info.get('created', 'N/A'))

            assigned = vector_store_info.get('assigned_users', {})
            ocp_users = assigned.get('ocp', [])
            total = assigned.get('total', 0)

            info_table.add_row("Total Assigned Users", str(total))
            info_table.add_row(
                "OCP Users",
                ", ".join(ocp_users) if ocp_users else "[dim]None[/]")

            self.console.print(info_table)
        else:
            self.console.print(
                f"[yellow]Could not fetch details for vector store/domain: {self.current_vector_store}[/]"
            )

    # ==================== QUERY COMMANDS ====================

    def cmd_query_ask(self) -> None:
        """Ask a query using LLM with user-specific authentication"""

        # Ensure user is selected and added to vector store
        if not self._user_in_vector_store():
            return

        # Check token validity
        if not self._check_token():
            return

        # Get query from user
        query = self._get_query_input()
        if not query:
            return

        self.console.print(
            "\n[bold cyan]Processing query with user-specific authentication...[/]\n"
        )

        # Execute query with user-specific token
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
        table.add_column("#", style="dim", width=4)
        table.add_column("Time", style="cyan", width=20)
        table.add_column("User", style="green", width=15)
        table.add_column("Vector Store", style="yellow", width=15)
        table.add_column("Query", style="white")

        for idx, q in enumerate(queries[-20:], 1):  # Show last 20
            table.add_row(
                str(idx), q.get('timestamp', 'N/A'), q.get('user', 'N/A'),
                q.get('vector store', 'N/A'),
                q.get('query', 'N/A')[:50] + "..."
                if len(q.get('query', '')) > 50 else q.get('query', 'N/A'))

        self.console.print(table)

    # ==================== SESSION COMMANDS ====================

    def cmd_session_view(self):
        """View current session info"""
        self.display_status()

    def cmd_session_history(self):
        """Show full session history"""
        history = self.session_manager.get_history()

        self.console.print(
            f"\n[bold]Session started:[/] {history.get('session_start', 'Unknown')}"
        )
        self.console.print(
            f"[bold]Total queries:[/] {len(history.get('queries', []))}")
        self.console.print(
            f"[bold]Total assignments:[/] {len(history.get('assignments', []))}"
        )
        self.console.print(
            f"[bold]Total unassignments:[/] {len(history.get('unassignments', []))}"
        )
        self.console.print(
            f"[bold]Total file lookups:[/] {len(history.get('file_lookups', []))}"
        )

    def cmd_session_stats(self):
        """Show session statistics"""
        stats = self.session_manager.get_statistics()

        stats_table = Table(title="Session Statistics", show_header=True)
        stats_table.add_column("Metric", style="cyan")
        stats_table.add_column("Value", style="green")

        for key, value in stats.items():
            stats_table.add_row(key.replace('_', ' ').title(), str(value))

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

    # ==================== SYSTEM COMMANDS ====================

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
        from utils.health_check import HealthChecker

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

    # ==================== CASAPI COMMANDS ====================
    def _accessible_vector_stores(self) -> list[str]:
        """List vector_stores available to user"""
        # Check token validity
        if not self._check_token():
            return []

        vector_stores = self.services['query'].list_vector_stores()

        if not vector_stores:
            self.console.print(
                f"[yellow]No accessible vector stores/domains found for {self.current_namespace}[/]"
            )
            return []

        return vector_stores

    def cmd_casapi_vector_search(self) -> None:
        """Execute vector search with user-specific authentication.
        
        Performs authenticated vector store search by:
        1. Validating user assignment to vector store
        2. Authenticating user credentials
        3. Executing search query with user token
        4. Displaying results and recording in session history
        
        Requires:
            - User must be selected (self.current_user)
            - User must be assigned to target vector store
            - Valid authentication credentials
            
        Side Effects:
            - Prompts user for query input
            - Displays search results to console
            - Records query in session history
            - Logs operation status
            
        Raises:
            KeyError: If required configuration is missing
            ValueError: If query parameters are invalid
            ConnectionError: If API connection fails
        """
        # Ensure user is selected and added to vector store
        if not self._user_in_vector_store():
            return

        # Check token validity
        if not self._check_token():
            return

        # Determine vector store to use
        vector_store = self._get_active_vector_store()
        if not vector_store:
            return

        # Get query from user
        query = self._get_input(
            f"[{self.current_user}@{self.current_vector_store or 'global'}] Enter your query: "
        )
        self.console.print(
            "\n[bold cyan]Processing query with user-specific authentication...[/]\n"
        )

        # Execute query with user-specific token
        try:
            search_result = self._execute_vector_search(
                query=query, vector_store=vector_store)

            if search_result:
                # Check if there are any chunks in the result
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

    def cmd_casapi_vector_search_filter(self):
        """Retrieve raw chunks with user-specific authentication and filters"""

        # Ensure user is selected and added to vector store
        if not self._user_in_vector_store():
            return

        # Check token validity
        if not self._check_token():
            return

        # Get query from user
        query = self._get_input(
            f"[{self.current_user}@{self.current_vector_store or 'global'}] Enter your query: "
        )
        self.console.print(
            "\n[bold cyan]Processing query with user-specific authentication...[/]\n"
        )

        # Get filters from user
        self.console.print("Enter your filter (key, type, value) \n")
        key = self.session.prompt(" - key: ").strip()
        operator = self.session.prompt(
            " - type (eq, ne, gt, gte, lt, lte, in, nin, contains): ").strip()
        raw_value = self.session.prompt(" - value: ").strip()

        # Handle list values for in / nin
        if operator in {"in", "nin"}:
            value = [v.strip() for v in raw_value.split(",")]
        else:
            value = raw_value

        # Build dictionary for query filter
        query_filter = {"key": key, "type": operator, "value": value}

        # Execute query with user-specific token
        try:
            self.logger.info(
                f"Executing filtered query for user {self.current_user} ({self.user_type})"
            )

            # Get search results
            search_result = self.services['query'].query_with_filters(
                user_query=query,
                filters=query_filter,
                vector_store=self.current_vector_store,
            )

            # Check query result and display chunks
            if self._retrieved_result_valid(search_result, "Query"):
                self._display_search_chunks(search_result)

                # Save to session
                self.session_manager.add_query(
                    user=self.current_user,
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
                e,
                f"Unexpected filtered query error for user {self.current_user}")

    def cmd_casapi_show_file_content(self):
        """Returns all the content (text chunks) for a specific vector-store and file by their IDs"""

        # Validate preconditions
        if not self._user_in_vector_store():
            return

        # Check token validity
        if not self._check_token():
            return

        # Get user input
        identifiers = self._get_file_identifiers()
        if not identifiers:
            return

        vector_store_id, file_id = identifiers

        # Retrieve and display content
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

        # Validate preconditions
        if not self._user_in_vector_store():
            return

        # Check token validity
        if not self._check_token():
            return

        # Get user input
        identifiers = self._get_file_identifiers()
        if not identifiers:
            return

        vector_store_id, file_id = identifiers

        # Get query from user
        query = self._get_input(
            f"[{self.current_user}@{self.current_vector_store or 'global'}] Enter your query: "
        )
        self.console.print(
            "\n[bold cyan]Processing query with user-specific authentication...[/]\n"
        )

        # Retrieve file content and process with LLM
        try:
            file_content = self._retrieve_file_content(vector_store_id, file_id)
            if not file_content:
                return

            # Call LLM with search results
            self.console.print("[bold cyan]Getting AI response...[/]\n")
            self.services['llm'].call_llm(file_content, query)

            # Save to session
            self.session_manager.add_query(
                user=self.current_user,
                query=query,
                vector_store=self.current_vector_store,
                user_type=self.user_type,
                authenticated=True)

            self.logger.info(
                f"Query completed successfully for {self.current_user}")

        except Exception as e:
            self.error_handler.handle_error(
                e,
                f"Query execution of specified file for user {self.current_user}"
            )

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

        # Get vector store details
        vector_store_info = self.services['query'].get_vector_store_info(
            self.current_vector_store, self.current_user)

        if vector_store_info:
            info_table = Table(
                title=f"Vector Store: {self.current_vector_store}",
                show_header=False)
            info_table.add_column("Property", style="cyan")
            info_table.add_column("Value", style="white")

            info_table.add_row("Vector Store Name",
                               vector_store_info.get('name', 'N/A'))
            info_table.add_row("ID", vector_store_info.get('id', 'N/A'))
            info_table.add_row("Created",
                               vector_store_info.get('created_at', 'N/A'))
            info_table.add_row("Bytes", vector_store_info.get('bytes', 'N/A'))
            info_table.add_row("File Count",
                               vector_store_info.get('file_counts', 'N/A'))
            info_table.add_row("Object", vector_store_info.get('object', 'N/A'))

            self.console.print(info_table)
        else:
            self.console.print(
                f"[yellow]Could not fetch details for vector store/domain: {self.current_vector_store}[/]"
            )

    # ==================== HELPER FUNCTIONS ====================

    def _get_query_input(self) -> Optional[str]:
        """Get and validate query from user.
        
        Returns:
            Query string or None if empty
        """
        query = self.session.prompt(
            f"[{self.current_user}@{self.current_vector_store or 'global'}] Enter your query: "
        ).strip()

        if not query:
            self.console.print("[yellow]Query cannot be empty[/]")
            return None
        return query

    def _execute_query_with_llm(self, query: str) -> bool:
        """Execute query and process with LLM.
        
        Args:
            query: User query string
            
        Returns:
            True if successful, False otherwise
        """
        vector_store = self._get_active_vector_store()

        search_result = self._execute_vector_search(query, vector_store)
        if not search_result:
            return False

        # Check if there are any chunks in the result
        data = search_result.get("data", [])
        if not data:
            self.console.print(
                "[yellow]No chunks found matching your query.[/]\n"
                "[dim]Try rephrasing your query or using different keywords.[/]"
            )
            return False

        self.console.print("[bold cyan]Getting AI response...[/]\n")
        self.services['llm'].call_llm(search_result, query)

        self._record_successful_query(query)
        return True

    def _get_active_vector_store(self) -> Optional[str]:
        """Get the active vector store, prioritizing current selection over default.
        
        Returns:
            Vector store name or None if not configured
        """
        vector_store = self.current_vector_store or self.config.get(
            "default_vector_store", "")
        if not vector_store:
            self.console.print(
                "[red]✗ No vector store selected or configured[/]")
            return None
        return vector_store

    def _record_successful_query(self, query: str) -> None:
        """Record successful query execution in session history.
        
        Args:
            query: The executed query string
        """
        self.session_manager.add_query(user=self.current_user,
                                       query=query,
                                       vector_store=self.current_vector_store,
                                       user_type=self.user_type,
                                       authenticated=True)
        self.logger.info(
            f"Query completed successfully for {self.current_user}")

    def _get_file_identifiers(self) -> Optional[tuple]:
        """Get vector store ID and file ID from user input.
        
        Returns:
            Tuple of (vector_store_id, file_id) or None if cancelled
        """
        vector_store_id = self._get_input(
            f"[{self.current_user}@{self.current_vector_store or 'global'}] "
            "Enter the vector store ID (might be same as vector store name): ")

        file_id = self._get_input(
            f"[{self.current_user}@{self.current_vector_store or 'global'}] "
            "Enter the file ID: ")

        return vector_store_id, file_id

    def _retrieve_file_content(self, vector_store_id: str,
                               file_id: str) -> Optional[Dict]:
        """Retrieve file content with user authentication.
        
        Args:
            vector_store_id: Vector store identifier
            file_id: File identifier
            
        Returns:
            File content dict or None if retrieval failed
        """
        self.logger.info(
            f"Retrieving file content for {self.current_user} ({self.user_type})"
        )

        file_content = self.services['query'].get_file_content(
            vector_store_id=vector_store_id,
            file_id=file_id,
            username=self.current_user,
            user_type=self.user_type,
        )

        if not self._retrieved_result_valid(file_content,
                                            "File content retrieval"):
            return None

        return file_content

    def _display_file_content(self, file_content: Dict) -> None:
        """Display file content with formatting.
        
        Args:
            file_content: Dictionary containing filename, file_id, and content chunks
        """
        self.console.print("[bold cyan]Retrieving file content...[/]\n")

        filename = file_content.get("filename", self.UNKNOWN_FILENAME)
        file_id = file_content.get("file_id", self.UNKNOWN_FILE_ID)

        self.console.print(
            f"[bold]\\[filename: {filename}]\n\\[file ID: {file_id}]\n[/bold]")

        for chunk in file_content.get("content", []):
            for text in chunk.get("text", "").splitlines():
                cleaned_text = text.strip()
                if cleaned_text:  # Skip empty lines
                    self.console.print(cleaned_text)

    def _record_file_lookup(self, vector_store_id: str, file_id: str) -> None:
        """Record file lookup in session history.
        
        Args:
            vector_store_id: Vector store identifier
            file_id: File identifier
        """
        self.session_manager.add_file_lookup(user=self.current_user,
                                             vector_store_id=vector_store_id,
                                             file_id=file_id,
                                             user_type=self.user_type,
                                             authenticated=True)

        self.logger.info(
            f"File content retrieved successfully for {self.current_user}")

    def _clean_chunk_text(self, text: str) -> str:
        """Normalize whitespace in chunk text"""
        return re.sub(r"\s+", " ", text).strip()

    def _display_search_chunks(self, search_result: Dict) -> None:
        """Display search result chunks with formatting"""
        self.console.print("[bold cyan]Retrieving text chunks...[/]\n")

        for chunk_idx, item in enumerate(search_result.get("data", []),
                                         start=1):
            filename = item.get("filename", self.UNKNOWN_FILENAME)
            file_id = item.get("file_id", self.UNKNOWN_FILE_ID)

            for chunk in item.get("content", []):
                text = chunk.get("text", self.NO_TEXT_PLACEHOLDER)
                cleaned_text = self._clean_chunk_text(text)

                self.console.print(
                    f"[bold]Chunk {chunk_idx}:[/bold] \\[filename: {filename}]\n"
                    f"\\[file ID: {file_id}]\n{cleaned_text}\n")

    def _execute_vector_search(self, query: str,
                               vector_store: str | None) -> Optional[Dict]:
        """Execute vector store search with user authentication"""
        self.logger.info(
            f"Executing query for user {self.current_user} ({self.user_type})")

        search_result = self.services['query'].query_vector_store(
            user_query=query,
            vector_store=vector_store,
        )

        if not self._retrieved_result_valid(search_result, "Query"):
            return None

        return search_result

    def _check_token(self) -> bool:
        if not self.services["auth"].has_valid_token():
            self.console.print(
                "[red]✗ Authentication failed. Please check your credentials.[/]"
            )
            return False
        return True

    def _user_in_vector_store(self) -> bool:
        # Ensure user is selected
        if not self.current_user:
            self.console.print(
                "[red]✗ No user selected. Select a user first with 'users select'[/]"
            )
            return False

        if self.current_vector_store:
            if self.current_vector_store in self._accessible_vector_stores():
                return True
            else:
                self.console.print(
                    f"[red]✗ User '{self.current_user}' is not assigned to vector store/domain '{self.current_vector_store}'[/]"
                )
                self.console.print(
                    "[dim]Please add this user to the vector store in the Fusion UI[/]"
                )
                self.logger.warning(
                    f"User {self.current_user} not in vector store {self.current_vector_store}"
                )
                return False
        else:
            self.console.print(
                f"[red]✗ A vector store/domain has not been selected[/]")
            self.console.print(
                "[dim]Please select a vector store first with 'vector_stores select'[/]"
            )
            self.logger.warning(f"A vector store/domain has not been selected")
            return False

    def _retrieved_result_valid(self, result, content_type: str) -> bool:
        # Check retrieval result
        if isinstance(result, dict) and not result.get('success', True):
            error = result.get('error', 'Unknown error')
            details = result.get('details', '')

            self.console.print(f"[red]✗ {content_type} failed: {error}[/]")

            # Check for token-related errors
            if 'bearer token' in error.lower() or 'token' in error.lower():
                self.console.print(
                    "[bold yellow]⚠ No valid bearer token available.[/]")
                self.console.print(
                    "[yellow]You cannot use commands until your token is valid.[/]"
                )
                self.console.print(
                    "[yellow]Please restart the application and authenticate.[/]"
                )
            elif result.get('status_code') == 401:
                self.console.print(
                    "[red]Invalid or expired user token. Please re-authenticate.[/]"
                )
            elif result.get('status_code') == 403:
                self.console.print(f"[red]{details}[/]")

            self.logger.error(
                f"{content_type} failed for {self.current_user}: {error}")
            return False

        self.console.print(
            f"[green]✓ {content_type} succeeded for user: {self.current_user}[/]\n"
        )
        self.logger.info(f"{content_type} succeeded for {self.current_user}")

        return True

    def _get_input(self, prompt):
        while True:
            user_input = self.session.prompt(prompt).strip()
            if not user_input:
                self.console.print("[yellow]Input cannot be empty[/] ")
            else:
                return user_input

    # ==================== MAIN LOOP ====================

    def _prompt_vector_store_selection(self) -> None:
        """
        Prompt user to select a vector store at startup.
        
        """
        vector_stores_list = self.services["vector store"].list_vector_stores(
            self.current_namespace)
        if not vector_stores_list:
            self.console.print(
                "[red]No vector stores found. Please create one.[/]")
            return

        # Check if there's a default vector store in config
        default_vector_store = self.config.get("default_vector_store")

        # Check for placeholder
        placeholders = ["<default-vector-store-name>", ""]
        if default_vector_store in placeholders:
            default_vector_store = None

        if default_vector_store:
            self.console.print(
                f"\n[bold cyan]Default vector store '{default_vector_store}' detected in config. Validating...[/]\n"
            )

            # Check if default is valid and accessible
            self.cmd_vector_stores_select(default_vector_store)
            if not self.current_vector_store:
                self.console.print(
                    f"[red]Default vector store '{default_vector_store}' is not valid or accessible.[/]\n"
                )
                # Print list of available vector stores
                self.cmd_vector_stores_list()
                self.cmd_vector_stores_select(
                )  # Prompt user to select vector store
            else:
                use_default = Confirm.ask("[yellow]Use this vector store?[/]",
                                          default=True)

                if use_default:
                    self.current_vector_store = default_vector_store
                    self.console.print(
                        f"[bold green]✓ Using vector store: {default_vector_store}[/]"
                    )
                else:  # User declined default, continue to show list
                    self.cmd_vector_stores_list()
                    self.cmd_vector_stores_select(
                    )  # Prompt user to select vector store
        else:
            # No default configured, show list and prompt for selection
            self.console.print(
                "\n[bold cyan]No default vector store configured. Please select one:[/]\n"
            )
            self.cmd_vector_stores_list()  # Show list of vector stores
            self.cmd_vector_stores_select(
            )  # Prompt user to select vector store

    def _has_valid_llm_config(self) -> bool:
        """
        Check if the current configuration has a valid LLM provider configured.
        
        Returns:
            True if at least one LLM provider is properly configured
        """
        if not self.config_manager:
            return False

        return self.config_manager.has_llm_configured(self.config)

    def _prompt_llm_setup(self) -> None:
        """
        Prompt user to configure LLM provider.
        Only prompts if no valid LLM configuration exists.
        """

        # Check if LLM is already configured
        if self._has_valid_llm_config():
            use_default = Confirm.ask("[yellow]Use default LLM from config?[/]", default=True)

            if use_default:
                self.console.print(
                    "\n[bold green]✓ Using default LLM configuration from config.yaml[/]")
                return

        self.console.print()  # Add spacing

        # Ask if user wants to set up LLM
        setup_llm = Confirm.ask(
            "[yellow]Some commands use an LLM to enhance responses. Would you like to configure an LLM provider now?[/]",
            default=False)

        if not setup_llm:
            self.console.print(
                "[dim]You can configure LLM later by editing the config.yaml file.[/]"
            )
            return

        # Use ConfigManager to prompt for LLM setup
        if self.config_manager:
            llm_config = self.config_manager.prompt_for_llm_setup()

            if llm_config:
                # Update the config file
                self.config_manager.update_llm_config(llm_config)

                # Update the in-memory config
                self.config.update(llm_config)

                self.console.print(
                    "\n[bold green]✓ LLM configuration complete![/]")
                self.console.print(
                    "[dim]You can now use commands like 'query ask' with LLM enhancement.[/]\n"
                )
        else:
            self.console.print(
                "[yellow]⚠ Config manager not available. Please configure LLM manually in config.yaml[/]"
            )

    def run(self) -> int:
        """Main CLI loop"""
        self.display_welcome()

        # Prompt for vector store selection at startup
        try:
            self._prompt_vector_store_selection()
        except KeyboardInterrupt:
            self.console.print("\n[dim]Skipped vector store selection.[/]")
        except Exception as e:
            self.logger.warning(f"Error during vector store selection: {e}")
            self.console.print(
                "[yellow]⚠ Could not complete vector store selection. You can select one later using 'vector-stores select'.[/]"
            )

        # Prompt for LLM configuration at startup
        try:
            self._prompt_llm_setup()
        except KeyboardInterrupt:
            self.console.print("\n[dim]Skipped LLM setup.[/]")
        except Exception as e:
            self.logger.warning(f"Error during LLM setup: {e}")
            self.console.print(
                "[yellow]⚠ Error during LLM setup. You can configure it later in config.yaml[/]"
            )

        try:
            while self.running:
                try:
                    # Show prompt with current context
                    prompt_text = self._build_prompt()
                    command = self.session.prompt(
                        prompt_text,
                        completer=self.command_completer).strip().lower()

                    if not command:
                        continue

                    # Execute command
                    self.execute_command(command)

                except KeyboardInterrupt:
                    if confirm("\nExit application?"):
                        self.running = False
                    else:
                        continue

                except EOFError:
                    self.running = False

                except Exception as e:
                    self.error_handler.handle_error(e, "Command execution")

            return 0

        finally:
            self.session_manager.save()
            self.logger.info("CLI session ended")

    def _build_prompt(self) -> str:
        """Build dynamic prompt with context"""
        parts = []

        if self.current_user:
            parts.append(f"[cyan]{self.current_user}[/]")

        if self.current_vector_store:
            parts.append(f"[yellow]{self.current_vector_store}[/]")

        prefix = "@".join(parts) if parts else "cas"
        return f"{prefix}> "

    def execute_command(self, command: str):
        """Execute a CLI command"""
        # Check if command has parameters (e.g., "vector_stores select my-store")
        if command.startswith('vector stores select'):
            parts = command.split(maxsplit=2)
            if len(parts) == 4:  # Has parameter
                vector_store_name = parts[3]
                self.cmd_vector_stores_select(vector_store_name)
            else:  # No parameter, use interactive mode
                self.cmd_vector_stores_select()
            return

        # Map commands to methods
        command_map = {
            'vector search': self.cmd_casapi_vector_search,
            'vector search filter': self.cmd_casapi_vector_search_filter,
            'show file content': self.cmd_casapi_show_file_content,
            'vector stores info': self.cmd_casapi_vector_stores_info,
            'query file': self.cmd_casapi_query_file,
            'help': self.display_help,
            'vector stores list': self.cmd_vector_stores_list,
            'vector stores select': self.cmd_vector_stores_select,
            'vector_ tores info': self.cmd_vector_stores_info,
            'query ask': self.cmd_query_ask,
            'query history': self.cmd_query_history,
            'session view': self.cmd_session_view,
            'session history': self.cmd_session_history,
            'session stats': self.cmd_session_stats,
            'session export': self.cmd_session_export,
            'session clear': self.cmd_session_clear,
            'config show': self.cmd_config_show,
            'metrics': self.cmd_metrics,
            'health': self.cmd_health,
            'clear': self.cmd_clear,
            'exit': lambda: setattr(self, 'running', False),
            'quit': lambda: setattr(self, 'running', False)
        }

        # Execute command
        handler = command_map.get(command)
        if handler:
            handler()
        else:
            # Try partial match
            matches = [
                cmd for cmd in command_map.keys() if cmd.startswith(command)
            ]
            if len(matches) == 1:
                command_map[matches[0]]()
            elif len(matches) > 1:
                self.console.print(
                    f"[yellow]Ambiguous command. Did you mean:[/]")
                for match in matches:
                    self.console.print(f"  - {match}")
            else:
                self.console.print(f"[red]Unknown command: {command}[/]")
                self.console.print("[dim]Type 'help' for available commands[/]")
