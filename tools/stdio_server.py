# ---------------------------------------------------------
# COMPONENT: TOOL SERVER (MCP stdio)
# FILE: tools/stdio_server.py
# PURPOSE: Expose mesh_server MCP tools over stdio for vendor MCP clients (codex CLI)
# ---------------------------------------------------------
import argparse
import os
import sys
import asyncio
import signal

# Add parent directory to path so we can import mesh_server
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from mcp.server.fastmcp import FastMCP

# Ensure DB path is set before importing mesh_server (which reads env)
def ensure_db_path(db_path_arg: str | None):
    if db_path_arg:
        os.environ["ATOMIC_MESH_DB"] = db_path_arg
    if "ATOMIC_MESH_DB" not in os.environ or not os.environ["ATOMIC_MESH_DB"]:
        # Default to mesh.db in current working directory
        os.environ["ATOMIC_MESH_DB"] = os.path.join(os.getcwd(), "mesh.db")


def load_mesh_server():
    # Import mesh_server after env is ready; it creates the mcp instance with registered tools
    import mesh_server
    return mesh_server.mcp  # Return the mcp instance with all tools registered


async def run_server():
    parser = argparse.ArgumentParser(description="MCP stdio tool server for mesh")
    parser.add_argument(
        "--db-path",
        dest="db_path",
        help="Path to mesh.db (defaults to ATOMIC_MESH_DB or ./mesh.db)",
    )
    args = parser.parse_args()

    ensure_db_path(args.db_path)

    # Get the mcp instance from mesh_server (with all tools already registered)
    server = load_mesh_server()

    loop = asyncio.get_running_loop()
    stop_event = asyncio.Event()

    def handle_sigint():
        try:
            stop_event.set()
        except Exception:
            pass

    try:
        loop.add_signal_handler(signal.SIGINT, handle_sigint)
    except NotImplementedError:
        # Windows may not support add_signal_handler for SIGINT; ignore
        pass

    await server.run_stdio_async()


if __name__ == "__main__":
    asyncio.run(run_server())
