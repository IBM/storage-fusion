"""
CLI Middleware - Error handling and session management
"""

import json
import logging
import traceback
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Any, Optional
from rich.console import Console


class ErrorHandler:
    """Centralized error handling"""

    def __init__(self, logger: logging.Logger, console: Console):
        self.logger = logger
        self.console = console
        self.error_count = 0

    def handle_error(self, error: Exception, context: str = ""):
        """
        Handle an error with logging and user notification

        Args:
            error: The exception that occurred
            context: Context information about where the error occurred
        """
        self.error_count += 1

        error_msg = str(error)
        error_type = type(error).__name__

        # Log full traceback
        self.logger.error(f"Error in {context}: {error_type}: {error_msg}")
        self.logger.debug(traceback.format_exc())

        # User-friendly error message
        self.console.print(f"\n[bold red]✗ Error:[/] {error_msg}")

        if context:
            self.console.print(f"[dim]Context: {context}[/]")

        # Suggest actions based on error type
        suggestions = self._get_error_suggestions(error)
        if suggestions:
            self.console.print(f"[yellow]Suggestion:[/] {suggestions}")

    def _get_error_suggestions(self, error: Exception) -> str:
        """Get user-friendly suggestions based on error type"""
        error_type = type(error).__name__

        suggestions = {
            'ConnectionError': 'Check network connectivity and service availability',
            'TimeoutError': 'Service may be slow or unavailable. Try again later',
            'AuthenticationError': 'Check credentials in config.yaml',
            'PermissionError': 'Insufficient permissions. Check user access rights',
            'FileNotFoundError': 'Required file not found. Check file paths',
            'KeyError': 'Configuration may be incomplete. Review config.yaml',
            'ValueError': 'Invalid input provided. Check command parameters',
            'subprocess.CalledProcessError': 'External command failed. Check oc CLI installation'
        }

        return suggestions.get(error_type, 'Check logs for more details')

    def get_error_count(self) -> int:
        """Get total error count"""
        return self.error_count

    def reset_count(self):
        """Reset error counter"""
        self.error_count = 0


class SessionManager:
    """Manage user session data and history"""

    def __init__(self, config: Dict, logger: logging.Logger, session_file: str = "session_history.json"):
        self.config = config
        self.logger = logger
        self.session_file = Path(session_file)
        self.history = self._load()

        # Initialize session metadata if new
        if 'session_start' not in self.history:
            self.history['session_start'] = datetime.now().isoformat()
            self.history['queries'] = []
            self.history['assignments'] = []
            self.history['events'] = []

    def _load(self) -> Dict:
        """Load session history from file"""
        if self.session_file.exists():
            try:
                with open(self.session_file, 'r') as f:
                    data = json.load(f)
                    self.logger.info(f"Loaded session from {self.session_file}")
                    return data
            except Exception as e:
                self.logger.warning(f"Failed to load session: {e}")

        return {}

    def save(self):
        """Save session history to file"""
        try:
            self.history['last_updated'] = datetime.now().isoformat()

            with open(self.session_file, 'w') as f:
                json.dump(self.history, f, indent=2)

            self.logger.debug("Session saved")
        except Exception as e:
            self.logger.error(f"Failed to save session: {e}")

    def add_query(self, user: str, query: str, domain: Optional[str] = None,
                  answer: str = "", user_type: str = "ocp", authenticated: bool = False):
        """Add a query to history with authentication details"""
        entry = {
            'timestamp': datetime.now().isoformat(),
            'user': user,
            'query': query,
            'domain': domain,
            'answer': answer,
            'user_type': user_type,
            'authenticated': authenticated,
            'authenticated_at': datetime.now().isoformat() if authenticated else None
        }

        self.history.setdefault('queries', []).append(entry)
        self.save()
        self.logger.debug(f"Query added to session: {query[:50]}")

    def add_assignment(self, domain: str, user: str):
        """Add a domain assignment to history"""
        entry = {
            'timestamp': datetime.now().isoformat(),
            'domain': domain,
            'user': user
        }

        self.history.setdefault('assignments', []).append(entry)
        self.save()
        self.logger.debug(f"Assignment added to session: {user} -> {domain}")

    def add_event(self, event_type: str, details: Dict[str, Any]):
        """Add a general event to history"""
        entry = {
            'timestamp': datetime.now().isoformat(),
            'type': event_type,
            'details': details
        }

        self.history.setdefault('events', []).append(entry)
        self.save()

    def get_history(self) -> Dict:
        """Get full session history"""
        return self.history

    def get_queries(self, limit: Optional[int] = None) -> List[Dict]:
        """Get query history"""
        queries = self.history.get('queries', [])
        return queries[-limit:] if limit else queries

    def get_assignments(self, limit: Optional[int] = None) -> List[Dict]:
        """Get assignment history"""
        assignments = self.history.get('assignments', [])
        return assignments[-limit:] if limit else assignments

    def get_statistics(self) -> Dict[str, Any]:
        """Get session statistics"""
        queries = self.history.get('queries', [])
        assignments = self.history.get('assignments', [])

        # Count unique users and domains
        unique_users = set(q.get('user') for q in queries if q.get('user'))
        unique_domains = set(a.get('domain') for a in assignments if a.get('domain'))

        return {
            'total_queries': len(queries),
            'total_assignments': len(assignments),
            'unique_users': len(unique_users),
            'unique_domains': len(unique_domains),
            'session_start': self.history.get('session_start', 'Unknown'),
            'last_updated': self.history.get('last_updated', 'Unknown')
        }

    def clear(self):
        """Clear session history"""
        self.history = {
            'session_start': datetime.now().isoformat(),
            'queries': [],
            'assignments': [],
            'events': []
        }
        self.save()
        self.logger.info("Session history cleared")

    def export(self, filename: str):
        """Export session to a file"""
        export_data = {
            **self.history,
            'exported_at': datetime.now().isoformat()
        }

        with open(filename, 'w') as f:
            json.dump(export_data, f, indent=2)

        self.logger.info(f"Session exported to {filename}")

    def import_session(self, filename: str):
        """Import session from a file"""
        with open(filename, 'r') as f:
            imported_data = json.load(f)

        # Merge with current session
        for key in ['queries', 'assignments', 'events']:
            if key in imported_data:
                self.history.setdefault(key, []).extend(imported_data[key])

        self.save()
        self.logger.info(f"Session imported from {filename}")


class RateLimiter:
    """Simple rate limiter for API calls"""

    def __init__(self, max_requests: int, time_window: int):
        """
        Args:
            max_requests: Maximum number of requests
            time_window: Time window in seconds
        """
        self.max_requests = max_requests
        self.time_window = time_window
        self.requests = []

    def can_proceed(self) -> bool:
        """Check if request can proceed"""
        now = datetime.now().timestamp()

        # Remove old requests
        self.requests = [
            req for req in self.requests
            if now - req < self.time_window
        ]

        if len(self.requests) < self.max_requests:
            self.requests.append(now)
            return True

        return False

    def get_wait_time(self) -> float:
        """Get time to wait before next request"""
        if not self.requests:
            return 0.0

        oldest = min(self.requests)
        now = datetime.now().timestamp()
        wait = self.time_window - (now - oldest)

        return max(0.0, wait)