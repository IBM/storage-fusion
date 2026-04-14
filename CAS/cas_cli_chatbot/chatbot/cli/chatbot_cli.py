"""
Enhanced Chatbot CLI with advanced enterprise features
"""

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
import re



class CommandValidator(Validator):
    """Validate user commands"""

    def __init__(self, valid_commands: List[str]):
        self.valid_commands = valid_commands

    def validate(self, document):
        text = document.text.strip()
        if text and not any(text.startswith(cmd) for cmd in self.valid_commands):
            raise ValidationError(
                message="Invalid command. Type 'help' for available commands.",
                cursor_position=len(text)
            )


class ChatbotCLI:
    """Enhanced Interactive CLI for CAS Chatbot"""

    COMMANDS = {
        'casapi list_vector_stores': 'Show available vector stores by users',
        'casapi vector_search': 'Retrieve relevant chunks without LLM processing',
        'casapi vector_search filter': 'Retrieve specific chunks using filters',
        'casapi show_file_content': 'Show the content of a specified file',
        'casapi vector_stores info': 'Show vector store info from CAS API',
        'casapi query file': 'Query a specific file from a vector store',
        'help': 'Show available commands',
        'users list': 'List all users (OCP and IDP)',
        'users ocp': 'List OpenShift users only',
        'users idp': 'List IDP users only',
        'users select': 'Select/switch user',
        'users sync': 'Sync users from both sources',
        'vector_stores list': 'List all available vector stores',
        'vector_stores select': 'Select a vector store to work with',
        'vector_stores info': 'Show detailed vector store information',
        'vector_stores assign': 'Assign user(s) to current vector store',
        'vector_stores unassign': 'Remove user(s) from vector store',
        'vector_stores users': 'Show users assigned to vector store',
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

    def __init__(self, services: Dict, config: Dict, logger, console: Console,
                 error_handler, session_manager):
        self.services = services
        self.config = config
        self.logger = logger
        self.console = Console(markup=True, force_terminal=True)
        self.error_handler = error_handler
        self.session_manager = session_manager

        # CLI state
        self.current_user = config.get("oc_username")
        self.user_type = "ocp"
        self.current_vector_store = config.get("default_vector_store")
        self.running = True

        # Setup prompt session
        self.session = PromptSession()
        self.command_completer = FuzzyCompleter(
            WordCompleter(list(self.COMMANDS.keys()), ignore_case=True)
        )

    def display_welcome(self):
        """Display welcome message"""
        welcome_text = """
            # Welcome to CAS Chatbot CLI

            **Features:**
            - Multi-user management (OCP)
            - Vector store administration
            - LLM-powered queries
            - Session persistence
            - Health monitoring

            Type `help` to see all available commands.
        """
        self.console.print(Panel(Markdown(welcome_text), title="Welcome", border_style="cyan"))

    def display_help(self, command: Optional[str] = None):
        """Display help information"""
        if command and command in self.COMMANDS:
            self.console.print(f"\n[bold cyan]{command}[/]: {self.COMMANDS[command]}")
            return

        table = Table(title="Available Commands", show_header=True, header_style="bold magenta")
        table.add_column("Command", style="cyan", width=20)
        table.add_column("Description", style="white")

        # Group commands by category
        categories = {
            'Users': [k for k in self.COMMANDS.keys() if k.startswith('users')],
            'Vector stores': [k for k in self.COMMANDS.keys() if k.startswith('vector_stores')],
            'Queries': [k for k in self.COMMANDS.keys() if k.startswith('query')],
            'Session': [k for k in self.COMMANDS.keys() if k.startswith('session')],
            'System': [k for k in self.COMMANDS.keys() if
                       k in ['help', 'config show', 'config reload', 'metrics', 'health', 'clear', 'exit', 'quit']],
            'CAS API': [k for k in self.COMMANDS.keys() if k.startswith('casapi')]
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
        status.add_row("Current Vector Store:", self.current_vector_store or "[dim]None[/]")
        status.add_row("Session Queries:", str(len(self.session_manager.get_history().get('queries', []))))
        status.add_row("Session Assignments:", str(len(self.session_manager.get_history().get('assignments', []))))

        self.console.print(Panel(status, title="Status", border_style="blue"))

    # ==================== USER COMMANDS ====================

    def cmd_users_list(self):
        """List all users from both OCP and IDP"""
        with Progress(SpinnerColumn(), TextColumn("[progress.description]{task.description}"),
                      console=self.console) as progress:
            task = progress.add_task("Fetching users...", total=None)

            ocp_users = self.services['user'].list_oc_users()
            # idp_users = self.services['user'].list_keycloak_users()

            progress.remove_task(task)

        table = Table(title="All Users", show_header=True)
        table.add_column("Source", style="cyan")
        table.add_column("Username", style="green")
        table.add_column("Count", style="yellow")

        table.add_row("OpenShift", ", ".join(ocp_users[:5]) + ("..." if len(ocp_users) > 5 else ""),
                      str(len(ocp_users)))
        # table.add_row("IDP/Keycloak", ", ".join(idp_users[:5]) + ("..." if len(idp_users) > 5 else ""),
        #              str(len(idp_users)))

        self.console.print(table)

    def cmd_users_ocp(self):
        """List OpenShift users"""
        users = self.services['user'].list_oc_users()
        self._display_user_list(users, "OpenShift Users")

    # def cmd_users_idp(self):
    #     """List IDP users"""
    #     users = self.services['user'].list_keycloak_users()
    #     self._display_user_list(users, "IDP/Keycloak Users")

    def _display_user_list(self, users: List[str], title: str):
        """Helper to display user list"""
        if not users:
            self.console.print(f"[yellow]No users found[/]")
            return

        tree = Tree(f"[bold cyan]{title}[/] ({len(users)} total)")
        for user in users:
            style = "green" if user == self.current_user else "white"
            tree.add(f"[{style}]{user}[/]")

        self.console.print(tree)

    def cmd_users_select(self):
        """Select a user interactively"""
        ocp_users = self.services['user'].list_oc_users()
        # idp_users = self.services['user'].list_keycloak_users()
        all_users = list(set(ocp_users))

        if not all_users:
            self.console.print("[red]No users available[/]")
            return

        completer = FuzzyCompleter(WordCompleter(all_users, ignore_case=True))
        selected = self.session.prompt(
            "Select user (type to search): ",
            completer=completer
        ).strip()

        if selected in all_users:
            self.current_user = selected
            self.console.print(f"[bold green]✓ Switched to user: {self.current_user}[/]")
            self.logger.info(f"User switched to: {self.current_user}")
        else:
            self.console.print(f"[red]✗ User not found: {selected}[/]")

    # def cmd_users_sync(self):
    #     """Sync users from all sources"""
    #     with Progress(SpinnerColumn(), TextColumn("[progress.description]{task.description}"),
    #                   console=self.console) as progress:
    #         progress.add_task("Syncing users...", total=None)
    #         # Clear cache to force refresh
    #         self.services['cache'].clear_pattern("users_*")
    #         ocp_users = self.services['user'].list_oc_users()
    #         idp_users = self.services['user'].list_keycloak_users()

    #     self.console.print(f"[green]✓ Synced {len(ocp_users)} OCP and {len(idp_users)} IDP users[/]")

    # ==================== VECTOR STORE COMMANDS ====================

    def cmd_vector_stores_list(self):
        """List all vector_stores"""
        vector_stores = self.services['vector store'].list_vector_stores()

        if not vector_stores:
            self.console.print("[yellow]No vector stores/domains found[/]")
            return

        tree = Tree(f"[bold cyan]Available Vector Stores[/] ({len(vector_stores)} total)")
        for vector_store in vector_stores:
            style = "green bold" if vector_store == self.current_vector_store else "white"
            tree.add(f"[{style}]{vector_store}[/]")

        self.console.print(tree)

    def cmd_vector_stores_select(self):
        """Select a vector store"""
        vector_stores = self.services['vector store'].list_vector_stores()

        if not vector_stores:
            self.console.print("[red]No vector stores/domains available[/]")
            return

        completer = FuzzyCompleter(WordCompleter(vector_stores, ignore_case=True))
        selected = self.session.prompt(
            "Select vector store/domain (type to search): ",
            completer=completer
        ).strip()

        if selected in vector_stores:
            self.current_vector_store = selected
            self.console.print(f"[bold green]✓ Selected vector store: {self.current_vector_store}[/]")
            self.logger.info(f"Vector store selected: {self.current_vector_store}")
        else:
            self.console.print(f"[red]✗ Vector store not found: {selected}[/]")

    def cmd_vector_stores_info(self):
        """Show detailed vector store information with assigned users"""
        if not self.current_vector_store:
            self.console.print("[red]✗ No vector stores/domains selected. Use 'vector_stores select' first.[/]")
            return

        self.console.print(f"\n[bold cyan]Vector Store Information: {self.current_vector_store}[/]\n")

        # Get vector store details
        vector_store_info = self.services['vector store'].get_vector_store_details(self.current_vector_store)

        if vector_store_info:
            info_table = Table(title=f"Vector Store: {self.current_vector_store}", show_header=False)
            info_table.add_column("Property", style="cyan")
            info_table.add_column("Value", style="white")

            info_table.add_row("Vector Store Name", vector_store_info.get('name', 'N/A'))
            info_table.add_row("Namespace", vector_store_info.get('namespace', 'N/A'))
            info_table.add_row("Created", vector_store_info.get('created', 'N/A'))

            assigned = vector_store_info.get('assigned_users', {})
            ocp_users = assigned.get('ocp', [])
            # keycloak_users = assigned.get('keycloak', [])
            total = assigned.get('total', 0)

            info_table.add_row("Total Assigned Users", str(total))
            info_table.add_row("OCP Users", ", ".join(ocp_users) if ocp_users else "[dim]None[/]")
            # info_table.add_row("Keycloak Users", ", ".join(keycloak_users) if keycloak_users else "[dim]None[/]")

            self.console.print(info_table)
        else:
            self.console.print(f"[yellow]Could not fetch details for vector store/domain: {self.current_vector_store}[/]")

    def cmd_vector_stores_users(self):
        """Show users assigned to current vector store"""
        if not self.current_vector_store:
            self.console.print("[red]✗ No vector store/domain selected[/]")
            return

        users = self.services['vector store'].get_assigned_users(self.current_vector_store)
        ocp_users, keycloak_users = self.services['vector store'].get_assigned_users_detailed(self.current_vector_store)

        if users:
            table = Table(title=f"Users Assigned to {self.current_vector_store}", show_header=True)
            table.add_column("Username", style="green")
            table.add_column("Type", style="cyan")

            for user in ocp_users:
                table.add_row(user, "OCP")
            # for user in keycloak_users:
            #     table.add_row(user, "Keycloak")

            self.console.print(table)
        else:
            self.console.print(f"[yellow]No users assigned to vector store/domain: {self.current_vector_store}[/]")

    def cmd_vector_stores_assign(self):
        """Assign user(s) to vector store"""
        if not self.current_vector_store:
            self.console.print("[red]✗ No vector store/domain selected[/]")
            return

        # Show current assignments
        current_users = self.services['vector store'].get_assigned_users(self.current_vector_store)
        if current_users:
            self.console.print(f"\n[dim]Currently assigned users: {', '.join(current_users)}[/]\n")
        else:
            self.console.print(f"\n[dim]No users currently assigned to this vector store[/]\n")

        # Get available users
        ocp_users = self.services['user'].list_oc_users()
        # keycloak_users = self.services['user'].list_keycloak_users()
        all_users = list(set(ocp_users))

        if not all_users:
            self.console.print("[red]✗ No users available[/]")
            return

        completer = FuzzyCompleter(WordCompleter(all_users, ignore_case=True))
        selected = self.session.prompt(
            "Enter username to assign: ",
            completer=completer
        ).strip()

        if not selected:
            self.console.print("[yellow]Cancelled[/]")
            return

        if selected not in all_users:
            self.console.print(f"[red]✗ User not found: {selected}[/]")
            return

        # Check if already assigned
        if selected in current_users:
            self.console.print(f"[yellow]User '{selected}' is already assigned to this vector store[/]")
            return

        # Determine user type
        self.user_type = "ocp" if selected in ocp_users else "idp"

        # Confirm assignment
        if confirm(f"Assign '{selected}' ({self.user_type}) to vector store '{self.current_vector_store}'?"):
            user_types = {selected: self.user_type}
            success = self.services['vector store'].assign_users_to_vector_store(
                self.current_vector_store,
                [selected],
                user_types=user_types
            )

            if success:
                self.console.print(f"[green]✓ Assigned {selected} to {self.current_vector_store}[/]")

                # Update session
                self.session_manager.add_assignment(self.current_vector_store, selected)

                # Show updated list
                updated_users = self.services['vector store'].get_assigned_users(self.current_vector_store, use_cache=False)
                self.console.print(f"[dim]Vector store now has {len(updated_users)} user(s)[/]")
            else:
                self.console.print(f"[red]✗ Failed to assign user[/]")
        else:
            self.console.print("[yellow]Cancelled[/]")

    def cmd_vector_stores_unassign(self):
        """Unassign user(s) to vector store"""
        if not self.current_vector_store:
            self.console.print("[red]✗ No vector store/domain selected[/]")
            return

        # Show current assignments
        current_users = self.services['vector store'].get_assigned_users(self.current_vector_store)
        if current_users:
            self.console.print(f"\n[dim]Currently assigned users: {', '.join(current_users)}[/]\n")
        else:
            self.console.print(f"\n[dim]No users currently assigned to this vector store[/]\n")
            return

        # Get available users
        ocp_users = self.services['user'].list_oc_users()
        # keycloak_users = self.services['user'].list_keycloak_users()
        all_users = list(set(ocp_users))

        if not all_users:
            self.console.print("[red]✗ No users available[/]")
            return

        completer = FuzzyCompleter(WordCompleter(all_users, ignore_case=True))
        selected = self.session.prompt(
            "Enter username to unassign: ",
            completer=completer
        ).strip()

        if not selected:
            self.console.print("[yellow]Cancelled[/]")
            return

        if selected not in all_users:
            self.console.print(f"[red]✗ User not found: {selected}[/]")
            return

        # Determine user type
        self.user_type = "ocp" if selected in ocp_users else "idp"

        # Confirm assignment
        if confirm(f"Unassign '{selected}' ({self.user_type}) from vector store '{self.current_vector_store}'?"):
            user_types = {selected: self.user_type}
            success = self.services['vector store'].unassign_users_from_vector_store(
                self.current_vector_store,
                [selected],
            )

            if success:
                self.console.print(f"[green]✓ Unassigned {selected} to {self.current_vector_store}[/]")

                # Update session
                self.session_manager.add_unassignment(self.current_vector_store, selected)

                # Show updated list
                updated_users = self.services['vector store'].get_assigned_users(self.current_vector_store, use_cache=False)
                self.console.print(f"[dim]Vector store now has {len(updated_users)} user(s)[/]")
            else:
                self.console.print(f"[red]✗ Failed to unassign user[/]")
        else:
            self.console.print("[yellow]Cancelled[/]")

    # ==================== QUERY COMMANDS ====================

    def cmd_query_ask(self):
        """Ask a query using LLM with user-specific authentication"""

        # Ensure user is selected and added to vector store
        if not self._user_in_vector_store():
            return

        # Authenticate user
        if not self._user_auth():
            return

        # Get query from user
        query = self.session.prompt(
            f"[{self.current_user}@{self.current_vector_store or 'global'}] Enter your query: "
        ).strip()

        if not query:
            self.console.print("[yellow]Query cannot be empty[/]")
            return

        # Verify user is added to vector store
        if self.current_vector_store:
            vector_store_users = self.services['vector store'].get_assigned_users(self.current_vector_store)

            if self.current_user not in vector_store_users:
                self.console.print(
                    f"[red]✗ User '{self.current_user}' is not assigned to vector store/domain '{self.current_vector_store}'[/]")
                self.console.print("[dim]Please add this user to the vector store first with 'vector_stores assign'[/]")
                self.logger.warning(f"User {self.current_user} not in vector store {self.current_vector_store}")
                return

        self.console.print("\n[bold cyan]Processing query with user-specific authentication...[/]\n")

        # Execute query with user-specific token
        try:
            self.logger.info(f"Executing query for user {self.current_user} ({self.user_type})")

            # Get search results with user-specific token
            search_result = self.services['query'].query_vector_store(
                user_query=query,
                vector_store=self.current_vector_store or self.config.get("default_vector_store", "gt20"),
                username=self.current_user,
                user_type=self.user_type,
            )

            # Check query result
            if isinstance(search_result, dict) and not search_result.get('success', True):
                error = search_result.get('error', 'Unknown error')
                details = search_result.get('details', '')

                self.console.print(f"[red]✗ Query failed: {error}[/]")

                if search_result.get('status_code') == 401:
                    self.console.print("[red]Invalid or expired user token. Please re-authenticate.[/]")
                elif search_result.get('status_code') == 403:
                    self.console.print(f"[red]{details}[/]")

                self.logger.error(f"Query failed for {self.current_user}: {error}")
                return

            self.console.print(f"[green]✓ Query executed successfully for user: {self.current_user}[/]\n")

            # Call LLM with search results
            self.console.print("[bold cyan]Getting AI response...[/]\n")
            self.services['llm'].call_llm(search_result, query)

            # Save to session
            self.session_manager.add_query(
                user=self.current_user,
                query=query,
                vector_store=self.current_vector_store,
                user_type=self.user_type,
                authenticated=True
            )

            self.logger.info(f"Query completed successfully for {self.current_user}")

        except Exception as e:
            self.error_handler.handle_error(e, f"Query execution for user {self.current_user}")

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
                str(idx),
                q.get('timestamp', 'N/A'),
                q.get('user', 'N/A'),
                q.get('vector store', 'N/A'),
                q.get('query', 'N/A')[:50] + "..." if len(q.get('query', '')) > 50 else q.get('query', 'N/A')
            )

        self.console.print(table)


    # ==================== SESSION COMMANDS ====================

    def cmd_session_view(self):
        """View current session info"""
        self.display_status()

    def cmd_session_history(self):
        """Show full session history"""
        history = self.session_manager.get_history()

        self.console.print(f"\n[bold]Session started:[/] {history.get('session_start', 'Unknown')}")
        self.console.print(f"[bold]Total queries:[/] {len(history.get('queries', []))}")
        self.console.print(f"[bold]Total assignments:[/] {len(history.get('assignments', []))}")
        self.console.print(f"[bold]Total unassignments:[/] {len(history.get('unassignments', []))}")
        self.console.print(f"[bold]Total file lookups:[/] {len(history.get('file_lookups', []))}")

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
            "Enter filename (default: session_export.json): "
        ).strip() or "session_export.json"

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
        self.console.print(Panel(
            json.dumps(sanitized, indent=2),
            title="Current Configuration",
            border_style="cyan"
        ))

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
            status = "[green]✓ Healthy[/]" if result['healthy'] else "[red]✗ Unhealthy[/]"
            table.add_row(service, status, result['message'])

        self.console.print(table)

    def cmd_clear(self):
        """Clear screen"""
        self.console.clear()
        self.display_welcome()

    # ==================== CASAPI COMMANDS ====================
    def cmd_casapi_list_vector_stores(self):
        """List vector_stores available to user"""

        # Ensure user is selected
        if not self.current_user:
            self.console.print("[red]✗ No user selected. Select a user first with 'users select'[/]")
            return

        # Authenticate user
        if not self._user_auth():
            return

        vector_stores = self.services['query'].list_vector_stores(
            username=self.current_user,
            user_type=self.user_type,
        )

        if not vector_stores:
            self.console.print("[yellow]No vector stores/domains found[/]")
            return

        tree = Tree(f"[bold cyan]Available Vector Stores for User '{self.current_user}'[/] ({len(vector_stores)} total)")
        for vector_store in vector_stores:
            style = "green bold" if vector_store == self.current_vector_store else "white"
            tree.add(f"[{style}]{vector_store}[/]")

        self.console.print(tree)

    def cmd_casapi_vector_search(self):
        """Retrieve raw chunks with user-specific authentication"""

        # Ensure user is selected and added to vector store
        if not self._user_in_vector_store():
            return

        # Authenticate user
        if not self._user_auth():
            return

        # Get query from user
        query = self._get_input(f"[{self.current_user}@{self.current_vector_store or 'global'}] Enter your query: ")
        self.console.print("\n[bold cyan]Processing query with user-specific authentication...[/]\n")
            

        # Execute query with user-specific token
        try:
            self.logger.info(f"Executing query for user {self.current_user} ({self.user_type})")

            # Get search results with user-specific token
            search_result = self.services['query'].query_vector_store(
                user_query = query,
                vector_store=self.current_vector_store or self.config.get("default_vector_store", "gt20"),
                username=self.current_user,
                user_type=self.user_type,
            )

            # Check query result
            if self._retrieved_result_valid(search_result, "Query"):
                # Print chunks of text
                self.console.print("[bold cyan]Retrieving text chunks...[/]\n")
                for chunk_idx, item in enumerate(search_result.get("data", []), start=1):
                    filename = item.get("filename", "unknown")
                    file_id = item.get("file_id", "unknown")
                    for chunk in item.get("content", []):
                        text = chunk.get("text", "No text")
                        cleaned_text = re.sub(r"\s+", " ", text).strip()

                        self.console.print(
                            f"[bold]Chunk {chunk_idx}:[/bold] \\[filename: {filename}]\n\\[file ID: {file_id}]\n{cleaned_text}\n")
            else:
                return

            # Save to session
            self.session_manager.add_query(
                user=self.current_user,
                query=query,
                vector_store=self.current_vector_store,
                user_type=self.user_type,
                authenticated=True
            )

            self.logger.info(f"Query completed successfully for {self.current_user}")

        except Exception as e:
            self.error_handler.handle_error(e, f"Query execution for user {self.current_user}")

    def cmd_casapi_vector_search_filter(self):
        """Retrieve raw chunks with user-specific authentication and filters"""

        # Ensure user is selected and added to vector store
        if not self._user_in_vector_store():
            return
        
            # Authenticate user
        if not self._user_auth():
            return

        ## Get query from user
        query = self._get_input(f"[{self.current_user}@{self.current_vector_store or 'global'}] Enter your query: ")
        self.console.print("\n[bold cyan]Processing query with user-specific authentication...[/]\n")

        # Get filters from user
        self.console.print("Enter your filter (key, type, value) \n")
        key = self.session.prompt(" - key: ").strip()
        operator = self.session.prompt(" - type (eq, ne, gt, gte, lt, lte, in, nin, contains): ").strip()
        raw_value = self.session.prompt(" - value: ").strip()

        # Handle list values for in / nin
        if operator in {"in", "nin"}:
            value = [v.strip() for v in raw_value.split(",")]
        else:
            value = raw_value

        # Build dictionary for query filter
        query_filter = {
            "key": key,
            "type": operator,
            "value": value
        }

        # Execute query with user-specific token
        try:
            self.logger.info(f"Executing query for user {self.current_user} ({self.user_type})")

            # Get search results with user-specific token
            search_result = self.services['query'].query_with_filters(
                user_query = query,
                vector_store=self.current_vector_store,
                filters= query_filter,
                username=self.current_user,
                user_type=self.user_type,
            )

            # Check query result
            if self._retrieved_result_valid(search_result, "Query"):
                # Print chunks of text
                self.console.print("[bold cyan]Retrieving text chunks...[/]\n")
                for chunk_idx, item in enumerate(search_result.get("data", []), start=1):
                    filename = item.get("filename", "unknown")
                    file_id = item.get("file_id", "unknown")
                    for chunk in item.get("content", []):
                        text = chunk.get("text", "No text")
                        cleaned_text = text.replace("\r\n", "\n").strip()

                        self.console.print(
                            f"[bold]Chunk {chunk_idx}:[/bold]\n\\[filename: {filename}]\n\\[file ID: {file_id}]\n{cleaned_text}\n")
            else: 
                return
            

            # Save to session
            self.session_manager.add_query(
                user=self.current_user,
                query=query,
                vector_store=self.current_vector_store,
                user_type=self.user_type,
                authenticated=True
            )

            self.logger.info(f"Query completed successfully for {self.current_user}")

        except Exception as e:
            self.error_handler.handle_error(e, f"Query execution for user {self.current_user}")

    def cmd_casapi_show_file_content(self):
        """Returns all the content (text chunks) for a specific vector-store and file by their IDs"""

        # Ensure user is selected and added to vector store
        if not self._user_in_vector_store():
            return

        # Authenticate user
        if not self._user_auth():
            return

        # Get vector store id from user
        vector_store_id = self._get_input(f"[{self.current_user}@{self.current_vector_store or 'global'}] Enter the vector store ID (might be same as vector store name): ")
        
        # Get file id from user
        file_id = self._get_input(f"[{self.current_user}@{self.current_vector_store or 'global'}] Enter the file ID: ")

        # Retrieve file content with user-specific token
        try:
            self.logger.info(f"Retrieving file content for {self.current_user} ({self.user_type})")

            # Get file content with user-specific token
            file_content = self.services['query'].get_file_content(
                vector_store_id=vector_store_id,
                file_id=file_id,
                username=self.current_user,
                user_type=self.user_type,
            )

            # Check file content retrieval result
            if self._retrieved_result_valid(file_content, "File content retrieval"):
                self.console.print("[bold cyan]Retrieving file content...[/]\n")
                filename = file_content.get("filename", "unknown")
                file_id = file_content.get("file_id", "unknown")
                self.console.print(f"[bold]\\[filename: {filename}]\n\\[file ID: {file_id}]\n[/bold]")
                
                for chunk in file_content.get("content", "unknown"):
                    for text in chunk["text"].splitlines():
                        cleaned_text = text.strip()
                        self.console.print(cleaned_text)
            else: 
                return
            
            # Save to session
            self.session_manager.add_file_lookup(
                user=self.current_user,
                vector_store_id=vector_store_id,
                file_id=file_id,
                user_type=self.user_type,
                authenticated=True
            )

            self.logger.info(f"File content retrieved successfully for {self.current_user}")

        except Exception as e:
            self.error_handler.handle_error(e, f"File content retrieval for user {self.current_user}")

    def cmd_casapi_query_file(self):
        # Ensure user is selected and added to vector store
        if not self._user_in_vector_store():
            return
        
        # Authenticate user
        if not self._user_auth():
            return

        # Get vector store id from user
        vector_store_id = self._get_input(f"[{self.current_user}@{self.current_vector_store or 'global'}] Enter the vector store ID (might be same as vector store name): ")
        
        # Get file id from user
        file_id = self._get_input(f"[{self.current_user}@{self.current_vector_store or 'global'}] Enter the file ID: ")

        # Get query from user
        query = self._get_input(f"[{self.current_user}@{self.current_vector_store or 'global'}] Enter your query: ")
        self.console.print("\n[bold cyan]Processing query with user-specific authentication...[/]\n")


        # Retrieve file content with user-specific token
        try:
            self.logger.info(f"Retrieving file content for {self.current_user} ({self.user_type})")

            # Get file content with user-specific token
            file_content = self.services['query'].get_file_content(
                vector_store_id=vector_store_id,
                file_id=file_id,
                username=self.current_user,
                user_type=self.user_type,
            )

            # Check file content retrieval result
            if self._retrieved_result_valid(file_content, "File content retrieval"):
                # Call LLM with search results
                self.console.print("[bold cyan]Getting AI response...[/]\n")
                self.services['llm'].call_llm(file_content, query)
            else: 
                return

            # Save to session
            self.session_manager.add_query(
                user=self.current_user,
                query=query,
                vector_store=self.current_vector_store,
                user_type=self.user_type,
                authenticated=True
            )

            self.logger.info(f"Query completed successfully for {self.current_user}")

        except Exception as e:
            self.error_handler.handle_error(e, f"Query execution of specified file for user {self.current_user}")

    def cmd_casapi_vector_stores_info(self):
        """Show detailed vector store information with assigned users"""
        if not self.current_vector_store:
            self.console.print("[red]✗ No vector stores/domains selected. Use 'vector_stores select' first.[/]")
            return

        self.console.print(f"\n[bold cyan]Vector Store Information: {self.current_vector_store}[/]\n")

        # Get vector store details
        vector_store_info = self.services['query'].get_vector_store_info(self.current_vector_store, self.current_user)

        if vector_store_info:
            info_table = Table(title=f"Vector Store: {self.current_vector_store}", show_header=False)
            info_table.add_column("Property", style="cyan")
            info_table.add_column("Value", style="white")

            info_table.add_row("Vector Store Name", vector_store_info.get('name', 'N/A'))
            info_table.add_row("ID", vector_store_info.get('id', 'N/A'))
            info_table.add_row("Created", vector_store_info.get('created_at', 'N/A'))
            info_table.add_row("Bytes", vector_store_info.get('bytes', 'N/A'))
            info_table.add_row("File Count", vector_store_info.get('file_counts', 'N/A'))
            info_table.add_row("Object", vector_store_info.get('object', 'N/A'))

            self.console.print(info_table)
        else:
            self.console.print(f"[yellow]Could not fetch details for vector store/domain: {self.current_vector_store}[/]")

    # ==================== HELPER FUNCTIONS ====================
    def _user_auth(self) -> bool:
        # Determine user type
        ocp_users = self.services['user'].list_oc_users()
        # keycloak_users = self.services['user'].list_keycloak_users()
        self.user_type = "ocp" if self.current_user in ocp_users else "idp"

        self.console.print(
            f"[cyan]Authenticating user: {self.current_user} ({self.user_type})[/]")

        # Get password for user authentication
        password = self.config.get("oc_password")
        if password == "":
            from getpass import getpass
            password = getpass(
                f"Enter password for {self.user_type} user '{self.current_user}': ")

        # Authenticate the user
        if self.user_type == "ocp":
            success, token = self.services['user_auth'].authenticate_ocp_user(self.current_user, 
                                                                            password)
        else:
            success = False
        # else:
        #     success, token = self.services[
        #         'user_auth'].authenticate_keycloak_user(self.current_user, password)
        if not success:
            self.console.print(f"[red]✗ Authentication failed for user: {self.current_user}[/]")
            self.logger.error(f"Failed to authenticate {self.current_user}")
            return False

        self.console.print(f"[green]✓ User authenticated: {self.current_user}[/]")
        
        return True
    
    def _user_in_vector_store(self) -> bool:
        # Ensure user is selected
        if not self.current_user:
            self.console.print("[red]✗ No user selected. Select a user first with 'users select'[/]")
            return False
        
        # Verify user is added to vector store
        if self.current_vector_store:
            vector_store_users = self.services['vector store'].get_assigned_users(self.current_vector_store)

            if self.current_user not in vector_store_users:
                self.console.print(
                    f"[red]✗ User '{self.current_user}' is not assigned to vector store/domain '{self.current_vector_store}'[/]")
                self.console.print("[dim]Please add this user to the vector store first with 'vector_stores assign'[/]")
                self.logger.warning(f"User {self.current_user} not in vector store {self.current_vector_store}")
                return False
        else:
            self.console.print(
                f"[red]✗ A vector store/domain has not been selected[/]")
            self.console.print("[dim]Please select a vector store first with 'vector_stores select'[/]")
            self.logger.warning(f"A vector store/domain has not been selected")
            return False
        
        return True
    
    def _retrieved_result_valid(self, result, content_type: str) -> bool:
        # Check retrieval result
        if isinstance(result, dict) and not result.get('success', True):
            error = result.get('error', 'Unknown error')
            details = result.get('details', '')

            self.console.print(f"[red]✗ {content_type} failed: {error}[/]")

            if result.get('status_code') == 401:
                self.console.print("[red]Invalid or expired user token. Please re-authenticate.[/]")
            elif result.get('status_code') == 403:
                self.console.print(f"[red]{details}[/]")

            self.logger.error(f"{content_type} failed for {self.current_user}: {error}")
            return False
        
        self.console.print(f"[green]✓ {content_type} succeeded for user: {self.current_user}[/]\n")
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

    def run(self) -> int:
        """Main CLI loop"""
        self.display_welcome()

        try:
            while self.running:
                try:
                    # Show prompt with current context
                    prompt_text = self._build_prompt()
                    command = self.session.prompt(
                        prompt_text,
                        completer=self.command_completer
                    ).strip().lower()

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
        # Map commands to methods
        command_map = {
            'casapi list_vector_stores': self.cmd_casapi_list_vector_stores,
            'casapi vector_search': self.cmd_casapi_vector_search,
            'casapi vector_search filter': self.cmd_casapi_vector_search_filter,
            'casapi show_file_content': self.cmd_casapi_show_file_content,
            'casapi vector_stores info': self.cmd_casapi_vector_stores_info,
            'casapi query file': self.cmd_casapi_query_file,
            'help': self.display_help,
            'users list': self.cmd_users_list,
            'users ocp': self.cmd_users_ocp,
            'users select': self.cmd_users_select,
            'vector_stores list': self.cmd_vector_stores_list,
            'vector_stores select': self.cmd_vector_stores_select,
            'vector_stores info': self.cmd_vector_stores_info,
            'vector_stores assign': self.cmd_vector_stores_assign,
            'vector_stores unassign': self.cmd_vector_stores_unassign,
            'vector_stores users': self.cmd_vector_stores_users,
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