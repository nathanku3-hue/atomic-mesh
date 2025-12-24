# Lane: Data

## MUST
- Validate schema before processing
- Handle NULL/missing values explicitly
- Use transactions for multi-step operations
- Log data pipeline stages
- Document data transformations

## MUST NOT
- Silently drop invalid records
- Assume data types without validation
- Ignore encoding issues (UTF-8)
- Process without backup strategy

## Patterns
```python
# ✅ Good: Schema validation
def validate_record(record):
    required = ['id', 'name', 'email']
    for field in required:
        if field not in record or record[field] is None:
            raise ValueError(f"Missing required field: {field}")

# ✅ Good: Transaction safety
with conn:
    conn.execute("INSERT INTO users ...")
    conn.execute("INSERT INTO audit_log ...")
# Auto-commit or rollback

# ❌ Bad: Silent failure
records = [r for r in data if r.get('id')]  # Silently drops!
```

## Acceptance Checks
- [ ] Validation: Schema enforced on input
- [ ] Nulls: Explicitly handled
- [ ] Transactions: Multi-step ops are atomic
- [ ] Logging: Pipeline stages visible
