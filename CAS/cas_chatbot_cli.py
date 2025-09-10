# chatbot.py

import requests
import subprocess
import yaml
import difflib
import sys
import json
import argparse
import logging
import time
import os
from datetime import datetime
from typing import Dict, List, Optional, Any
from urllib.parse import urlparse
from pathlib import Path
from dataclasses import dataclass, asdict

# Third-party imports
from prompt_toolkit import PromptSession
from prompt_toolkit.completion import WordCompleter
from prompt_toolkit.history import FileHistory
from prompt_toolkit.auto_suggest import AutoSuggestFromHistory
from openai import OpenAI
from rich.console import Console
from rich.text import Text
from rich.align import Align
from rich.panel import Panel
from rich.table import Table
from rich.progress import Progress, SpinnerColumn, TextColumn
from rich.logging import RichHandler

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(message)s",
    datefmt="[%X]",
    handlers=[RichHandler(rich_tracebacks=True)]
)
logger = logging.getLogger("CASChatBot")
console = Console()


@dataclass
class QueryResult:
    """Data class for query results"""
    success: bool
    data: Any = None
    error: str = ""
    timestamp: datetime = None

    def __post_init__(self):
        if self.timestamp is None:
            self.timestamp = datetime.now()

    def to_dict(self):
        return {
            "success": self.success,
            "data": self.data,
            "error": self.error,
            "timestamp": self.timestamp.isoformat() if self.timestamp else None
        }


class ConfigurationError(Exception):
    """Custom exception for configuration errors"""
    pass


class AuthenticationError(Exception):
    """Custom exception for authentication errors"""
    pass


class CASChatBot:
    """Enhanced Enterprise CAS Chatbot with improved error handling and features"""

    def __init__(self, config_path: str = "config.yaml"):
        self.config_path = config_path
        self.config = self.load_config(config_path)
        self.console_url = self.config["console_url"]
        self.username = self.config["oc_username"]
        self.password = self.config["oc_password"]
        self.token = None
        self.table_completer = None
        self.default_table = None
        self.tables = []
        self.chat_history = []
        self.query_count = 0
        self.session_start_time = datetime.now()

        # Setup session with history and auto-suggest
        history_file = Path.home() / ".cas_chatbot_history"
        self.session = PromptSession(
            history=FileHistory(str(history_file)),
            auto_suggest=AutoSuggestFromHistory()
        )

        # Setup logging
        self.setup_logging()

        logger.info("CAS Chatbot initialized")

    def setup_logging(self):
        """Setup logging configuration"""
        log_level = self.config.get("log_level", "INFO").upper()
        log_file = self.config.get("log_file", "cas_chatbot.log")

        # File handler
        file_handler = logging.FileHandler(log_file)
        file_handler.setLevel(getattr(logging, log_level))
        file_formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        file_handler.setFormatter(file_formatter)
        logger.addHandler(file_handler)

    def load_config(self, path: str) -> Dict:
        """Load and validate configuration file"""
        try:
            if not os.path.exists(path):
                raise ConfigurationError(f"Configuration file not found: {path}")

            with open(path, 'r') as f:
                config = yaml.safe_load(f)

            # Validate required configuration
            required_keys = [
                "console_url", "oc_username", "oc_password", "cas_url"
            ]
            missing_keys = [key for key in required_keys if key not in config]
            if missing_keys:
                raise ConfigurationError(f"Missing required configuration keys: {missing_keys}")

            logger.info(f"Configuration loaded from {path}")
            return config

        except yaml.YAMLError as e:
            raise ConfigurationError(f"Invalid YAML configuration: {e}")
        except Exception as e:
            raise ConfigurationError(f"Error loading configuration: {e}")

    def get_api_url_from_console(self) -> str:
        """Extract API URL from console URL"""
        try:
            parsed = urlparse(self.console_url)
            host = parsed.hostname

            if not host:
                raise ValueError("Invalid console URL - no hostname found")

            if host.startswith("console-openshift-console.apps."):
                api_host = host.replace("console-openshift-console.apps.", "api.")
                return f"https://{api_host}:6443"

            # Handle alternative formats
            if "console" in host and "apps" in host:
                api_host = host.replace("console-openshift-console", "api").split(".apps.")[0] + ".apps." + \
                           host.split(".apps.")[1]
                return f"https://api.{host.split('.apps.')[1]}:6443"

            raise ValueError("Unsupported OpenShift Console URL format")

        except Exception as e:
            raise ConfigurationError(f"Failed to parse console URL: {e}")

    def authenticate(self) -> bool:
        """Authenticate with OpenShift cluster"""
        try:
            api_url = self.get_api_url_from_console()

            with Progress(
                    SpinnerColumn(),
                    TextColumn("[progress.description]{task.description}"),
                    console=console,
            ) as progress:
                task = progress.add_task("🔐 Authenticating with OpenShift...", total=None)

                # Perform authentication
                result = subprocess.run([
                    "oc", "login", api_url,
                    "--username", self.username,
                    "--password", self.password,
                    "--insecure-skip-tls-verify"
                ], capture_output=True, text=True, timeout=30)

                if result.returncode != 0:
                    raise AuthenticationError(f"Login failed: {result.stderr}")

                # Get token
                token_result = subprocess.run(
                    ['oc', 'whoami', '-t'],
                    capture_output=True,
                    text=True,
                    timeout=10
                )

                if token_result.returncode != 0:
                    raise AuthenticationError("Failed to retrieve authentication token")

                self.token = token_result.stdout.strip()
                progress.update(task, completed=True)

            console.print("[green]Authentication successful[/green]")
            logger.info("Successfully authenticated with OpenShift")
            return True

        except subprocess.TimeoutExpired:
            raise AuthenticationError("Authentication timed out")
        except Exception as e:
            logger.error(f"Authentication failed: {e}")
            raise AuthenticationError(f"Authentication failed: {e}")

    def check_cas_service_status(self) -> bool:
        """Check CAS service health and connectivity"""
        try:
            base_url = self.config['cas_url']
            endpoints = [
                ("/api/v1/querysearch", "Query Search API"),
                ("/api/v1/querysearch/health", "Health Check")
            ]
            headers = {'Authorization': f'Bearer {self.token}'}

            console.print("🔍 [bold blue]Checking CAS service status...[/bold blue]")

            for endpoint, description in endpoints:
                try:
                    response = requests.get(
                        f"{base_url}{endpoint}",
                        headers=headers,
                        timeout=self.config.get("request_timeout", 10)
                    )

                    if response.ok:
                        console.print(f"[dim]{description}: OK[/dim]")

                        # Try to extract and display message
                        try:
                            data = response.json()
                            if "message" in data:
                                console.print(f"   [green]{data['message']}[/green]")
                        except json.JSONDecodeError:
                            pass
                    else:
                        console.print(f"[red]{description}: Failed ({response.status_code})[/red]")
                        return False

                except requests.exceptions.Timeout:
                    console.print(f"⏱️ [yellow]{description}: Timeout[/yellow]")
                    return False
                except requests.exceptions.ConnectionError:
                    console.print(f"🔌 [red]{description}: Connection Error[/red]")
                    return False

            logger.info("CAS service status check passed")
            return True

        except Exception as e:
            logger.error(f"CAS service validation failed: {e}")
            console.print(f"[red]CAS service validation failed: {e}[/red]")
            return False

    def fetch_tables(self) -> bool:
        """Fetch available tables from CAS"""
        query_params =""
        if self.config.get("default_after"):
            query_params += f"?after={self.config.get("default_after")}"
        if self.config.get("default_before"):
            query_params += f"?before={self.config.get("default_before")}"
        if self.config.get("default_limit"):
            query_params += f"?limit={self.config.get("default_limit")}"
        if self.config.get("efault_order"):
            query_params += f"?order={self.config.get("default_order")}"

        try:
            headers = {'Authorization': f'Bearer {self.token}'}
            response = requests.get(
                f"{self.config['cas_url']}/contentawarestorage/api/v1/vector_stores{query_params}",
                headers=headers,
                timeout=self.config.get("request_timeout", 10)
            )

            if response.ok:
                data = response.json()
                self.tables =[]
                for table in data.get("data",[]):
                    self.tables.append(table.get("name"))

                if not self.tables:
                    console.print("[yellow]No tables found for this user role[/yellow]")
                    return False

                # Display tables in a nice format
                table = Table(title="Available Tables", show_header=True, header_style="bold magenta")
                table.add_column("Index", style="dim", width=6)
                table.add_column("Table Name", style="cyan")

                for idx, tbl in enumerate(self.tables, 1):
                    table.add_row(str(idx), tbl)

                console.print(table)

                # Setup auto-completion
                self.table_completer = WordCompleter(self.tables, ignore_case=True)
                logger.info(f"Fetched {len(self.tables)} tables")
                return True
            else:
                console.print(f"[red]Error fetching tables: {response.status_code} - {response.text}[/red]")
                return False

        except Exception as e:
            logger.error(f"Failed to fetch tables: {e}")
            console.print(f"[red]Failed to fetch tables: {e}[/red]")
            return False

    def query(self, user_query: str, vector_store_id: str) -> QueryResult:
        """Execute semantic search query"""
        try:
            headers = {
                'Authorization': f'Bearer {self.token}',
                'Content-Type': 'application/json'
            }

            payload = {
                "query": user_query,
                "ranking_options": self.config.get("default_ranking_options"),
                "max_num_results": self.config.get("default_max_num_results", 5),
                "enable_source": self.config.get("enable_source", False),
                "enable_content_metadata": self.config.get("enable_content_metadata", False)
            }

            with Progress(
                    SpinnerColumn(),
                    TextColumn("[progress.description]{task.description}"),
                    console=console,
            ) as progress:
                task = progress.add_task("🔍 Searching...", total=None)

                response = requests.post(
                    f"{self.config['cas_url']}/vector_stores/{vector_store_id}/search'",
                    headers=headers,
                    json=payload,
                    timeout=self.config.get("request_timeout", 30)
                )

                progress.update(task, completed=True)

            if response.ok:
                data = response.json()
                self.query_count += 1
                logger.info(f"Query executed successfully for table: {table}")
                return QueryResult(success=True, data=data)
            else:
                error_msg = f"Query failed: {response.status_code} - {response.text}"
                logger.error(error_msg)
                return QueryResult(success=False, error=error_msg)

        except requests.exceptions.Timeout:
            error_msg = "Query timed out"
            logger.error(error_msg)
            return QueryResult(success=False, error=error_msg)
        except Exception as e:
            error_msg = f"Query error: {e}"
            logger.error(error_msg)
            return QueryResult(success=False, error=error_msg)

    def call_llm(self, search_result, user_query):
        # Safely serialize the QueryResult object
        try:
            query_data = search_result.to_dict()
        except AttributeError:
            query_data = {
                "success": getattr(search_result, "success", False),
                "data": getattr(search_result, "data", None),
                "error": getattr(search_result, "error", ""),
                "timestamp": str(getattr(search_result, "timestamp", datetime.now()))
            }

        prompt = f"""
    You are an intelligent assistant helping users understand data from a semantic search engine.
    Based on the following retrieved data:
    {json.dumps(query_data, indent=2)}
    Answer the user's query: \"{user_query}\"
    """


        for provider in self.config.get("llm_provider_sequence", []):
            try:
                console.print(f"[yellow]Trying LLM provider: {provider}[/yellow]")

                payload = [
                    {"role": "system", "content": "You help analyze CAS semantic search results."},
                    {"role": "user", "content": prompt}
                ]

                # === OPENAI ===
                if provider == "openai":
                    client = OpenAI(api_key=self.config.get("openai_api_key"))
                    stream = client.chat.completions.create(
                        model=self.config.get("openai_model", "gpt-3.5-turbo"),
                        messages=payload,
                        stream=True
                    )
                    for chunk in stream:
                        content = chunk.choices[0].delta.content if chunk.choices[0].delta else ""
                        console.print(content, end="")
                    print()
                    return

                # === OLLAMA ===
                elif provider == "ollama":
                    response = requests.post(
                        f"{self.config['ollama_host']}/api/generate",
                        json={"model": self.config['ollama_model'], "prompt": prompt, "stream": True},
                        stream=True
                    )
                    for line in response.iter_lines():
                        if line:
                            data = json.loads(line.decode("utf-8"))
                            if "response" in data:
                                console.print(data["response"], end="")
                    print()
                    return

                # === NVIDIA ===
                elif provider == "nvidia":
                    response = requests.post(
                        f"{self.config['nvidia_llm_url']}/v1/chat/completions",
                        headers={"Content-Type": "application/json"},
                        json={"model": self.config['nvidia_model'], "messages": payload, "stream": False}
                    )

                    if response.ok:
                        data = response.json()
                        if "choices" in data:
                            message = data["choices"][0]["message"]["content"]
                            console.print(message)
                            return
                        else:
                            console.print(
                                f"[red]Unexpected response format from NVIDIA:[/red] {json.dumps(data, indent=2)}")
                    else:
                        console.print(f"[red]NVIDIA API call failed ({response.status_code}): {response.text}[/red]")

                # === Granite ===
                elif provider == "granite":
                    response = requests.post(
                    f"{self.config['llm_url']}/v1/chat/completions",
                        headers={"Content-Type": "application/json"},
                        json={"model": self.config['llm_model'], "messages": payload, "stream": False}
                        )

                    if response.ok:
                        data = response.json()
                        if "choices" in data:
                            message = data["choices"][0]["message"]["content"]
                            console.print(message)
                            return
                        else:
                            console.print(
                                f"[red]Unexpected response format from Granite:[/red] {json.dumps(data, indent=2)}")
                else:
                    console.print(f"[red]Granite API call failed ({response.status_code}): {response.text}[/red]")

            except Exception as e:
                console.print(f"[red]Provider {provider} failed: {e}[/red]")
                continue

    console.print("[red]All LLM providers failed.[/red]")


    def display_help(self):
        """Display help information"""
        help_table = Table(title="Available Commands", show_header=True, header_style="bold cyan")
        help_table.add_column("Command", style="green", width=15)
        help_table.add_column("Description", style="white")
        help_table.add_column("Example", style="dim")

        commands = [
            ("help", "Show this help menu", "help"),
            ("bye/exit/quit", "Exit the chatbot", "bye"),
            ("history", "Show query history", "history"),
            ("clear", "Clear query history", "clear"),
            ("tables", "List available tables", "tables"),
            ("table <name>", "Switch to a specific table", "table customers"),
            ("stats", "Show session statistics", "stats"),
            ("export", "Export chat history", "export"),
            ("<query>", "Ask a question", "What are the sales trends?")
        ]

        for cmd, desc, example in commands:
            help_table.add_row(cmd, desc, example)

        console.print(help_table)

    def display_stats(self):
        """Display session statistics"""
        uptime = datetime.now() - self.session_start_time

        stats_table = Table(title="Session Statistics", show_header=True, header_style="bold magenta")
        stats_table.add_column("Metric", style="cyan")
        stats_table.add_column("Value", style="green")

        stats_table.add_row("Session Duration", str(uptime).split('.')[0])
        stats_table.add_row("Queries Executed", str(self.query_count))
        stats_table.add_row("Current Table", self.default_table or "None")
        stats_table.add_row("Available Tables", str(len(self.tables)))
        stats_table.add_row("History Length", str(len(self.chat_history)))

        console.print(stats_table)

    def export_history(self):
        """Export chat history to file"""
        try:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"cas_chat_history_{timestamp}.json"

            export_data = {
                "session_info": {
                    "start_time": self.session_start_time.isoformat(),
                    "export_time": datetime.now().isoformat(),
                    "query_count": self.query_count,
                    "default_table": self.default_table
                },
                "chat_history": self.chat_history
            }

            with open(filename, 'w') as f:
                json.dump(export_data, f, indent=2)

            console.print(f"[green]Chat history exported to {filename}[/green]")

        except Exception as e:
            console.print(f"[red]Failed to export history: {e}[/red]")

    def run(self):
        """Main chatbot loop"""
        try:
            # Initialization sequence
            console.print("\n[bold cyan]Starting CAS Chatbot...[/bold cyan]")

            if not self.authenticate():
                return

            if not self.check_cas_service_status():
                console.print("[red]CAS service checks failed. Exiting.[/red]")
                return

            if not self.fetch_tables():
                console.print("[red]No tables available. Exiting.[/red]")
                return

            # Select default table
            if self.config.get("default_table") and self.config["default_table"] in self.tables:
                self.default_table = self.config["default_table"]
                console.print(f"[green]Using default table: {self.default_table}[/green]")
            else:
                console.print("\n[bold]Select a table to query:[/bold]")
                self.default_table = self.session.prompt(
                    "🔍 Table: ",
                    completer=self.table_completer
                )

            # Start chat session
            console.print("\n[bold green]Chat session started![/bold green]")
            console.print("[dim]Type 'help' for commands, 'bye' to quit[/dim]")

            # Command mapping
            commands = {
                "help": self.display_help,
                "bye": lambda: False,
                "exit": lambda: False,
                "quit": lambda: False,
                "history": lambda: self.display_history(),
                "clear": lambda: self.clear_history(),
                "tables": lambda: self.fetch_tables(),
                "stats": lambda: self.display_stats(),
                "export": lambda: self.export_history()
            }

            while True:
                try:
                    user_input = self.session.prompt(
                        f"[{self.default_table}] 👤 You: "
                    ).strip()

                    if not user_input:
                        continue

                    # Handle commands
                    user_input_lower = user_input.lower()

                    # Check for table switching
                    if user_input_lower.startswith("table "):
                        table_name = user_input[6:].strip()
                        if table_name in self.tables:
                            self.default_table = table_name
                            console.print(f"[green]Switched to table: {table_name}[/green]")
                        else:
                            console.print(f"[red]Table '{table_name}' not found[/red]")
                        continue

                    # Check for exact command match
                    if user_input_lower in commands:
                        if user_input_lower in ("bye", "exit", "quit"):
                            break
                        commands[user_input_lower]()
                        continue

                    # Fuzzy command matching
                    close_matches = difflib.get_close_matches(
                        user_input_lower, commands.keys(), n=1, cutoff=0.8
                    )

                    if close_matches:
                        suggested_command = close_matches[0]
                        console.print(f"[yellow]Did you mean '{suggested_command}'? (y/n)[/yellow]")
                        confirmation = self.session.prompt("").strip().lower()

                        if confirmation in ('y', 'yes'):
                            if suggested_command in ("bye", "exit", "quit"):
                                break
                            commands[suggested_command]()
                            continue

                    # Process as query
                    self.chat_history.append({
                        "timestamp": datetime.now().isoformat(),
                        "query": user_input,
                        "table": self.default_table
                    })

                    result = self.query(user_input, self.default_table)
                    self.call_llm(result, user_input)

                except KeyboardInterrupt:
                    console.print("\n[yellow]Interrupted by user[/yellow]")
                    break
                except EOFError:
                    break

            # Cleanup
            console.print("\n[cyan]Thanks for using CAS Chatbot![/cyan]")
            self.display_stats()

        except Exception as e:
            logger.error(f"Fatal error in main loop: {e}")
            console.print(f"[red]Fatal error: {e}[/red]")
            sys.exit(1)

    def display_history(self):
        """Display chat history"""
        if not self.chat_history:
            console.print("[yellow] No queries in history[/yellow]")
            return

        history_table = Table(title="Query History", show_header=True, header_style="bold blue")
        history_table.add_column("#", style="dim", width=4)
        history_table.add_column("Time", style="cyan", width=20)
        history_table.add_column("Table", style="magenta", width=15)
        history_table.add_column("Query", style="white")

        for i, entry in enumerate(self.chat_history[-10:], 1):  # Show last 10
            timestamp = datetime.fromisoformat(entry["timestamp"]).strftime("%H:%M:%S")
            history_table.add_row(
                str(i),
                timestamp,
                entry["table"],
                entry["query"][:50] + "..." if len(entry["query"]) > 50 else entry["query"]
            )

        console.print(history_table)

        if len(self.chat_history) > 10:
            console.print(f"[dim]... and {len(self.chat_history) - 10} more entries[/dim]")

    def clear_history(self):
        """Clear chat history"""
        self.chat_history.clear()
        console.print("[green]Chat history cleared[/green]")


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="Enhanced Enterprise CAS Chatbot",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python chatbot.py                    # Use default config.yaml
  python chatbot.py -c prod.yaml       # Use production config
  python chatbot.py --config dev.yaml  # Use development config
        """
    )

    parser.add_argument(
        '--config', '-c',
        default='config.yaml',
        help='Configuration YAML file path (default: config.yaml)'
    )

    parser.add_argument(
        '--version',
        action='version',
        version='CAS Chatbot v1.0.0'
    )

    args = parser.parse_args()

    # Display banner
    title_text = Text(" CAS ENTERPRISE CHATBOT", style="bold white on blue", justify="center")
    subtitle_text = Text("v1.0.0 - Enhanced Edition", style="bold cyan", justify="center")

    about_text = (
        "Content-Aware Storage powers AI applications like RAG with faster insights, "
        "lower costs, better performance, stronger security, and simplified operations."
    )

    console.print("\n")
    console.print(Align.center(title_text))
    console.print(Align.center(subtitle_text))
    console.print("\n")
    console.print(
        Panel.fit(
            Align.center(Text(about_text, justify="center")),
            title="[bold]ABOUT CAS[/bold]",
            border_style="green"
        )
    )
    console.print("\n")

    try:
        bot = CASChatBot(config_path=args.config)
        bot.run()
    except ConfigurationError as e:
        console.print(f"[red]Configuration Error: {e}[/red]")
        sys.exit(1)
    except AuthenticationError as e:
        console.print(f"[red]Authentication Error: {e}[/red]")
        sys.exit(1)
    except KeyboardInterrupt:
        console.print("\n[yellow]Interrupted by user[/yellow]")
        sys.exit(0)
    except Exception as e:
        console.print(f"[red]Unexpected error: {e}[/red]")
        logger.exception("Unexpected error occurred")
        sys.exit(1)


if __name__ == "__main__":
    main()