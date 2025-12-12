# Pattern Library
*Golden paths and reusable solutions mined from incidents.*

## Pattern: UTC Timestamps
**Context:** Timezone bugs are frequent.
**Solution:** Always use `datetime.now(timezone.utc)`.
**Linked Rule:** DR-ARCH-004
