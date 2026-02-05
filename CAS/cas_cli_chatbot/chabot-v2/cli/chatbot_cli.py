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
        'help': 'Show available commands',
        'users list': 'List all users (OCP and IDP)',
        'users ocp': 'List OpenShift users only',
        'users idp': 'List IDP/Keycloak users only',
        'users select': 'Select/switch user',
        'users sync': 'Sync users from both sources',
        'domains list': 'List all available domains',
        'domains select': 'Select a domain to work with',
        'domains info': 'Show detailed domain information',
        'domains assign': 'Assign user(s) to current domain',
        'domains unassign': 'Remove user(s) from domain',
        'domains users': 'Show users assigned to domain',
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
        self.current_user = None
        self.current_domain = None
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
- Multi-user management (OCP & IDP)
- Domain administration
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
            'Domains': [k for k in self.COMMANDS.keys() if k.startswith('domains')],
            'Queries': [k for k in self.COMMANDS.keys() if k.startswith('query')],
            'Session': [k for k in self.COMMANDS.keys() if k.startswith('session')],
            'System': [k for k in self.COMMANDS.keys() if
                       k in ['help', 'config show', 'config reload', 'metrics', 'health', 'clear', 'exit', 'quit']]
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
        status.add_row("Current Domain:", self.current_domain or "[dim]None[/]")
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
            idp_users = self.services['user'].list_keycloak_users()

            progress.remove_task(task)

        table = Table(title="All Users", show_header=True)
        table.add_column("Source", style="cyan")
        table.add_column("Username", style="green")
        table.add_column("Count", style="yellow")

        table.add_row("OpenShift", ", ".join(ocp_users[:5]) + ("..." if len(ocp_users) > 5 else ""),
                      str(len(ocp_users)))
        table.add_row("IDP/Keycloak", ", ".join(idp_users[:5]) + ("..." if len(idp_users) > 5 else ""),
                      str(len(idp_users)))

        self.console.print(table)

    def cmd_users_ocp(self):
        """List OpenShift users"""
        users = self.services['user'].list_oc_users()
        self._display_user_list(users, "OpenShift Users")

    def cmd_users_idp(self):
        """List IDP users"""
        users = self.services['user'].list_keycloak_users()
        self._display_user_list(users, "IDP/Keycloak Users")

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
        idp_users = self.services['user'].list_keycloak_users()
        all_users = list(set(ocp_users + idp_users))

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

    def cmd_users_sync(self):
        """Sync users from all sources"""
        with Progress(SpinnerColumn(), TextColumn("[progress.description]{task.description}"),
                      console=self.console) as progress:
            progress.add_task("Syncing users...", total=None)
            # Clear cache to force refresh
            self.services['cache'].clear_pattern("users_*")
            ocp_users = self.services['user'].list_oc_users()
            idp_users = self.services['user'].list_keycloak_users()

        self.console.print(f"[green]✓ Synced {len(ocp_users)} OCP and {len(idp_users)} IDP users[/]")

    # ==================== DOMAIN COMMANDS ====================

    def cmd_domains_list(self):
        """List all domains"""
        domains = self.services['domain'].list_domains()

        if not domains:
            self.console.print("[yellow]No domains found[/]")
            return

        tree = Tree(f"[bold cyan]Available Domains[/] ({len(domains)} total)")
        for domain in domains:
            style = "green bold" if domain == self.current_domain else "white"
            tree.add(f"[{style}]{domain}[/]")

        self.console.print(tree)

    def cmd_domains_select(self):
        """Select a domain"""
        domains = self.services['domain'].list_domains()

        if not domains:
            self.console.print("[red]No domains available[/]")
            return

        completer = FuzzyCompleter(WordCompleter(domains, ignore_case=True))
        selected = self.session.prompt(
            "Select domain (type to search): ",
            completer=completer
        ).strip()

        if selected in domains:
            self.current_domain = selected
            self.console.print(f"[bold green]✓ Selected domain: {self.current_domain}[/]")
            self.logger.info(f"Domain selected: {self.current_domain}")
        else:
            self.console.print(f"[red]✗ Domain not found: {selected}[/]")

    def cmd_domains_info(self):
        """Show detailed domain information with assigned users"""
        if not self.current_domain:
            self.console.print("[red]✗ No domain selected. Use 'domains select' first.[/]")
            return

        self.console.print(f"\n[bold cyan]Domain Information: {self.current_domain}[/]\n")

        # Get domain details
        domain_info = self.services['domain'].get_domain_details(self.current_domain)

        if domain_info:
            info_table = Table(title=f"Domain: {self.current_domain}", show_header=False)
            info_table.add_column("Property", style="cyan")
            info_table.add_column("Value", style="white")

            info_table.add_row("Domain Name", domain_info.get('name', 'N/A'))
            info_table.add_row("Namespace", domain_info.get('namespace', 'N/A'))
            info_table.add_row("Created", domain_info.get('created', 'N/A'))

            assigned = domain_info.get('assigned_users', {})
            ocp_users = assigned.get('ocp', [])
            keycloak_users = assigned.get('keycloak', [])
            total = assigned.get('total', 0)

            info_table.add_row("Total Assigned Users", str(total))
            info_table.add_row("OCP Users", ", ".join(ocp_users) if ocp_users else "[dim]None[/]")
            info_table.add_row("Keycloak Users", ", ".join(keycloak_users) if keycloak_users else "[dim]None[/]")

            self.console.print(info_table)
        else:
            self.console.print(f"[yellow]Could not fetch details for domain: {self.current_domain}[/]")

    def cmd_domains_users(self):
        """Show users assigned to current domain"""
        if not self.current_domain:
            self.console.print("[red]✗ No domain selected[/]")
            return

        users = self.services['domain'].get_assigned_users(self.current_domain)
        ocp_users, keycloak_users = self.services['domain'].get_assigned_users_detailed(self.current_domain)

        if users:
            table = Table(title=f"Users Assigned to {self.current_domain}", show_header=True)
            table.add_column("Username", style="green")
            table.add_column("Type", style="cyan")

            for user in ocp_users:
                table.add_row(user, "OCP")
            for user in keycloak_users:
                table.add_row(user, "Keycloak")

            self.console.print(table)
        else:
            self.console.print(f"[yellow]No users assigned to domain: {self.current_domain}[/]")

    def cmd_domains_assign(self):
        """Assign user(s) to domain"""
        if not self.current_domain:
            self.console.print("[red]✗ No domain selected[/]")
            return

        # Show current assignments
        current_users = self.services['domain'].get_assigned_users(self.current_domain)
        if current_users:
            self.console.print(f"\n[dim]Currently assigned users: {', '.join(current_users)}[/]\n")
        else:
            self.console.print(f"\n[dim]No users currently assigned to this domain[/]\n")

        # Get available users
        ocp_users = self.services['user'].list_oc_users()
        keycloak_users = self.services['user'].list_keycloak_users()
        all_users = list(set(ocp_users + keycloak_users))

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
            self.console.print(f"[yellow]User '{selected}' is already assigned to this domain[/]")
            return

        # Determine user type
        user_type = "ocp" if selected in ocp_users else "keycloak"

        # Confirm assignment
        if confirm(f"Assign '{selected}' ({user_type}) to domain '{self.current_domain}'?"):
            user_types = {selected: user_type}
            success = self.services['domain'].assign_users_to_domain(
                self.current_domain,
                [selected],
                user_types=user_types
            )

            if success:
                self.console.print(f"[green]✓ Assigned {selected} to {self.current_domain}[/]")

                # Update session
                self.session_manager.add_assignment(self.current_domain, selected)

                # Show updated list
                updated_users = self.services['domain'].get_assigned_users(self.current_domain, use_cache=False)
                self.console.print(f"[dim]Domain now has {len(updated_users)} user(s)[/]")
            else:
                self.console.print(f"[red]✗ Failed to assign user[/]")
        else:
            self.console.print("[yellow]Cancelled[/]")

    # ==================== QUERY COMMANDS ====================

    def cmd_query_ask(self):
        """Ask a query using LLM with user-specific authentication"""

        # Ensure user is selected
        if not self.current_user:
            self.console.print("[red]✗ No user selected. Select a user first with 'users select'[/]")
            return

        # Determine user type
        ocp_users = self.services['user'].list_oc_users()
        keycloak_users = self.services['user'].list_keycloak_users()
        user_type = "ocp" if self.current_user in ocp_users else "keycloak"

        self.console.print(f"[cyan]Authenticating user: {self.current_user} ({user_type})[/]")

        # Get password for user authentication
        from getpass import getpass
        password = getpass(f"Enter password for {user_type} user '{self.current_user}': ")

        # Authenticate the user
        if user_type == "ocp":
            success, token = self.services['user_auth'].authenticate_ocp_user(self.current_user, password)
        else:
            success, token = self.services['user_auth'].authenticate_keycloak_user(self.current_user, password)

        if not success:
            self.console.print(f"[red]✗ Authentication failed for user: {self.current_user}[/]")
            self.logger.error(f"Failed to authenticate {self.current_user}")
            return

        self.console.print(f"[green]✓ User authenticated: {self.current_user}[/]")

        # Get query from user
        query = self.session.prompt(
            f"[{self.current_user}@{self.current_domain or 'global'}] Enter your query: "
        ).strip()

        if not query:
            self.console.print("[yellow]Query cannot be empty[/]")
            return

        # Verify user is added to domain
        if self.current_domain:
            domain_users = self.services['domain'].get_assigned_users(self.current_domain)

            if self.current_user not in domain_users:
                self.console.print(
                    f"[red]✗ User '{self.current_user}' is not assigned to domain '{self.current_domain}'[/]")
                self.console.print("[dim]Please add this user to the domain first with 'domains assign'[/]")
                self.logger.warning(f"User {self.current_user} not in domain {self.current_domain}")
                return

        self.console.print("\n[bold cyan]Processing query with user-specific authentication...[/]\n")

        # Execute query with user-specific token
        try:
            self.logger.info(f"Executing query for user {self.current_user} ({user_type})")

            # Get search results with user-specific token
            search_result = self.services['query'].query_with_user_token(
                table=self.current_domain or self.config.get("default_table", "gt20"),
                username=self.current_user,
                user_type=user_type,
                password=password  # Pass password for potential re-authentication
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
                domain=self.current_domain,
                user_type=user_type,
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
        table.add_column("Domain", style="yellow", width=15)
        table.add_column("Query", style="white")

        for idx, q in enumerate(queries[-20:], 1):  # Show last 20
            table.add_row(
                str(idx),
                q.get('timestamp', 'N/A'),
                q.get('user', 'N/A'),
                q.get('domain', 'N/A'),
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

        if self.current_domain:
            parts.append(f"[yellow]{self.current_domain}[/]")

        prefix = "@".join(parts) if parts else "cas"
        return f"{prefix}> "

    def execute_command(self, command: str):
        """Execute a CLI command"""
        # Map commands to methods
        command_map = {
            'help': self.display_help,
            'users list': self.cmd_users_list,
            'users ocp': self.cmd_users_ocp,
            'users idp': self.cmd_users_idp,
            'users select': self.cmd_users_select,
            'users sync': self.cmd_users_sync,
            'domains list': self.cmd_domains_list,
            'domains select': self.cmd_domains_select,
            'domains info': self.cmd_domains_info,
            'domains assign': self.cmd_domains_assign,
            'domains users': self.cmd_domains_users,
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