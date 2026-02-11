#!/usr/bin/env python3
"""
Enhanced CAS Chatbot - Enterprise Edition
Main entry point with improved error handling and initialization
"""

import sys
import logging
from pathlib import Path
from rich.console import Console
from rich.panel import Panel

from utils.config_loader import ConfigLoader
from utils.logger import LoggerFactory
from utils.health_check import HealthChecker
from services.auth_service import AuthService
from services.user_service import UserService
from services.domain_service import DomainService
from services.query_service import QueryService
from services.llm_service import LLMService
from services.cache_service import CacheService
from services.metrics_service import MetricsService
from cli.chatbot_cli import ChatbotCLI
from cli.middleware import ErrorHandler, SessionManager

console = Console()


def display_banner():
    """Display application banner"""
    banner = """
    ╔═══════════════════════════════════════════════════════════╗
    ║                                                           ║
    ║           CAS Chatbot - Enterprise Edition               ║
    ║           Multi-Provider LLM Integration                 ║
    ║           Version 2.0.0                                  ║
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
    console.print("[bold yellow]Initializing services...[/]")

    services = {}

    try:
        # Core services
        services['cache'] = CacheService(config=config, logger=logger)
        services['metrics'] = MetricsService(config=config, logger=logger)
        services['auth'] = AuthService(
            config=config,
            logger=logger,
            cache_service=services['cache']
        )

        # User authentication manager for user-specific queries
        from services.user_auth_manager import UserAuthenticationManager
        services['user_auth'] = UserAuthenticationManager(config=config, logger=logger)

        # Business logic services
        services['user'] = UserService(
            config=config,
            auth_service=services['auth'],
            logger=logger,
            cache_service=services['cache']
        )

        services['domain'] = DomainService(
            config=config,
            auth_service=services['auth'],
            logger=logger,
            cache_service=services['cache']
        )

        services['query'] = QueryService(
            config=config,
            logger=logger,
            cache_service=services['cache']
        )

        services['llm'] = LLMService(
            config=config,
            logger=logger,
            metrics_service=services['metrics']
        )

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
        console.print("[bold yellow]⚠ Some services are unhealthy but continuing...[/]")

    return all_healthy


def main():
    """Main application entry point"""

    # Display banner
    display_banner()

    # Setup
    config_path = Path("config.yaml")
    logger = None

    try:
        # Load configuration
        console.print(f"[bold cyan]Loading configuration from {config_path}...[/]")
        config_loader = ConfigLoader(config_path)
        config = config_loader.load()

        # Validate configuration
        if not config_loader.validate(config):
            console.print("[bold red]Configuration validation failed![/]")
            return 1

        console.print("[bold green]✓ Configuration loaded and validated[/]")

        # Setup logging
        log_config = config.get('logging', {})
        logger = LoggerFactory.create_logger(
            name="cas_chatbot",
            log_file=log_config.get("file", "cas_chatbot.log"),
            level=log_config.get("level", "INFO"),
            max_bytes=log_config.get("max_bytes", 10485760),
            backup_count=log_config.get("backup_count", 5)
        )

        logger.info("=" * 60)
        logger.info("CAS Chatbot Application Starting")
        logger.info("=" * 60)

        # Initialize services
        services = initialize_services(config, logger)

        # Run health checks
        run_health_checks(services, logger)

        # Initialize error handler and session manager
        error_handler = ErrorHandler(logger=logger, console=console)
        session_manager = SessionManager(
            config=config,
            logger=logger,
            session_file=config.get('session', {}).get('file', 'session_history.json')
        )

        # Authenticate
        console.print("\n[bold yellow]Authenticating...[/]")
        try:
            success = services['auth'].authenticate()
            if success:
                console.print("[bold green]✓ Authentication successful[/]")
            else:
                console.print("[bold red]✗ Authentication failed[/]")
                return 1
        except Exception as e:
            error_handler.handle_error(e, "Authentication")
            return 1

        # Initialize CLI
        cli = ChatbotCLI(
            services=services,
            config=config,
            logger=logger,
            console=console,
            error_handler=error_handler,
            session_manager=session_manager
        )

        # Run CLI loop
        logger.info("Starting CLI interface")
        console.print("\n[bold green]Starting interactive CLI...[/]\n")

        exit_code = cli.run()

        # Cleanup
        logger.info("Application shutting down")
        console.print("\n[bold cyan]Thank you for using CAS Chatbot![/]")

        return exit_code

    except KeyboardInterrupt:
        console.print("\n\n[bold yellow]Application interrupted by user[/]")
        if logger:
            logger.info("Application interrupted by user")
        return 130

    except Exception as e:
        console.print(f"\n[bold red]Fatal error: {str(e)}[/]")
        if logger:
            logger.exception("Fatal application error")
        return 1


if __name__ == "__main__":
    sys.exit(main())