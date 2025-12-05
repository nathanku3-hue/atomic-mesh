# 🚀 Atomic Mesh v7.4 - Golden Master

[![Version](https://img.shields.io/badge/version-7.4-blue.svg)](https://github.com/nathanku/atomic-mesh)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Security](https://img.shields.io/badge/security-hardened-brightgreen.svg)](#security-features)

> **Autonomous Development Orchestration System**
>
> A self-healing, multi-agent system that orchestrates AI coding assistants with built-in quality gates, conflict resolution, and file safety.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ATOMIC MESH v7.4 - SYSTEM ARCHITECTURE                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   [USER INPUT]                                                              │
│        │                                                                    │
│        ▼                                                                    │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │              🧠 SEMANTIC ROUTER (router.py)                         │   │
│   │   ┌─────────────────┐    ┌─────────────────────────────────────┐    │   │
│   │   │   FAST PATH     │    │         SMART PATH (LLM)            │    │   │
│   │   │  30+ regex pats │ OR │  3s timeout + graceful fallback     │    │   │
│   │   │  Confidence: 1.0│    │  Confidence: 0.8-0.95               │    │   │
│   │   └────────┬────────┘    └─────────────────┬───────────────────┘    │   │
│   │            └───────────────┬───────────────┘                        │   │
│   │                            ▼                                        │   │
│   │                  INTENT CLASSIFICATION                              │   │
│   │   EXECUTE | QUEUE_OPS | CONTEXT_SET | AGENT_DIRECT | QUERY | CHAT   │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│        │                                                                    │
│        ├────────────────┬────────────────┬────────────────┐                 │
│        ▼                ▼                ▼                ▼                 │
│   ┌─────────┐      ┌─────────┐      ┌─────────┐      ┌─────────┐            │
│   │ WORKERS │◀────▶│ AUDITOR │      │LIBRARIAN│      │ DATABASE│            │
│   │ (BE/FE) │      │ (QA)    │      │ (Files) │      │ (State) │            │
│   │         │      │ 3-Tier  │      │Git Guard│      │   WAL   │            │
│   └─────────┘      └─────────┘      └─────────┘      └─────────┘            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## ✨ Features

### 🧠 Semantic Router
- **Fast Path**: 30+ regex patterns for instant command recognition
- **Smart Path**: LLM-based classification with 3-second timeout
- **Pronoun Resolution**: "Skip it" → resolves to last shown task
- **Safety Interlock**: Destructive commands require `--confirm`

### 🔍 Auditor Agent
- **3-Tier Strictness**: Critical → Normal → Relaxed
- **Security Tripwire**: Blocks dangerous patterns (eval, injection, etc.)
- **Context Flush**: Resets agent context on user override

### 📚 Librarian Agent
- **Git Guard**: Blocks operations on uncommitted files
- **Secret Scanning**: Detects API keys, passwords, tokens
- **Reference Checking**: Prevents breaking imports
- **Restore Points**: Automatic backup before file operations

### 🔧 Self-Healing Features
- **Active File Lock**: Prevents conflicts between agents
- **Port Cleanup**: Kills zombie dev servers automatically
- **Deep Import Refactor**: Fixes imports when moving files
- **JIT Context Injection**: Always uses fresh decisions

---

## 🚀 Quick Start

### Prerequisites
- Python 3.10+
- PowerShell 5.1+ (Windows) or pwsh (Cross-platform)
- Git

### Installation

```bash
# 1. Clone the repository
git clone https://github.com/nathanku/atomic-mesh.git
cd atomic-mesh

# 2. Install Python dependencies
pip install -r requirements.txt

# 3. Copy environment template
cp config/.env.example .env
# Edit .env with your settings

# 4. Start the MCP server
python src/mesh_server.py

# 5. In another terminal, start the control panel
pwsh src/control_panel.ps1
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ATOMIC_MESH_DB` | `mesh.db` | Path to SQLite database |
| `ATOMIC_MESH_DOCS` | `./docs` | Path to docs directory |
| `ROUTER_TIMEOUT` | `3.0` | LLM timeout in seconds |
| `OPENAI_API_KEY` | - | API key for Smart Path (optional) |

---

## 📖 Commands

### Hotkeys (Control Panel)
| Key | Action |
|-----|--------|
| `C` | Continue/Execute next task |
| `1` | Stream Backend Worker |
| `2` | Stream Frontend Worker |
| `A` | Open Auditor panel |
| `L` | Open Librarian panel |
| `M` | Toggle mode |
| `Q` | Quit |

### CLI Commands
```bash
# Task Management
post backend Fix auth bug     # Add task
skip 5                        # Skip task #5
reset 3                       # Reset task #3
drop 7                        # Delete task #7
nuke --confirm                # Clear all pending

# Context
decision: Use JWT tokens      # Add decision
blocker: API is down          # Add blocker
note: Remember to test        # Add note

# Agents
lib scan                      # Librarian scan
auditor check                 # Auditor status

# Queries
status                        # System status
task 5                        # Task details
plan                          # Show roadmap
```

---

## 🛡️ Security Features

All 12 security issues identified and fixed:

| Issue | Fix |
|-------|-----|
| Shell Injection | List arguments instead of `shell=True` |
| Bare Exceptions | Specific exception handling |
| Hardcoded DB Path | Environment variable |
| Task ID Validation | Input bounds checking |
| ThreadPool Leak | Destructor cleanup |
| Port Range | Validation (3000-10000 only) |
| Log Sanitization | Credential masking |
| SQL Injection (PS) | Pattern validation |
| Silent Catches | Error reporting |
| Health Check | Monitoring endpoint |

---

## 📁 Project Structure

```
atomic-mesh/
├── src/
│   ├── mesh_server.py       # MCP server (1,400+ lines)
│   ├── router.py            # Semantic router (710+ lines)
│   ├── librarian_tools.py   # File management (900+ lines)
│   ├── control_panel.ps1    # CLI dashboard
│   ├── worker.ps1           # Worker agent
│   └── cleanup_legacy.py    # Deployment helper
├── prompts/
│   ├── auditor_prompt.md    # Auditor system prompt
│   └── librarian_prompt.md  # Librarian system prompt
├── launcher/
│   └── mesh-up.ps1          # Multi-window launcher
├── config/
│   └── .env.example         # Configuration template
├── docs/
│   ├── ARCHITECTURE.md
│   ├── SECURITY_AUDIT.md
│   └── API_REFERENCE.md
├── requirements.txt
├── .gitignore
└── README.md
```

---

## 🔌 MCP Tools Reference

### Task Management
- `add_task(type, desc, deps, priority)`
- `list_tasks(status, type, limit)`
- `get_task(task_id)`
- `complete_task(task_id, output, files_changed)`
- `fail_task(task_id, error)`

### Router
- `route_input(user_input)`
- `execute_routed_intent(user_input)`
- `update_task_context(task_id, type)`

### Librarian
- `librarian_scan(project_path)`
- `librarian_approve(manifest_id)`
- `librarian_execute(manifest_id)`
- `check_secrets(file_path)`
- `check_references(file_path)`

### Auditor
- `determine_strictness(files, desc, diff)`
- `record_audit(task_id, action, reason)`
- `flush_auditor_context(task_id)`

### System
- `system_health_check()`
- `check_port_available(port)`
- `kill_process_on_port(port)`
- `cleanup_dev_environment()`

---

## 📊 Database Schema

```sql
-- Core Tables
tasks (id, type, desc, status, priority, files_changed, ...)
decisions (id, priority, question, answer, status)
audit_log (id, task_id, action, strictness, reason)
librarian_ops (id, manifest_id, operation, status)
restore_points (id, operation_id, original_path, backup_path)
session_context (key, value, updated_at)
route_log (id, input, intent, action, confidence, source)
```

---

## 🏆 Version History

- **v7.4** - Golden Master (Security Hardened)
- **v7.3** - Semantic Router + Conflict Patches
- **v7.2** - Librarian Agent
- **v7.1** - Auditor Integration
- **v7.0** - Initial MCP Architecture

---

## 📄 License

MIT License - See [LICENSE](LICENSE) for details.

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests
5. Submit a pull request

---

**Built with ❤️ for autonomous development**
