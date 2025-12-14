# SNIPPET: retry_with_backoff
# LANG: python
# TAGS: retry, backoff, http, resilience
# INTENT: Standard retry loop with exponential backoff + jitter
# UPDATED: 2025-12-12

import time
import random

def retry_with_backoff(func, max_retries=3, base_delay=1.0):
    """
    Retry a function with exponential backoff and jitter.

    Args:
        func: Callable to retry
        max_retries: Maximum number of attempts
        base_delay: Initial delay in seconds

    Returns:
        Result of func() if successful

    Raises:
        Last exception if all retries exhausted
    """
    for attempt in range(max_retries):
        try:
            return func()
        except Exception as e:
            if attempt == max_retries - 1:
                raise
            delay = base_delay * (2 ** attempt) + random.uniform(0, 1)
            time.sleep(delay)
