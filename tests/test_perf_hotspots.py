"""
P0 performance regressions: provenance scan, log tailing, and secret scanning.

These tests validate the new streaming algorithms without changing outputs.
"""
import json
import os
import sys

import pytest

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


@pytest.fixture
def mesh_module(tmp_path, monkeypatch):
    """Reload mesh_server with an isolated workspace."""
    base_dir = tmp_path
    monkeypatch.setenv("MESH_BASE_DIR", str(base_dir))
    monkeypatch.setenv("ATOMIC_MESH_DB", str(base_dir / "mesh.db"))
    monkeypatch.chdir(base_dir)

    # Force reload to pick up new env vars and paths
    if "mesh_server" in sys.modules:
        del sys.modules["mesh_server"]
    import importlib
    import mesh_server

    return importlib.reload(mesh_server)


def test_generate_provenance_report_streaming(mesh_module, tmp_path):
    """Provenance scan should de-dup lines and emit expected line numbers."""
    src_dir = tmp_path / "src"
    src_dir.mkdir(parents=True, exist_ok=True)

    a_path = src_dir / "a.py"
    a_path.write_text(
        "# Implements [FOO-1]\n"
        "# Implements [foo-1, BAR-2]\n",
        encoding="utf-8",
    )
    b_path = src_dir / "b.js"
    b_path.write_text("// Implements [BAR-2]\n", encoding="utf-8")

    result = json.loads(mesh_module.generate_provenance_report())

    # Full provenance (with sources) is persisted to provenance.json
    prov_path = mesh_module.get_state_path("provenance.json")
    with open(prov_path, "r", encoding="utf-8") as f:
        provenance = json.load(f)

    rel_a = os.path.join("src", "a.py")
    rel_b = os.path.join("src", "b.js")

    foo_lines = set(provenance["sources"]["FOO-1"]["lines"])
    bar_lines = set(provenance["sources"]["BAR-2"]["lines"])

    assert foo_lines == {f"{rel_a}:1", f"{rel_a}:2"}
    assert bar_lines == {f"{rel_a}:2", f"{rel_b}:1"}
    # No orphan entries when coverage.json is absent
    assert provenance["orphans"] == []
    assert result["status"] == "COMPLETE"


def test_tail_text_lines_returns_last_lines(mesh_module, tmp_path):
    """Tail helper returns the last N lines without error."""
    log_dir = tmp_path / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / "mesh.log"
    lines = [f"line-{i}" for i in range(50)]
    log_path.write_text("\n".join(lines), encoding="utf-8")

    tail = mesh_module._tail_text_lines(str(log_path), max_lines=5, encoding="utf-8")
    assert tail == lines[-5:]


def test_scan_for_secrets_short_circuits(tmp_path):
    """Secret scan should block and report when a key is present."""
    from librarian_tools import scan_for_secrets

    secret_path = tmp_path / "secret.txt"
    payload = "\n".join(["noise"] * 100 + ["api_key = 'abc123'"] + ["more"] * 100)
    secret_path.write_text(payload, encoding="utf-8")

    result = scan_for_secrets(str(secret_path))
    assert result["blocked"] is True
    assert result["secrets_found"], "Expected at least one secret hit"
    types = {entry["type"] for entry in result["secrets_found"]}
    assert "API Key" in types


def test_check_file_references_short_circuits(monkeypatch, tmp_path):
    """check_file_references should stop reading a file once both patterns are hit."""
    from librarian_tools import check_file_references

    target = tmp_path / "target.py"
    target.write_text("print('ok')", encoding="utf-8")

    ref_file = tmp_path / "ref.py"
    # First two lines contain both import and literal hits; further reads should not occur.
    ref_lines = ["import target\n", 'path = "target.py"\n']
    ref_file.write_text("".join(ref_lines) + "SHOULD_NOT_BE_READ\n" * 1000, encoding="utf-8")

    # Fail if the scanner reads beyond the first two lines
    class FailAfterTwo:
        def __init__(self, lines):
            self.lines = lines
            self.idx = 0

        def __iter__(self):
            return self

        def __next__(self):
            if self.idx >= len(self.lines):
                raise AssertionError("Scanner read past early matches")
            line = self.lines[self.idx]
            self.idx += 1
            return line

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def read(self, *_args, **_kwargs):
            # Should not be called; iterator is used
            raise AssertionError("Unexpected read() call")

    import builtins

    real_open = builtins.open

    def fake_open(path, mode="r", *args, **kwargs):
        if os.path.abspath(path) == os.path.abspath(ref_file):
            if "b" in mode:
                return real_open(path, mode, *args, **kwargs)
            return FailAfterTwo(ref_lines)
        return real_open(path, mode, *args, **kwargs)

    monkeypatch.setattr(builtins, "open", fake_open)

    result = check_file_references(str(target), str(tmp_path))
    assert ref_file.as_posix() in [p.replace("\\", "/") for p in result["import_refs"]]
    assert any(ref_file.as_posix() in r["file"].replace("\\", "/") for r in result["literal_refs"])
    assert result["total_refs"] == 2


def test_get_recently_modified_files_cache(monkeypatch, tmp_path):
    """get_recently_modified_files should honor a short TTL cache."""
    import librarian_tools

    base = tmp_path / "proj"
    base.mkdir(parents=True)
    f1 = base / "a.txt"
    f1.write_text("a", encoding="utf-8")

    # Force deterministic time and clear cache
    t = {"now": 1000.0}

    def fake_time():
        return t["now"]

    monkeypatch.setattr(librarian_tools.time, "time", fake_time)
    monkeypatch.setattr(librarian_tools, "_recent_cache", {})
    monkeypatch.setattr(librarian_tools, "_RECENT_CACHE_TTL", 10)

    scan_calls = {"count": 0}
    real_scandir = librarian_tools.os.scandir

    def tracking_scandir(path):
        scan_calls["count"] += 1
        return real_scandir(path)

    monkeypatch.setattr(librarian_tools.os, "scandir", tracking_scandir)

    first = set(librarian_tools.get_recently_modified_files(str(base), minutes=5))
    assert f1.as_posix() in [p.replace("\\", "/") for p in first]
    first_calls = scan_calls["count"]

    # Within TTL: should hit cache (no additional scandir calls)
    second = set(librarian_tools.get_recently_modified_files(str(base), minutes=5))
    assert second == first
    assert scan_calls["count"] == first_calls

    # After TTL expiry: should rescan
    t["now"] += 11
    third = set(librarian_tools.get_recently_modified_files(str(base), minutes=5))
    assert third == first
    assert scan_calls["count"] > first_calls
