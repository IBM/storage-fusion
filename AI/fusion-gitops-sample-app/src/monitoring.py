"""
Monitoring and Logging Module for Fusion Agentic Assistance Platform
Provides comprehensive logging, metrics collection, and health monitoring
"""

import logging
import time
from typing import Dict, Optional, Any
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
import json
from pathlib import Path


class LogLevel(Enum):
    """Log levels"""
    DEBUG = "DEBUG"
    INFO = "INFO"
    WARNING = "WARNING"
    ERROR = "ERROR"
    CRITICAL = "CRITICAL"


@dataclass
class MetricData:
    """Metric data structure"""
    name: str
    value: float
    timestamp: datetime = field(default_factory=datetime.now)
    tags: Dict[str, str] = field(default_factory=dict)
    
    def to_dict(self) -> Dict:
        """Convert to dictionary"""
        return {
            "name": self.name,
            "value": self.value,
            "timestamp": self.timestamp.isoformat(),
            "tags": self.tags
        }


class MonitoringService:
    """
    Centralized monitoring service for the Fusion Agentic Assistance platform
    
    Features:
    - Structured logging
    - Metrics collection
    - Performance tracking
    - Error tracking
    - Health monitoring
    """
    
    def __init__(
        self,
        service_name: str = "fusion-agentic-assistance-platform",
        log_level: str = "INFO",
        log_file: Optional[str] = None,
        enable_console: bool = True
    ):
        """
        Initialize monitoring service
        
        Args:
            service_name: Name of the service
            log_level: Logging level
            log_file: Path to log file (optional)
            enable_console: Enable console logging
        """
        self.service_name = service_name
        self.metrics: Dict[str, list] = {}
        self.start_time = time.time()
        
        # Configure logging
        self.logger = self._setup_logger(log_level, log_file, enable_console)
        
    def _setup_logger(
        self,
        log_level: str,
        log_file: Optional[str],
        enable_console: bool
    ) -> logging.Logger:
        """
        Setup structured logger
        
        Args:
            log_level: Logging level
            log_file: Path to log file
            enable_console: Enable console logging
            
        Returns:
            Configured logger
        """
        logger = logging.getLogger(self.service_name)
        logger.setLevel(getattr(logging, log_level.upper()))
        
        # Clear existing handlers
        logger.handlers.clear()
        
        # Create formatter
        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        )
        
        # Console handler
        if enable_console:
            console_handler = logging.StreamHandler()
            console_handler.setFormatter(formatter)
            logger.addHandler(console_handler)
        
        # File handler
        if log_file:
            log_path = Path(log_file)
            log_path.parent.mkdir(parents=True, exist_ok=True)
            file_handler = logging.FileHandler(log_file)
            file_handler.setFormatter(formatter)
            logger.addHandler(file_handler)
        
        return logger
    
    def log(
        self,
        level: LogLevel,
        message: str,
        extra: Optional[Dict[str, Any]] = None
    ):
        """
        Log a message with structured data
        
        Args:
            level: Log level
            message: Log message
            extra: Additional structured data
        """
        log_data = {
            "service": self.service_name,
            "message": message,
            "timestamp": datetime.now().isoformat()
        }
        
        if extra:
            log_data.update(extra)
        
        # Log based on level
        log_func = getattr(self.logger, level.value.lower())
        log_func(json.dumps(log_data))
    
    def record_metric(
        self,
        name: str,
        value: float,
        tags: Optional[Dict[str, str]] = None
    ):
        """
        Record a metric
        
        Args:
            name: Metric name
            value: Metric value
            tags: Optional tags for the metric
        """
        metric = MetricData(
            name=name,
            value=value,
            tags=tags or {}
        )
        
        if name not in self.metrics:
            self.metrics[name] = []
        
        self.metrics[name].append(metric)
        
        # Log metric
        self.log(
            LogLevel.INFO,
            f"Metric recorded: {name}",
            extra={"metric": metric.to_dict()}
        )
    
    def track_operation(self, operation_name: str):
        """
        Context manager for tracking operation duration
        
        Args:
            operation_name: Name of the operation
            
        Usage:
            with monitor.track_operation("cas_search"):
                # perform operation
                pass
        """
        return OperationTracker(self, operation_name)
    
    def get_metrics_summary(self) -> Dict[str, Any]:
        """
        Get summary of all metrics
        
        Returns:
            Dictionary with metric summaries
        """
        summary = {}
        
        for name, metrics in self.metrics.items():
            values = [m.value for m in metrics]
            summary[name] = {
                "count": len(values),
                "min": min(values) if values else 0,
                "max": max(values) if values else 0,
                "avg": sum(values) / len(values) if values else 0,
                "latest": values[-1] if values else 0
            }
        
        return summary
    
    def get_health_status(self) -> Dict[str, Any]:
        """
        Get health status of the service
        
        Returns:
            Health status dictionary
        """
        uptime = time.time() - self.start_time
        
        return {
            "service": self.service_name,
            "status": "healthy",
            "uptime_seconds": uptime,
            "timestamp": datetime.now().isoformat(),
            "metrics_summary": self.get_metrics_summary()
        }
    
    def log_error(
        self,
        error: Exception,
        context: Optional[Dict[str, Any]] = None
    ):
        """
        Log an error with context
        
        Args:
            error: Exception object
            context: Additional context
        """
        import traceback
        
        error_data = {
            "error_type": type(error).__name__,
            "error_message": str(error),
            "traceback": traceback.format_exc()
        }
        
        if context:
            error_data.update(context)
        
        self.log(
            LogLevel.ERROR,
            f"Error occurred: {str(error)}",
            extra=error_data
        )
    
    def log_rag_query(
        self,
        query: str,
        response: str,
        sources_count: int,
        processing_time: float,
        success: bool = True
    ):
        """
        Log RAG query execution
        
        Args:
            query: User query
            response: Generated response
            sources_count: Number of sources retrieved
            processing_time: Processing time in seconds
            success: Whether the query was successful
        """
        self.log(
            LogLevel.INFO,
            "RAG query executed",
            extra={
                "query_length": len(query),
                "response_length": len(response),
                "sources_count": sources_count,
                "processing_time": processing_time,
                "success": success
            }
        )
        
        # Record metrics
        self.record_metric("rag_query_duration", processing_time)
        self.record_metric("rag_sources_retrieved", sources_count)
    
    def log_cas_search(
        self,
        query: str,
        results_count: int,
        search_time: float,
        vector_store_id: str
    ):
        """
        Log CAS search operation
        
        Args:
            query: Search query
            results_count: Number of results
            search_time: Search time in seconds
            vector_store_id: Vector store ID
        """
        self.log(
            LogLevel.INFO,
            "CAS search executed",
            extra={
                "query_length": len(query),
                "results_count": results_count,
                "search_time": search_time,
                "vector_store_id": vector_store_id
            }
        )
        
        self.record_metric("cas_search_duration", search_time)
        self.record_metric("cas_results_count", results_count)
    
    def log_llm_inference(
        self,
        prompt_length: int,
        response_length: int,
        inference_time: float,
        model_endpoint: str
    ):
        """
        Log LLM inference operation
        
        Args:
            prompt_length: Length of prompt
            response_length: Length of response
            inference_time: Inference time in seconds
            model_endpoint: LLM endpoint
        """
        self.log(
            LogLevel.INFO,
            "LLM inference executed",
            extra={
                "prompt_length": prompt_length,
                "response_length": response_length,
                "inference_time": inference_time,
                "model_endpoint": model_endpoint
            }
        )
        
        self.record_metric("llm_inference_duration", inference_time)
        self.record_metric("llm_response_length", response_length)


class OperationTracker:
    """Context manager for tracking operation duration"""
    
    def __init__(self, monitor: MonitoringService, operation_name: str):
        """
        Initialize operation tracker
        
        Args:
            monitor: Monitoring service
            operation_name: Name of the operation
        """
        self.monitor = monitor
        self.operation_name = operation_name
        self.start_time = None
    
    def __enter__(self):
        """Start tracking"""
        self.start_time = time.time()
        self.monitor.log(
            LogLevel.INFO,
            f"Operation started: {self.operation_name}"
        )
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Stop tracking and record duration"""
        duration = time.time() - self.start_time
        
        if exc_type is None:
            self.monitor.log(
                LogLevel.INFO,
                f"Operation completed: {self.operation_name}",
                extra={"duration": duration}
            )
        else:
            self.monitor.log(
                LogLevel.ERROR,
                f"Operation failed: {self.operation_name}",
                extra={
                    "duration": duration,
                    "error": str(exc_val)
                }
            )
        
        self.monitor.record_metric(
            f"operation_duration_{self.operation_name}",
            duration
        )


# Global monitoring instance
_global_monitor: Optional[MonitoringService] = None


def get_monitor() -> MonitoringService:
    """
    Get global monitoring instance
    
    Returns:
        MonitoringService instance
    """
    global _global_monitor
    
    if _global_monitor is None:
        _global_monitor = MonitoringService()
    
    return _global_monitor


def initialize_monitoring(
    service_name: str = "fusion-agentic-assistance-platform",
    log_level: str = "INFO",
    log_file: Optional[str] = None
) -> MonitoringService:
    """
    Initialize global monitoring service
    
    Args:
        service_name: Name of the service
        log_level: Logging level
        log_file: Path to log file
        
    Returns:
        MonitoringService instance
    """
    global _global_monitor
    
    _global_monitor = MonitoringService(
        service_name=service_name,
        log_level=log_level,
        log_file=log_file
    )
    
    return _global_monitor