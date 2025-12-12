#!/bin/bash
while true; do
    clear
    echo "=== ATOMIC MESH DASHBOARD ==="
    echo "Time: $(date)"
    echo "-----------------------------"
    uvx mcp-cli call dashboard --config-file server_config.json --server atomic-mesh
    sleep 2
done
