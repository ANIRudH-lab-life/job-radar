#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# JobRadar — Smart Setup Script
# Checks what exists before downloading anything. Safe to re-run.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# Resolve SCRIPT_DIR robustly — works both when run as a file and when piped
# via `curl ... | bash` (where BASH_SOURCE may be unset).
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    # Piped execution: use current dir if it looks like the repo, else clone.
    if [ -f "./requirements.txt" ] && [ -f "./setup.sh" ]; then
        SCRIPT_DIR="$(pwd)"
    else
        INSTALL_DIR="${HOME}/job-radar"
        if [ ! -d "$INSTALL_DIR/.git" ]; then
            echo "  Cloning JobRadar into $INSTALL_DIR ..."
            git clone https://github.com/ANIRudH-lab-life/job-radar.git "$INSTALL_DIR"
        fi
        cd "$INSTALL_DIR"
        SCRIPT_DIR="$INSTALL_DIR"
    fi
fi
VENV_DIR="$SCRIPT_DIR/.venv"
BIN_DIR="$SCRIPT_DIR/bin"
MODEL_DIR="$SCRIPT_DIR/models"
LLAMA_BIN="$BIN_DIR/llama-server"
MODEL_FILE="$MODEL_DIR/qwen3-1.7b-q4_k_m.gguf"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
skip() { echo -e "  ${YELLOW}→${NC} $1 ${YELLOW}(already exists)${NC}"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
info() { echo -e "${CYAN}$1${NC}"; }

# ── Step 1: Check Python ────────────────────────────────────────────────────
info "── Step 1/5: Python ──"
if command -v python3 &>/dev/null; then
    PY_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    PY_MAJOR=$(echo "$PY_VER" | cut -d. -f1)
    PY_MINOR=$(echo "$PY_VER" | cut -d. -f2)
    if [ "$PY_MAJOR" -gt 3 ] || { [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -ge 9 ]; }; then
        ok "Python $PY_VER found"
    else
        fail "Python 3.9+ required (found $PY_VER)"
        exit 1
    fi
else
    fail "Python3 not found. Install it: https://python.org"
    exit 1
fi

# ── Step 2: Python venv + pip packages ──────────────────────────────────────
info "── Step 2/5: Python packages ──"
# Recreate venv if it exists but is incomplete (missing activate/pip/python)
if [ -d "$VENV_DIR" ] && [ ! -f "$VENV_DIR/bin/activate" -o ! -x "$VENV_DIR/bin/python" ]; then
    warn "Existing virtual environment is incomplete — recreating..."
    rm -rf "$VENV_DIR"
fi

if [ -d "$VENV_DIR" ]; then
    skip "Virtual environment at $VENV_DIR"
else
    info "  Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
    # Ensure pip is available (some systems ship venv without pip)
    if [ ! -x "$VENV_DIR/bin/pip" ]; then
        "$VENV_DIR/bin/python" -m ensurepip --upgrade >/dev/null 2>&1 || true
    fi
    ok "Virtual environment created"
fi

# Activate if possible; otherwise use the venv interpreter directly
if [ -f "$VENV_DIR/bin/activate" ]; then
    # shellcheck source=/dev/null
    source "$VENV_DIR/bin/activate"
fi
VENV_PYTHON="$VENV_DIR/bin/python"
if [ ! -x "$VENV_PYTHON" ]; then
    VENV_PYTHON="python3"
fi

# Check if packages are installed
MISSING_PIPS=()
for pkg in rich yaml requests bs4 pytest; do
    if ! "$VENV_PYTHON" -c "import $pkg" &>/dev/null 2>&1; then
        MISSING_PIPS+=("$pkg")
    fi
done

if [ ${#MISSING_PIPS[@]} -eq 0 ]; then
    skip "Core Python packages already installed"
else
    info "  Installing ${#MISSING_PIPS[@]} missing package(s)..."
    "$VENV_PYTHON" -m pip install -q -r "$SCRIPT_DIR/requirements.txt"
    ok "Core packages installed"
fi

# Dashboard packages
MISSING_DASH=()
for pkg in fastapi uvicorn pydantic; do
    if ! "$VENV_PYTHON" -c "import $pkg" &>/dev/null 2>&1; then
        MISSING_DASH+=("$pkg")
    fi
done

if [ ${#MISSING_DASH[@]} -eq 0 ]; then
    skip "Dashboard packages already installed"
else
    info "  Installing ${#MISSING_DASH[@]} missing dashboard package(s)..."
    "$VENV_PYTHON" -m pip install -q -r "$SCRIPT_DIR/dashboard/requirements.txt"
    ok "Dashboard packages installed"
fi

# ── Detect OS ────────────────────────────────────────────────────────────────
OS="$(uname -s)"
ARCH="$(uname -m)"
info "  Detected: $OS $ARCH"

# ── Step 3: LLM Backend (Ollama vs llama.cpp) ──────────────────────────────
info "── Step 3/5: LLM Backend ──"
echo ""
echo -e "${CYAN}  Which LLM backend do you want?${NC}"
echo -e "    1) Ollama (recommended) — easy setup, auto-manages models"
echo -e "    2) llama.cpp (faster)    — raw performance, manual model download"
echo ""

LLM_CHOICE=""
while [ "$LLM_CHOICE" != "1" ] && [ "$LLM_CHOICE" != "2" ]; do
    if [ -t 0 ]; then
        read -r -p "  Enter 1 or 2 [1]: " LLM_CHOICE || LLM_CHOICE="1"
    else
        # Non-interactive (piped) run: default to Ollama
        LLM_CHOICE="1"
    fi
    if [ -z "$LLM_CHOICE" ]; then LLM_CHOICE="1"; fi
    if [ "$LLM_CHOICE" != "1" ] && [ "$LLM_CHOICE" != "2" ]; then
        warn "Please enter 1 or 2"
    fi
done

USE_OLLAMA=false
if [ "$LLM_CHOICE" = "1" ]; then
    USE_OLLAMA=true
fi

if $USE_OLLAMA; then
    # ── Ollama path ────────────────────────────────────────────────────────
    info "  Setting up Ollama..."

    # Check if Ollama is installed
    OLLAMA_FOUND=false
    if command -v ollama &>/dev/null; then
        OLLAMA_FOUND=true
        OLLAMA_VER=$(ollama --version 2>/dev/null || echo "installed")
        ok "Ollama found: $OLLAMA_VER"
    fi

    if ! $OLLAMA_FOUND; then
        warn "Ollama not found. Install it from: https://ollama.com"
        warn "  Then re-run this script."
        warn ""
        warn "  Falling back to llama.cpp instead..."
        USE_OLLAMA=false
    fi
fi

if $USE_OLLAMA; then
    # Pull the model into Ollama
    OLLAMA_MODEL="qwen3:1.7b"
    info "  Checking Ollama model ($OLLAMA_MODEL)..."

    # Check if model is already pulled
    MODEL_LIST=$(ollama list 2>/dev/null || echo "")
    if echo "$MODEL_LIST" | grep -q "qwen3:1\.7b"; then
        skip "Ollama model $OLLAMA_MODEL already available"
    else
        info "  Pulling $OLLAMA_MODEL (~1.1 GB) — this may take a minute..."
        if ollama pull "$OLLAMA_MODEL"; then
            ok "Ollama model $OLLAMA_MODEL ready"
        else
            fail "Failed to pull Ollama model"
            warn "  Try manually: ollama pull $OLLAMA_MODEL"
        fi
    fi

    # Check if Ollama server is already running
    OLLAMA_RUNNING=false
    if curl -s http://localhost:11434/api/tags &>/dev/null; then
        OLLAMA_RUNNING=true
    fi

    if ! $OLLAMA_RUNNING; then
        info "  Starting Ollama server..."
        ollama serve &>/dev/null &
        sleep 3
        if curl -s http://localhost:11434/api/tags &>/dev/null; then
            ok "Ollama server started on http://localhost:11434"
        else
            warn "Ollama server started — may need a moment to be ready"
        fi
    else
        ok "Ollama server already running on http://localhost:11434"
    fi
else
    # ── llama.cpp path ─────────────────────────────────────────────────────
    mkdir -p "$BIN_DIR"

    # Check if llama-server is already available
    if [ -x "$LLAMA_BIN" ]; then
        skip "llama-server at $LLAMA_BIN"
    elif command -v llama-server &>/dev/null; then
        LLAMA_BIN="$(which llama-server)"
        skip "llama-server found at $LLAMA_BIN"
    else
        # Check common system locations (Linux + macOS)
        CANDIDATES=(
            /usr/local/lib/ollama/llama-server
            /usr/bin/llama-server
            /usr/local/bin/llama-server
            "$HOME/llama-cpp/llama-server"
            "$HOME/llama.cpp/build/bin/llama-server"
        )
        # macOS Homebrew paths
        if [ "$OS" = "Darwin" ]; then
            if [ -x "/opt/homebrew/bin/llama-server" ]; then
                CANDIDATES+=("/opt/homebrew/bin/llama-server")
            fi
            if [ -x "/usr/local/opt/llama.cpp/bin/llama-server" ]; then
                CANDIDATES+=("/usr/local/opt/llama.cpp/bin/llama-server")
            fi
        fi

        for candidate in "${CANDIDATES[@]}"; do
            if [ -x "$candidate" ]; then
                LLAMA_BIN="$candidate"
                skip "llama-server found at $LLAMA_BIN"
                break
            fi
        done
    fi

    if [ ! -x "$LLAMA_BIN" ]; then
        # On macOS, try brew install first
        if [ "$OS" = "Darwin" ] && command -v brew &>/dev/null; then
            info "  Installing llama.cpp via Homebrew..."
            if brew install llama.cpp 2>/dev/null; then
                BREW_LLAMA=$(find /opt/homebrew /usr/local -name "llama-server" -type f 2>/dev/null | head -1)
                if [ -n "$BREW_LLAMA" ]; then
                    LLAMA_BIN="$BREW_LLAMA"
                    ok "llama-server installed via Homebrew at $LLAMA_BIN"
                fi
            fi
        fi
    fi

    if [ ! -x "$LLAMA_BIN" ]; then
        info "  Downloading llama.cpp binary for $OS $ARCH..."

        case "$ARCH" in
            x86_64)  LLAMA_ARCH="x86_64" ;;
            aarch64|arm64) LLAMA_ARCH="arm64" ;;
            armv7l)  LLAMA_ARCH="arm" ;;
            *)       fail "Unsupported architecture: $ARCH"; exit 1 ;;
        esac

        TMP_DIR=$(mktemp -d)

        # Try GitHub releases — find latest release tag dynamically
        LATEST_TAG=$(curl -fsSL --connect-timeout 10 "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name',''))" 2>/dev/null || echo "")

        if [ -n "$LATEST_TAG" ]; then
            info "  Latest release: $LATEST_TAG"

            # Platform-specific asset name patterns
            DOWNLOADED=false
            if [ "$OS" = "Linux" ]; then
                PATTERNS=("llama-ubuntu-x64.zip" "llama-linux-x64.zip" "llama-server-linux-x64.zip")
            elif [ "$OS" = "Darwin" ]; then
                PATTERNS=("llama-macos-arm64.zip" "llama-macos-x64.zip" "llama-osx-arm64.zip" "llama-osx-x64.zip")
            else
                PATTERNS=("llama-ubuntu-x64.zip" "llama-linux-x64.zip")
            fi

            for pattern in "${PATTERNS[@]}"; do
                DL_URL="https://github.com/ggml-org/llama.cpp/releases/download/${LATEST_TAG}/${pattern}"
                if curl -fsSL --connect-timeout 10 -o "$TMP_DIR/llama.zip" "$DL_URL" 2>/dev/null; then
                    DOWNLOADED=true
                    break
                fi
            done

            if $DOWNLOADED; then
                info "  Extracting..."
                cd "$TMP_DIR"
                unzip -qo llama.zip 2>/dev/null || true
                FOUND=$(find "$TMP_DIR" -name "llama-server" -type f 2>/dev/null | head -1)
                if [ -n "$FOUND" ]; then
                    cp "$FOUND" "$LLAMA_BIN"
                    chmod +x "$LLAMA_BIN"
                    ok "llama-server installed at $LLAMA_BIN"
                else
                    find "$TMP_DIR" -name "llama-*" -type f -exec cp {} "$BIN_DIR/" \; 2>/dev/null
                    if [ -x "$BIN_DIR/llama-server" ]; then
                        ok "llama-server installed at $LLAMA_BIN"
                    else
                        warn "Download succeeded but binary not found in archive"
                    fi
                fi
            else
                warn "Could not download llama.cpp from GitHub releases"
            fi
            rm -rf "$TMP_DIR"
        else
            warn "Could not reach GitHub API"
        fi

        if [ ! -x "$LLAMA_BIN" ]; then
            fail "llama-server not available"
            if [ "$OS" = "Darwin" ]; then
                warn "  Install: brew install llama.cpp"
            else
                warn "  Install from: https://github.com/ggml-org/llama.cpp#build"
            fi
            exit 1
        fi
    fi
fi

# ── Step 4: LLM Model (only for llama.cpp) ──────────────────────────────────
if ! $USE_OLLAMA; then
    info "── Step 4/5: LLM Model ──"
    mkdir -p "$MODEL_DIR"

    # Check if any GGUF model exists
    MODEL_FOUND=false
    for f in "$MODEL_DIR"/*.gguf; do
        if [ -f "$f" ]; then
            MODEL_FOUND=true
            MODEL_FILE="$f"
            break
        fi
    done

    if $MODEL_FOUND; then
        skip "Model found: $(basename "$MODEL_FILE")"
    else
        info "  Downloading qwen3-1.7b Q4_K_M (~1.1 GB)..."
        info "  This is a small, fast model — good for CPU inference"

        MODEL_URL="https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf"

        if curl -fSL --connect-timeout 10 --progress-bar -o "$MODEL_FILE.part" "$MODEL_URL"; then
            mv "$MODEL_FILE.part" "$MODEL_FILE"
            ok "Model saved: $MODEL_FILE ($(du -h "$MODEL_FILE" | cut -f1))"
        else
            rm -f "$MODEL_FILE.part"
            fail "Model download failed"
            warn "Download manually from:"
            warn "  $MODEL_URL"
            warn "  Save to: $MODEL_DIR/"
            exit 1
        fi
    fi
else
    info "── Step 4/5: LLM Model ──"
    skip "Ollama manages models automatically (no GGUF download needed)"
fi

# ── Step 5: Profile config ──────────────────────────────────────────────────
info "── Step 5/5: Configuration ──"
if [ -f "$SCRIPT_DIR/profile.yaml" ]; then
    skip "profile.yaml exists"
else
    cat > "$SCRIPT_DIR/profile.yaml" << 'YAML'
# JobRadar Profile — edit this with your details
name: "Your Name"
title: "Software Engineer"
experience_years: 3
skills:
  - Python
  - JavaScript
  - Docker
desired_roles:
  - Backend Engineer
  - Full Stack Developer
salary_min: 80000
salary_max: 150000
location_preference: "Remote"
remote_ok: true
industries:
  - Technology
  - SaaS
YAML
    warn "Created default profile.yaml — edit it with your real details!"
fi

if [ -f "$SCRIPT_DIR/companies.yaml" ]; then
    skip "companies.yaml exists"
else
    warn "companies.yaml not found — using defaults in jobradar/sources/"
fi

# ── Done ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✓ JobRadar is ready!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Quick start:"
echo "    cd $SCRIPT_DIR"
echo "    source .venv/bin/activate"
echo ""
echo "  CLI search (no AI — fast):"
echo "    python -m jobradar -q 'python developer' --no-ai"
echo ""
echo "  CLI search (with AI scoring):"
if $USE_OLLAMA; then
    echo "    # Make sure Ollama is running: ollama serve"
    echo "    python -m jobradar -q 'python developer' -p profile.yaml"
else
    echo "    # Start llama-server first:"
    echo "    $LLAMA_BIN --model $MODEL_FILE --port 8080 --host 0.0.0.0"
    echo "    python -m jobradar -q 'python developer' -p profile.yaml"
fi
echo ""
echo "  Web dashboard:"
echo "    cd dashboard && bash run.sh"
echo "    Open http://localhost:3000"
echo ""
