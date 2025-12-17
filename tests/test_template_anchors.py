#!/usr/bin/env python3
"""
Smoke test: Verify starter templates produce extractable anchors.

This test protects against template edits that accidentally remove
anchor patterns needed for plan extraction.

Run: python tests/test_template_anchors.py
"""
import os
import sys

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from mesh_server import (
    _extract_user_stories,
    _extract_api_endpoints,
    _extract_data_entities,
    _extract_decisions,
    _context_is_sufficient,
    build_plan_from_context_structured,
    _assess_plan_quality,
)

TEMPLATE_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "library", "templates"
)

# Minimum anchor thresholds for templates
MIN_USER_STORIES = 3
MIN_API_ENDPOINTS = 3
MIN_DATA_ENTITIES = 1
MIN_DECISIONS = 1  # non-INIT
MIN_PLAN_TASKS = 10
MIN_PLAN_STREAMS = 3


def load_template(name: str) -> str:
    """Load a template file."""
    path = os.path.join(TEMPLATE_DIR, f"{name}.template.md")
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def test_prd_template_anchors():
    """PRD template must produce extractable user stories."""
    prd = load_template("PRD")
    stories = _extract_user_stories(prd)

    assert len(stories) >= MIN_USER_STORIES, (
        f"PRD template must have >= {MIN_USER_STORIES} extractable user stories, "
        f"got {len(stories)}. Check that US-XX format is preserved."
    )

    # Verify stories have real content (not placeholders)
    for story in stories:
        assert "[user]" not in story["desc"].lower(), (
            f"Story {story['id']} still has placeholder [user]"
        )
        assert "[capability]" not in story["desc"].lower(), (
            f"Story {story['id']} still has placeholder [capability]"
        )

    print(f"✓ PRD: {len(stories)} user stories extracted")
    return stories


def test_spec_template_anchors():
    """SPEC template must produce extractable endpoints and entities."""
    spec = load_template("SPEC")

    endpoints = _extract_api_endpoints(spec)
    assert len(endpoints) >= MIN_API_ENDPOINTS, (
        f"SPEC template must have >= {MIN_API_ENDPOINTS} extractable API endpoints, "
        f"got {len(endpoints)}. Check table format or **Function** format."
    )

    entities = _extract_data_entities(spec)
    assert len(entities) >= MIN_DATA_ENTITIES, (
        f"SPEC template must have >= {MIN_DATA_ENTITIES} extractable data entities, "
        f"got {len(entities)}. Check Entity table or code block format."
    )

    # Verify entities have real names (not placeholders)
    for entity in entities:
        assert "[" not in entity["name"], (
            f"Entity {entity['name']} looks like a placeholder"
        )

    print(f"✓ SPEC: {len(endpoints)} endpoints, {len(entities)} entities extracted")
    return endpoints, entities


def test_decision_log_template_anchors():
    """DECISION_LOG template must produce extractable non-INIT decisions."""
    dec_log = load_template("DECISION_LOG")
    decisions = _extract_decisions(dec_log)

    assert len(decisions) >= MIN_DECISIONS, (
        f"DECISION_LOG template must have >= {MIN_DECISIONS} extractable non-INIT decisions, "
        f"got {len(decisions)}. Add ARCH/API/DATA/etc decisions to the table."
    )

    # Verify no INIT decisions slipped through
    for dec in decisions:
        assert dec["type"] != "INIT", (
            f"Decision {dec['id']} is INIT type - should be filtered"
        )

    print(f"✓ DECISION_LOG: {len(decisions)} non-INIT decisions extracted")
    return decisions


def test_templates_pass_sufficiency_gate():
    """Combined templates must pass the sufficiency gate."""
    stories = test_prd_template_anchors()
    endpoints, entities = test_spec_template_anchors()
    decisions = test_decision_log_template_anchors()

    context = {
        "project_name": "Template Test",
        "user_stories": stories,
        "api_endpoints": endpoints,
        "data_entities": entities,
        "decisions": decisions,
        "domain_nouns": [],
        "debug": {
            "counts": {
                "user_stories": len(stories),
                "api_endpoints": len(endpoints),
                "data_entities": len(entities),
                "decisions": len(decisions)
            }
        }
    }

    is_sufficient, reasons = _context_is_sufficient(context)
    assert is_sufficient, (
        "Templates must produce sufficient context for plan generation. "
        f"Got: stories={len(stories)}, endpoints={len(endpoints)}, "
        f"entities={len(entities)}, decisions={len(decisions)}. "
        f"Reasons: {reasons}"
    )

    print("✓ Sufficiency gate: PASSED")
    return context


def test_templates_produce_quality_plan():
    """Templates must produce a plan that passes quality gate."""
    context = test_templates_pass_sufficiency_gate()

    plan = build_plan_from_context_structured(context)
    quality = _assess_plan_quality(plan, context)

    total_tasks = sum(len(s.get("tasks", [])) for s in plan.get("streams", []))
    stream_count = len(plan.get("streams", []))

    assert total_tasks >= MIN_PLAN_TASKS, (
        f"Plan must have >= {MIN_PLAN_TASKS} tasks, got {total_tasks}. "
        "Add more anchors to templates."
    )

    assert stream_count >= MIN_PLAN_STREAMS, (
        f"Plan must have >= {MIN_PLAN_STREAMS} streams, got {stream_count}. "
        "Ensure templates cover Backend, Frontend, QA, Ops, Docs."
    )

    assert quality["level"] in ("OK", "THIN"), (
        f"Plan quality must be OK or THIN, got {quality['level']} ({quality['reason']})"
    )

    print(f"✓ Plan quality: {quality['level']} ({total_tasks} tasks, {stream_count} streams)")

    if quality["level"] == "OK":
        print("\n=== ALL TEMPLATE ANCHOR TESTS PASSED ===")
    else:
        print(f"\n=== TESTS PASSED (plan is THIN: {quality['reason']}) ===")


if __name__ == "__main__":
    try:
        test_templates_produce_quality_plan()
        sys.exit(0)
    except AssertionError as e:
        print(f"\n✗ FAILED: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"\n✗ ERROR: {e}")
        sys.exit(1)
