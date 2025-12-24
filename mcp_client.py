# ---------------------------------------------------------
# COMPONENT: INTELLIGENCE (sys:ai_client)
# FILE: mcp_client.py
# MAPPING: MCP Protocol Bridge to mesh_server.py
# EXPORTS: run_tool
# CONSUMES: sys:scheduler (via stdio)
# VERSION: v22.0
# ---------------------------------------------------------
import sys
import asyncio
import json
import os
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

async def run_tool(tool_name, arguments):
    # Start the server process
    # v23.1: Pass current environment so ATOMIC_MESH_DB is inherited
    server_params = StdioServerParameters(
        command="python",
        args=["mesh_server.py"],
        env=dict(os.environ)  # Inherit all env vars including ATOMIC_MESH_DB
    )

    async with stdio_client(server_params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            
            # Call the tool
            result = await session.call_tool(tool_name, arguments)
            
            # Output the result content
            if result.content:
                # Assuming the first content block is what we want
                print(result.content[0].text)
            else:
                print("")

import base64

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python mcp_client.py <tool_name> <json_arguments> [--base64]")
        sys.exit(1)

    tool_name = sys.argv[1]
    arg_str = sys.argv[2]
    
    if len(sys.argv) > 3 and sys.argv[3] == "--base64":
        try:
            arg_str = base64.b64decode(arg_str).decode('utf-8')
        except Exception as e:
            print(f"Error decoding Base64: {e}", file=sys.stderr)
            sys.exit(1)

    try:
        arguments = json.loads(arg_str)
    except json.JSONDecodeError:
        print(f"Error: Invalid JSON arguments: {arg_str}")
        sys.exit(1)
    
    try:
        asyncio.run(run_tool(tool_name, arguments))
    except Exception as e:
        # Print error to stderr so it doesn't pollute stdout (which is captured)
        print(f"Error running tool: {e}", file=sys.stderr)
        sys.exit(1)
