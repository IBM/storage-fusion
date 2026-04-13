"""
Metrics Service - Track application metrics and performance
"""

import time
import logging
from typing import Dict, List, Any
from datetime import datetime
from threading import Lock
from collections import defaultdict, deque
from typing import Dict, Optional


class MetricsService:
    """
    Service for tracking application metrics and performance
    """

    def __init__(self, config: Dict, logger: Optional[logging.Logger] = None):
        self.config = config
        self.logger = logger or logging.getLogger(__name__)
        self.lock = Lock()

        # Metrics storage
        self.counters: Dict[str, int] = defaultdict(int)
        self.gauges: Dict[str, float] = {}
        self.timings: Dict[str, deque] = defaultdict(lambda: deque(maxlen=100))
        self.errors: Dict[str, int] = defaultdict(int)

        # Configuration
        self.max_timing_samples = config.get('metrics', {}).get('max_samples', 100)

        self.start_time = time.time()
        self.logger.info("Metrics service initialized")

    def increment(self, metric: str, value: int = 1):
        """Increment a counter metric"""
        with self.lock:
            self.counters[metric] += value
            self.logger.debug(f"Metric incremented: {metric} += {value}")

    def set_gauge(self, metric: str, value: float):
        """Set a gauge metric"""
        with self.lock:
            self.gauges[metric] = value
            self.logger.debug(f"Gauge set: {metric} = {value}")

    def record_timing(self, metric: str, duration_ms: float):
        """Record a timing metric"""
        with self.lock:
            self.timings[metric].append(duration_ms)
            self.logger.debug(f"Timing recorded: {metric} = {duration_ms:.2f}ms")

    def record_error(self, error_type: str):
        """Record an error occurrence"""
        with self.lock:
            self.errors[error_type] += 1
            self.logger.debug(f"Error recorded: {error_type}")

    def get_counter(self, metric: str) -> int:
        """Get counter value"""
        with self.lock:
            return self.counters.get(metric, 0)

    def get_gauge(self, metric: str) -> float:
        """Get gauge value"""
        with self.lock:
            return self.gauges.get(metric, 0.0)

    def get_timing_stats(self, metric: str) -> Dict[str, float]:
        """Get timing statistics"""
        with self.lock:
            timings = list(self.timings.get(metric, []))

            if not timings:
                return {
                    'count': 0,
                    'min': 0,
                    'max': 0,
                    'avg': 0,
                    'p50': 0,
                    'p95': 0,
                    'p99': 0
                }

            sorted_timings = sorted(timings)
            count = len(sorted_timings)

            return {
                'count': count,
                'min': sorted_timings[0],
                'max': sorted_timings[-1],
                'avg': sum(sorted_timings) / count,
                'p50': sorted_timings[int(count * 0.5)],
                'p95': sorted_timings[int(count * 0.95)] if count > 1 else sorted_timings[0],
                'p99': sorted_timings[int(count * 0.99)] if count > 1 else sorted_timings[0]
            }

    def get_all_metrics(self) -> Dict[str, Any]:
        """Get all metrics"""
        with self.lock:
            uptime = time.time() - self.start_time

            metrics = {
                'uptime_seconds': round(uptime, 2),
                'counters': dict(self.counters),
                'gauges': dict(self.gauges),
                'errors': dict(self.errors),
                'timings': {}
            }

            for metric in self.timings.keys():
                metrics['timings'][metric] = self.get_timing_stats(metric)

            return metrics

    def reset(self):
        """Reset all metrics"""
        with self.lock:
            self.counters.clear()
            self.gauges.clear()
            self.timings.clear()
            self.errors.clear()
            self.start_time = time.time()
            self.logger.info("Metrics reset")

    def get_summary(self) -> str:
        """Get a summary of key metrics"""
        metrics = self.get_all_metrics()

        lines = [
            f"Uptime: {metrics['uptime_seconds'] / 3600:.1f} hours",
            f"Total Counters: {sum(metrics['counters'].values())}",
            f"Total Errors: {sum(metrics['errors'].values())}",
            f"Active Gauges: {len(metrics['gauges'])}",
            f"Tracked Timings: {len(metrics['timings'])}"
        ]

        return "\n".join(lines)


class Timer:
    """Context manager for timing operations"""

    def __init__(self, metrics_service: MetricsService, metric_name: str):
        self.metrics_service = metrics_service
        self.metric_name = metric_name
        self.start_time = None

    def __enter__(self):
        self.start_time = time.time()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        duration_ms = (time.time() - self.start_time) * 1000
        self.metrics_service.record_timing(self.metric_name, duration_ms)

        if exc_type is not None:
            self.metrics_service.record_error(f"{self.metric_name}_error")