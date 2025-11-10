"""
Cache Service - In-memory caching with TTL support
"""

import time
import logging
from typing import Any, Optional, Dict
from datetime import datetime, timedelta
from threading import Lock


class CacheEntry:
    """Represents a cached entry with TTL"""

    def __init__(self, value: Any, ttl_seconds: int = 300):
        self.value = value
        self.created_at = time.time()
        self.ttl_seconds = ttl_seconds

    def is_expired(self) -> bool:
        """Check if entry has expired"""
        return (time.time() - self.created_at) > self.ttl_seconds

    def get_age(self) -> float:
        """Get age of entry in seconds"""
        return time.time() - self.created_at


class CacheService:
    """
    In-memory cache service with TTL and statistics
    """

    def __init__(self, config: Dict, logger: Optional[logging.Logger] = None):
        self.config = config
        self.logger = logger or logging.getLogger(__name__)
        self.cache: Dict[str, CacheEntry] = {}
        self.lock = Lock()

        # Configuration
        self.default_ttl = config.get('cache', {}).get('default_ttl', 300)
        self.max_entries = config.get('cache', {}).get('max_entries', 1000)

        # Statistics
        self.hits = 0
        self.misses = 0
        self.evictions = 0

        self.logger.info(f"Cache service initialized (TTL: {self.default_ttl}s, Max: {self.max_entries})")

    def get(self, key: str) -> Optional[Any]:
        """
        Get value from cache

        Args:
            key: Cache key

        Returns:
            Cached value or None if not found/expired
        """
        with self.lock:
            entry = self.cache.get(key)

            if entry is None:
                self.misses += 1
                self.logger.debug(f"Cache miss: {key}")
                return None

            if entry.is_expired():
                self.logger.debug(f"Cache expired: {key} (age: {entry.get_age():.1f}s)")
                del self.cache[key]
                self.misses += 1
                return None

            self.hits += 1
            self.logger.debug(f"Cache hit: {key} (age: {entry.get_age():.1f}s)")
            return entry.value

    def set(self, key: str, value: Any, ttl_seconds: Optional[int] = None):
        """
        Set value in cache

        Args:
            key: Cache key
            value: Value to cache
            ttl_seconds: Time to live in seconds (default: from config)
        """
        with self.lock:
            # Check if we need to evict entries
            if len(self.cache) >= self.max_entries:
                self._evict_oldest()

            ttl = ttl_seconds if ttl_seconds is not None else self.default_ttl
            self.cache[key] = CacheEntry(value, ttl)
            self.logger.debug(f"Cache set: {key} (TTL: {ttl}s)")

    def delete(self, key: str) -> bool:
        """
        Delete entry from cache

        Args:
            key: Cache key

        Returns:
            True if deleted, False if not found
        """
        with self.lock:
            if key in self.cache:
                del self.cache[key]
                self.logger.debug(f"Cache delete: {key}")
                return True
            return False

    def clear(self):
        """Clear all cache entries"""
        with self.lock:
            count = len(self.cache)
            self.cache.clear()
            self.logger.info(f"Cache cleared ({count} entries)")

    def clear_pattern(self, pattern: str):
        """
        Clear entries matching pattern

        Args:
            pattern: Pattern to match (supports * wildcard)
        """
        with self.lock:
            import fnmatch
            keys_to_delete = [
                key for key in self.cache.keys()
                if fnmatch.fnmatch(key, pattern)
            ]

            for key in keys_to_delete:
                del self.cache[key]

            if keys_to_delete:
                self.logger.info(f"Cleared {len(keys_to_delete)} entries matching '{pattern}'")

    def _evict_oldest(self):
        """Evict oldest entry from cache"""
        if not self.cache:
            return

        oldest_key = min(self.cache.items(), key=lambda x: x[1].created_at)[0]
        del self.cache[oldest_key]
        self.evictions += 1
        self.logger.debug(f"Evicted oldest entry: {oldest_key}")

    def cleanup_expired(self):
        """Remove all expired entries"""
        with self.lock:
            expired_keys = [
                key for key, entry in self.cache.items()
                if entry.is_expired()
            ]

            for key in expired_keys:
                del self.cache[key]

            if expired_keys:
                self.logger.info(f"Cleaned up {len(expired_keys)} expired entries")

    def get_statistics(self) -> Dict[str, Any]:
        """Get cache statistics"""
        with self.lock:
            total_requests = self.hits + self.misses
            hit_rate = (self.hits / total_requests * 100) if total_requests > 0 else 0

            return {
                'entries': len(self.cache),
                'hits': self.hits,
                'misses': self.misses,
                'hit_rate_percent': round(hit_rate, 2),
                'evictions': self.evictions,
                'max_entries': self.max_entries
            }

    def get_info(self, key: str) -> Optional[Dict[str, Any]]:
        """Get information about a cache entry"""
        with self.lock:
            entry = self.cache.get(key)
            if entry:
                return {
                    'age_seconds': entry.get_age(),
                    'ttl_seconds': entry.ttl_seconds,
                    'expires_in': entry.ttl_seconds - entry.get_age(),
                    'is_expired': entry.is_expired()
                }
            return None