"""
Enhanced Logger Factory with rotating file handlers and structured logging
"""

import logging
import sys
from logging.handlers import RotatingFileHandler, TimedRotatingFileHandler
from pathlib import Path
from typing import Optional


class ColoredFormatter(logging.Formatter):
    """Custom formatter with color support for console output"""

    COLORS = {
        'DEBUG': '\033[36m',  # Cyan
        'INFO': '\033[32m',  # Green
        'WARNING': '\033[33m',  # Yellow
        'ERROR': '\033[31m',  # Red
        'CRITICAL': '\033[35m',  # Magenta
    }
    RESET = '\033[0m'

    def format(self, record):
        # Add color to levelname
        if hasattr(sys.stderr, 'isatty') and sys.stderr.isatty():
            levelname = record.levelname
            if levelname in self.COLORS:
                record.levelname = f"{self.COLORS[levelname]}{levelname}{self.RESET}"

        return super().format(record)


class LoggerFactory:
    """Factory for creating configured loggers"""

    @staticmethod
    def create_logger(
            name: str,
            log_file: Optional[str] = None,
            level: str = "INFO",
            max_bytes: int = 10485760,  # 10MB
            backup_count: int = 5,
            console_output: bool = True,
            structured: bool = False
    ) -> logging.Logger:
        """
        Create a configured logger instance

        Args:
            name: Logger name
            log_file: Path to log file (optional)
            level: Logging level
            max_bytes: Maximum log file size before rotation
            backup_count: Number of backup files to keep
            console_output: Enable console output
            structured: Use structured logging format

        Returns:
            Configured logger instance
        """
        logger = logging.getLogger(name)
        logger.setLevel(getattr(logging, level.upper()))

        # Remove existing handlers to avoid duplicates
        logger.handlers.clear()

        # Create formatters
        if structured:
            log_format = '{"timestamp": "%(asctime)s", "level": "%(levelname)s", "name": "%(name)s", "message": "%(message)s"}'
            date_format = '%Y-%m-%dT%H:%M:%S'
        else:
            log_format = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
            date_format = '%Y-%m-%d %H:%M:%S'

        # Console handler with colors
        if console_output:
            console_handler = logging.StreamHandler(sys.stdout)
            console_handler.setLevel(logging.INFO)

            colored_formatter = ColoredFormatter(
                log_format,
                datefmt=date_format
            )
            console_handler.setFormatter(colored_formatter)
            logger.addHandler(console_handler)

        # File handler with rotation
        if log_file:
            log_path = Path(log_file)
            log_path.parent.mkdir(parents=True, exist_ok=True)

            file_handler = RotatingFileHandler(
                log_file,
                maxBytes=max_bytes,
                backupCount=backup_count,
                encoding='utf-8'
            )
            file_handler.setLevel(logging.DEBUG)

            file_formatter = logging.Formatter(
                log_format,
                datefmt=date_format
            )
            file_handler.setFormatter(file_formatter)
            logger.addHandler(file_handler)

        return logger

    @staticmethod
    def create_rotating_logger(
            name: str,
            log_file: str,
            when: str = 'midnight',
            interval: int = 1,
            backup_count: int = 7,
            level: str = "INFO"
    ) -> logging.Logger:
        """
        Create a logger with time-based rotation

        Args:
            name: Logger name
            log_file: Path to log file
            when: Rotation interval ('S', 'M', 'H', 'D', 'midnight', 'W0'-'W6')
            interval: Number of intervals between rotations
            backup_count: Number of backup files to keep
            level: Logging level

        Returns:
            Configured logger instance
        """
        logger = logging.getLogger(name)
        logger.setLevel(getattr(logging, level.upper()))
        logger.handlers.clear()

        # Time-based rotating file handler
        log_path = Path(log_file)
        log_path.parent.mkdir(parents=True, exist_ok=True)

        handler = TimedRotatingFileHandler(
            log_file,
            when=when,
            interval=interval,
            backupCount=backup_count,
            encoding='utf-8'
        )

        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        )
        handler.setFormatter(formatter)
        logger.addHandler(handler)

        return logger

    @staticmethod
    def setup_application_logging(config: dict) -> logging.Logger:
        """
        Setup application-wide logging from configuration

        Args:
            config: Configuration dictionary

        Returns:
            Main application logger
        """
        log_config = config.get('logging', {})

        return LoggerFactory.create_logger(
            name='cas_chatbot',
            log_file=log_config.get('file', 'cas_chatbot.log'),
            level=log_config.get('level', 'INFO'),
            max_bytes=log_config.get('max_bytes', 10485760),
            backup_count=log_config.get('backup_count', 5),
            console_output=log_config.get('console_output', False),
            structured=log_config.get('structured', False)
        )


# Convenience function for backward compatibility
def setup_logger(name: str, log_file: Optional[str] = None, level: str = "INFO") -> logging.Logger:
    """Legacy function for backward compatibility"""
    return LoggerFactory.create_logger(name, log_file, level)