"""
Enhanced Chatbot CLI with advanced enterprise features.
"""

from typing import Any, Dict, List, Optional

from prompt_toolkit import PromptSession
from prompt_toolkit.completion import FuzzyCompleter, WordCompleter
from prompt_toolkit.shortcuts import confirm
from prompt_toolkit.validation import ValidationError, Validator
from rich.console import Console
from rich.prompt import Confirm

from chatbot.cli import command_handlers as handlers
from chatbot.cli import display_methods as displays
from chatbot.utils.validators import TokenValidator

# HTTP Status Code Constants
HTTP_STATUS_UNAUTHORIZED = 401
HTTP_STATUS_FORBIDDEN = 403


class _SessionProxy:
    """Proxy prompt session to allow method replacement in tests."""

    def __init__(self, session: Any):
        object.__setattr__(self, "_session", session)

    def __getattr__(self, name: str) -> Any:
        return getattr(self._session, name)

    def __setattr__(self, name: str, value: Any) -> None:
        setattr(self._session, name, value)


class CommandValidator(Validator):
    """Validate user commands."""

    def __init__(self, valid_commands: List[str]):
        self.valid_commands = valid_commands

    def validate(self, document):
        text = document.text.strip()
        if text and not any(
                text.startswith(cmd) for cmd in self.valid_commands):
            raise ValidationError(
                message="Invalid command. Type 'help' for available commands.",
                cursor_position=len(text),
            )


class ChatbotCLI:
    """Interactive CLI orchestrator for CAS Chatbot."""

    UNKNOWN_FILENAME = "unknown"
    UNKNOWN_FILE_ID = "unknown"
    NO_TEXT_PLACEHOLDER = "No text"

    COMMANDS = {
        "vector search":
            "Retrieve relevant chunks without LLM processing",
        "vector search filter":
            "Retrieve specific chunks using filters",
        "show file content":
            "Show the content of a specified file",
        "vector stores info files":
            "Show file counts, bytes, and storage details",
        "llm query file":
            "Query a specific file from a vector store",
        "llm setup":
            "Configure an LLM provider",
        "help":
            "Show available commands",
        "vector stores list":
            "List all available vector stores",
        "vector stores select":
            "Select a vector store to work with",
        "vector stores info users":
            "Show user assignments and access",
        "llm query ask":
            "Ask a query using LLM",
        "query history":
            "Show query history",
        "session info":
            "Show comprehensive session information",
        "session export":
            "Export session to file",
        "session clear":
            "Clear session history",
        "config show":
            "Show current configuration",
        "metrics":
            "Show application metrics",
        "health":
            "Run health checks",
        "clear":
            "Clear screen",
        "exit":
            "Exit application",
        "quit":
            "Exit application",
    }

    def __init__(
        self,
        services: Dict,
        config: Dict,
        logger,
        console: Console,
        error_handler,
        session_manager,
        config_manager=None,
    ):
        self.services = services
        self.config = config
        self.logger = logger
        self.console = Console(markup=True, force_terminal=True)
        self.error_handler = error_handler
        self.session_manager = session_manager
        self.config_manager = config_manager

        self.current_user = config.get("oc_username")
        self.user_type = "ocp"
        self.current_namespace = config.get("cas_namespace")
        self.current_vector_store = None
        self.running = True

        self.session: Any = _SessionProxy(PromptSession())
        self.command_completer = FuzzyCompleter(
            WordCompleter(list(self.COMMANDS.keys()), ignore_case=True))

    def _get_query_input(self) -> Optional[str]:
        """Get and validate query from user."""
        query = self.session.prompt(
            f"[{self.current_user}@{self.current_vector_store or 'global'}] Enter your query: "
        ).strip()

        if not query:
            self.console.print("[yellow]Query cannot be empty[/]")
            return None
        return query

    def _execute_query_with_llm(self, query: str) -> bool:
        """Execute query and process with LLM."""
        vector_store = self._get_active_vector_store()

        search_result = self._execute_vector_search(query, vector_store)
        if not search_result:
            return False

        data = search_result.get("data", [])
        if not data:
            self.console.print(
                "[yellow]No chunks found matching your query.[/]\n"
                "[dim]Try rephrasing your query or using different keywords.[/]"
            )
            return False

        self.console.print("\n[bold cyan]Getting AI response...[/]\n")
        self.services["llm"].call_llm(search_result, query)

        self._record_successful_query(query)
        return True

    def _get_active_vector_store(self) -> Optional[str]:
        """Get the active vector store, prioritizing current selection over default."""
        vector_store = self.current_vector_store or self.config.get(
            "default_vector_store", "")
        if not vector_store:
            self.console.print(
                "[red]✗ No vector store selected or configured[/]")
            return None
        return vector_store

    def _record_successful_query(self, query: str) -> None:
        """Record successful query execution in session history."""
        self.session_manager.add_query(
            user=self.current_user,
            query=query,
            vector_store=self.current_vector_store,
            user_type=self.user_type,
            authenticated=True,
        )
        self.logger.info(
            f"Query completed successfully for {self.current_user}")

    def _get_file_identifiers(self):
        """Get vector store ID and file ID from user input."""
        vector_store_id = self._get_input(
            f"[{self.current_user}@{self.current_vector_store or 'global'}] "
            "Enter the vector store ID (might be same as vector store name): ")

        file_id = self._get_input(
            f"[{self.current_user}@{self.current_vector_store or 'global'}] "
            "Enter the file ID: ")

        return vector_store_id, file_id

    def _retrieve_file_content(self, vector_store_id: str, file_id: str):
        """Retrieve file content with user authentication."""
        self.logger.info(
            f"Retrieving file content for {self.current_user} ({self.user_type})"
        )

        file_content = self.services["query"].get_file_content(
            vector_store_id=vector_store_id,
            file_id=file_id,
        )

        if not self._retrieved_result_valid(file_content,
                                            "File content retrieval"):
            return None

        return file_content

    def _record_file_lookup(self, vector_store_id: str, file_id: str) -> None:
        """Record file lookup in session history."""
        self.session_manager.add_file_lookup(
            user=self.current_user,
            vector_store_id=vector_store_id,
            file_id=file_id,
            user_type=self.user_type,
            authenticated=True,
        )

        self.logger.info(
            f"File content retrieved successfully for {self.current_user}")

    def _execute_vector_search(
        self,
        query: str,
        vector_store: str | None,
        limit: int | None = None,
    ):
        """Execute vector store search with user authentication."""
        self.logger.info(
            f"Executing query for user {self.current_user} ({self.user_type})")

        search_result = self.services["query"].query_vector_store(
            user_query=query,
            vector_store=vector_store,
            limit=limit,
        )

        if not self._retrieved_result_valid(search_result, "Query"):
            return None

        return search_result

    def _check_token(self) -> bool:
        """Check authentication token validity."""
        return TokenValidator.check_token_with_message(
            self.services["auth"], self.console,
            "[red]✗ Authentication failed. Please check your credentials.[/]")

    def _user_in_vector_store(
        self,
        vector_store: str | None,
        silent: bool = False,
    ) -> bool:
        """Check if user has access to current vector store."""
        if not self.current_user:
            if not silent:
                self.console.print(
                    "[red]✗ No user selected. Select a user first with 'users select'[/]"
                )
            return False

        if vector_store:
            if vector_store in self._accessible_vector_stores():
                return True

            if not silent:
                self.console.print(
                    f"[red]✗ User '{self.current_user}' is not assigned to vector store/domain '{vector_store}'[/]"
                )
                self.console.print(
                    "[dim]Please add this user to the vector store in the Fusion UI[/]\n"
                )
            self.logger.warning(
                f"User {self.current_user} not in vector store {vector_store}")
            return False

        if not silent:
            self.console.print(
                "[red]✗ A vector store/domain has not been selected[/]")
            self.console.print(
                "[dim]Please select a vector store first with 'vector_stores select'[/]\n"
            )
        self.logger.warning("A vector store/domain has not been selected")
        return False

    def _retrieved_result_valid(self, result, content_type: str) -> bool:
        """Validate retrieval result."""
        if isinstance(result, dict) and not result.get("success", True):
            error = result.get("error", "Unknown error")
            details = result.get("details", "")

            self.console.print(f"[red]✗ {content_type} failed: {error}[/]")

            if "bearer token" in error.lower() or "token" in error.lower():
                self.console.print(
                    "[bold yellow]⚠ No valid bearer token available.[/]")
                self.console.print(
                    "[yellow]You cannot use commands until your token is valid.[/]"
                )
                self.console.print(
                    "[yellow]Please restart the application and authenticate.[/]"
                )
            elif result.get("status_code") == HTTP_STATUS_UNAUTHORIZED:
                self.console.print(
                    "[red]Invalid or expired user token. Please re-authenticate.[/]"
                )
            elif result.get("status_code") == HTTP_STATUS_FORBIDDEN:
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
        """Get required non-empty input from the user."""
        while True:
            user_input = self.session.prompt(prompt).strip()
            if not user_input:
                self.console.print("[yellow]Input cannot be empty[/] ")
            else:
                return user_input

    def _has_valid_llm_config(self) -> bool:
        """Check if current configuration has a valid LLM provider."""
        if not self.config_manager:
            return False
        return self.config_manager.has_llm_configured(self.config)

    def _ensure_llm_configured(self) -> bool:
        """Ensure an LLM provider is configured before LLM-backed commands."""
        if self._has_valid_llm_config():
            return True

        self.console.print(
            "[yellow]LLM is not configured. Run 'llm setup' to configure an LLM provider before using this command.[/]"
        )
        return False

    def _prompt_llm_setup(self) -> None:
        """Prompt user to configure LLM provider if needed."""
        if self._has_valid_llm_config():
            use_default = Confirm.ask(
                "\n[yellow]Use default LLM from config?[/]",
                default=True,
            )

            if use_default:
                self.console.print(
                    "[bold green]✓ Using default LLM configuration from config.yaml[/]"
                )
                return

            if self.config_manager:
                self.config_manager.reset_llm_config()

        self.console.print()

        setup_llm = Confirm.ask(
            "[yellow]Some commands use an LLM to enhance responses. Would you like to configure an LLM provider now?[/]",
            default=False,
        )

        if not setup_llm:
            self.console.print(
                "[dim]You can configure LLM later with the command 'llm setup'.[/]"
            )
            return

        if self.config_manager:
            llm_config = self.config_manager.prompt_for_llm_setup()

            if llm_config:
                self.config_manager.update_llm_config(llm_config)
                self.config.update(llm_config)

                self.console.print(
                    "\n[bold green]✓ LLM configuration complete![/]")
                self.console.print(
                    "[dim]You can now use commands like 'llm query ask' with LLM enhancement.[/]\n"
                )
        else:
            self.console.print(
                "[yellow]⚠ Config manager not available. Please configure LLM manually in config.yaml[/]"
            )

    def run(self) -> int:
        """Main CLI loop."""
        displays.display_welcome(self)

        try:
            handlers._prompt_vector_store_selection(self)
        except Exception as e:
            self.logger.warning(f"Error during vector store selection: {e}")
            self.console.print(
                "[yellow]⚠ Could not complete vector store selection. You can select one later using 'vector-stores select'.[/]"
            )

        try:
            self._prompt_llm_setup()
        except Exception as e:
            self.logger.warning(f"Error during LLM setup: {e}")
            self.console.print(
                "[yellow]⚠ Error during LLM setup. You can configure it later in config.yaml[/]"
            )

        try:
            while self.running:
                try:
                    prompt_text = displays._build_prompt(self)
                    command = self.session.prompt(
                        prompt_text,
                        completer=self.command_completer,
                    ).strip().lower()

                    if not command:
                        continue

                    handlers.execute_command(self, command)

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

    # Minimal compatibility layer for existing callers/tests.
    def display_welcome(self, *args: Any, **kwargs: Any) -> Any:
        return displays.display_welcome(self, *args, **kwargs)

    def display_help(self, *args: Any, **kwargs: Any) -> Any:
        return displays.display_help(self, *args, **kwargs)

    def display_status(self, *args: Any, **kwargs: Any) -> Any:
        return displays.display_status(self, *args, **kwargs)

    def cmd_config_show(self, *args: Any, **kwargs: Any) -> Any:
        return displays.cmd_config_show(self, *args, **kwargs)

    def _sanitize_config(self, *args: Any, **kwargs: Any) -> Any:
        return displays._sanitize_config(self, *args, **kwargs)

    def _display_file_content(self, *args: Any, **kwargs: Any) -> Any:
        return displays._display_file_content(self, *args, **kwargs)

    def _clean_chunk_text(self, *args: Any, **kwargs: Any) -> Any:
        return displays._clean_chunk_text(self, *args, **kwargs)

    def _display_search_chunks(self, *args: Any, **kwargs: Any) -> Any:
        return displays._display_search_chunks(self, *args, **kwargs)

    def _build_prompt(self, *args: Any, **kwargs: Any) -> str:
        return displays._build_prompt(self, *args, **kwargs)

    def render_vector_stores_tree(self, *args: Any, **kwargs: Any) -> Any:
        return displays.render_vector_stores_tree(self, *args, **kwargs)

    def cmd_vector_stores_list(self, *args: Any, **kwargs: Any) -> Any:
        return handlers.cmd_vector_stores_list(self, *args, **kwargs)

    def cmd_vector_stores_select(self, *args: Any, **kwargs: Any) -> Any:
        return handlers.cmd_vector_stores_select(self, *args, **kwargs)

    def _set_vector_store(self, *args: Any, **kwargs: Any) -> Any:
        return handlers._set_vector_store(self, *args, **kwargs)

    def cmd_vector_stores_info(self, *args: Any, **kwargs: Any) -> Any:
        return handlers.cmd_vector_stores_info(self, *args, **kwargs)

    def cmd_query_ask(self, *args: Any, **kwargs: Any) -> Any:
        return handlers.cmd_query_ask(self, *args, **kwargs)

    def cmd_query_history(self, *args: Any, **kwargs: Any) -> Any:
        return handlers.cmd_query_history(self, *args, **kwargs)

    def cmd_session_info(self, *args: Any, **kwargs: Any) -> Any:
        return handlers.cmd_session_info(self, *args, **kwargs)

    def cmd_session_export(self, *args: Any, **kwargs: Any) -> Any:
        return handlers.cmd_session_export(self, *args, **kwargs)

    def cmd_session_clear(self, *args: Any, **kwargs: Any) -> Any:
        return handlers.cmd_session_clear(self, *args, **kwargs)

    def cmd_metrics(self, *args: Any, **kwargs: Any) -> Any:
        return handlers.cmd_metrics(self, *args, **kwargs)

    def cmd_health(self, *args: Any, **kwargs: Any) -> Any:
        return handlers.cmd_health(self, *args, **kwargs)

    def cmd_clear(self, *args: Any, **kwargs: Any) -> Any:
        return handlers.cmd_clear(self, *args, **kwargs)

    def _accessible_vector_stores(self, *args: Any, **kwargs: Any) -> Any:
        return handlers._accessible_vector_stores(self, *args, **kwargs)

    def cmd_vector_search(self, *args: Any, **kwargs: Any) -> Any:
        return handlers.cmd_vector_search(self, *args, **kwargs)

    def cmd_vector_search_filter(self, *args: Any, **kwargs: Any) -> Any:
        return handlers.cmd_vector_search_filter(self, *args, **kwargs)

    def cmd_casapi_show_file_content(self, *args: Any, **kwargs: Any) -> Any:
        return handlers.cmd_casapi_show_file_content(self, *args, **kwargs)

    def cmd_casapi_query_file(self, *args: Any, **kwargs: Any) -> Any:
        return handlers.cmd_casapi_query_file(self, *args, **kwargs)

    def cmd_casapi_vector_stores_info(self, *args: Any, **kwargs: Any) -> Any:
        return handlers.cmd_casapi_vector_stores_info(self, *args, **kwargs)

    def _prompt_vector_store_selection(self, *args: Any, **kwargs: Any) -> Any:
        return handlers._prompt_vector_store_selection(self, *args, **kwargs)

    def cmd_llm_setup(self, *args: Any, **kwargs: Any) -> Any:
        return handlers.cmd_llm_setup(self, *args, **kwargs)

    def execute_command(self, *args: Any, **kwargs: Any) -> Any:
        return handlers.execute_command(self, *args, **kwargs)
