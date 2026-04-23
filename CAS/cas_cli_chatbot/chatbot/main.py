#!/usr/bin/env python3
"""
Enhanced CAS Chatbot - Enterprise Edition
Main entry point with improved error handling and initialization
"""

import sys
import logging
from pathlib import Path

# Add parent directory to Python path to allow imports when running as script
if __name__ == "__main__":
    parent_dir = Path(__file__).resolve().parent.parent
    if str(parent_dir) not in sys.path:
        sys.path.insert(0, str(parent_dir))

from rich.console import Console
from rich.panel import Panel

from chatbot.utils.config_loader import ConfigLoader
from chatbot.utils.config_manager import ConfigManager
from chatbot.utils.logger import LoggerFactory
from chatbot.utils.health_check import HealthChecker
from chatbot.services.auth_service import AuthService
from chatbot.services.user_service import UserService
from chatbot.services.vector_store_service import VectorStoreService
from chatbot.services.query_service import QueryService
from chatbot.services.llm_service import LLMService
from chatbot.services.cache_service import CacheService
from chatbot.services.metrics_service import MetricsService
from chatbot.cli.chatbot_cli import ChatbotCLI
from chatbot.cli.middleware import ErrorHandler, SessionManager
# Constants
SEPARATOR_LINE_LENGTH = 60
EXIT_CODE_KEYBOARD_INTERRUPT = 130
DEFAULT_LOG_MAX_BYTES = 10485760  # 10MB
DEFAULT_LOG_BACKUP_COUNT = 5


console = Console()


def display_banner():
    """Display application banner"""
    banner = """
    ╔═══════════════════════════════════════════════════════════╗
    ║                                                           ║
    ║           CAS Chatbot - Enterprise Edition                ║
    ║           Multi-Provider LLM Integration                  ║
    ║           Version 2.0.0                                   ║
    ║                                                           ║
    ╚═══════════════════════════════════════════════════════════╝
    """
    console.print(Panel(banner, style="bold cyan"))


def initialize_services(config: dict, logger: logging.Logger) -> dict:
    """
    Initialize all services with dependency injection

    Args:
        config: Configuration dictionary
        logger: Logger instance

    Returns:
        Dictionary of initialized services
    """
    console.print("\n[bold yellow]Initializing services...[/]")

    services = {}

    try:
        # Core services
        services['cache'] = CacheService(config=config, logger=logger)
        services['metrics'] = MetricsService(config=config, logger=logger)
        services['auth'] = AuthService(config=config,
                                       logger=logger,
                                       cache_service=services['cache'])

        # Business logic services
        services['user'] = UserService(config=config,
                                       auth_service=services['auth'],
                                       logger=logger,
                                       cache_service=services['cache'])

        services['vector store'] = VectorStoreService(
            config=config,
            auth_service=services['auth'],
            logger=logger,
            cache_service=services['cache'])

        services['query'] = QueryService(config=config,
                                         auth_service=services['auth'],
                                         logger=logger,
                                         cache_service=services['cache'])

        services['llm'] = LLMService(config=config,
                                     logger=logger,
                                     metrics_service=services['metrics'])

        console.print("[bold green]✓ All services initialized successfully[/]")
        return services

    except Exception as e:
        console.print(f"[bold red]✗ Service initialization failed: {str(e)}[/]")
        logger.exception("Service initialization error")
        raise


def run_health_checks(services: dict, logger: logging.Logger) -> bool:
    """
    Run health checks on all services

    Args:
        services: Dictionary of service instances
        logger: Logger instance

    Returns:
        True if all checks pass, False otherwise
    """
    console.print("\n[bold yellow]Running health checks...[/]")

    health_checker = HealthChecker(services, logger)
    results = health_checker.run_all_checks()

    # Display results
    for service_name, status in results.items():
        icon = "✓" if status['healthy'] else "✗"
        color = "green" if status['healthy'] else "red"
        console.print(f"[{color}]{icon} {service_name}: {status['message']}[/]")

    all_healthy = all(r['healthy'] for r in results.values())

    if all_healthy:
        console.print("[bold green]✓ All health checks passed[/]")
    else:
        console.print(
            "[bold yellow]⚠ Some services are unhealthy but continuing...[/]")

    return all_healthy


def main():
    """Main application entry point"""

    # Display banner
    display_banner()

    # Setup
    config_path = Path(__file__).parent / "config.yaml"
    logger = None

    try:
        # Interactive configuration setup
        config_manager = ConfigManager(config_path)
        config = config_manager.setup_interactive()

        # Load and validate configuration
        console.print(f"\n[bold cyan]Validating configuration...[/]\n")
        config_loader = ConfigLoader(config_path)

        # Validate configuration
        if not config_loader.validate(config):
            console.print("[bold red]Configuration validation failed![/]")
            return 1

        console.print("[bold green]✓ Configuration validated[/]")

        # Setup logging
        log_config = config.get('logging', {})
        logger = LoggerFactory.create_logger(
            name="cas_chatbot",
            log_file=log_config.get("file", "cas_chatbot.log"),
            level=log_config.get("level", "INFO"),
            max_bytes=log_config.get("max_bytes", DEFAULT_LOG_MAX_BYTES),
            backup_count=log_config.get("backup_count", DEFAULT_LOG_BACKUP_COUNT))

        logger.info("=" * SEPARATOR_LINE_LENGTH)
        logger.info("CAS Chatbot Application Starting")
        logger.info("=" * SEPARATOR_LINE_LENGTH)

        # Initialize error handler and session manager
        error_handler = ErrorHandler(logger=logger, console=console)
        session_manager = SessionManager(
            config=config,
            logger=logger,
            session_file=config.get('session', {}).get('file',
                                                       'session_history.json'))

        # Initialize services
        services = initialize_services(config, logger)

        # Authenticate and fetch bearer token
        console.print("\n[bold yellow]Authenticating with OpenShift...[/]")
        try:
            success = services['auth'].authenticate()
            if success:
                # Verify token was obtained
                if services['auth'].token:
                    console.print("[bold green]✓ Authentication successful[/]")
                    console.print(f"[dim]Bearer token obtained and cached[/]")
                else:
                    console.print(
                        "[bold red]✗ Failed to retrieve bearer token[/]")
                    console.print(
                        "[yellow]You cannot use commands until your token is valid.[/]"
                    )
                    console.print(
                        "[yellow]Please check your credentials and try again.[/]"
                    )
                    return 1
            else:
                console.print("[bold red]✗ Authentication failed[/]")
                console.print(
                    "[yellow]You cannot use commands until your token is valid.[/]"
                )
                console.print(
                    "[yellow]Please check your credentials and try again.[/]")
                return 1
        except Exception as e:
            error_handler.handle_error(e, "Authentication")
            console.print(
                "[yellow]You cannot use commands until your token is valid.[/]")
            return 1

        # Run health checks
        run_health_checks(services, logger)

        # Initialize CLI
        cli = ChatbotCLI(services=services,
                         config=config,
                         logger=logger,
                         console=console,
                         error_handler=error_handler,
                         session_manager=session_manager,
                         config_manager=config_manager)

        # Run CLI loop
        logger.info("Starting CLI interface")
        console.print("\n[bold green]Starting interactive CLI...[/]\n")

        exit_code = cli.run()

        # Cleanup
        logger.info("Application shutting down")
        console.print("\n[bold cyan]Thank you for using CAS Chatbot!\n[/]")

        return exit_code

    except KeyboardInterrupt:
        console.print("\n\n[bold yellow]Application interrupted by user[/]")
        if logger:
            logger.info("Application interrupted by user")
        return EXIT_CODE_KEYBOARD_INTERRUPT

    except Exception as e:
        console.print(f"\n[bold red]Fatal error: {str(e)}[/]")
        if logger:
            logger.exception("Fatal application error")
        return 1


if __name__ == "__main__":
    sys.exit(main())
