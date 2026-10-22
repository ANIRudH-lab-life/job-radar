# 🎯 JobRadar

A CLI job search agent that hunts across 8 free sources at once and helps you figure out which ones are actually worth your time.

It uses a local LLM to score jobs against your profile — but **the AI is just a guide, not a decision-maker**. You're the one who decides what fits. That's the whole point.

## Why JobRadar?

Most job boards show you hundreds of listings and leave you drowning in tabs. JobRadar pulls from multiple sources at once, filters out the noise, and gives you a ranked list with AI-generated notes on why each job might (or might not) be a fit.

But here's the thing: **we believe the best job search tool puts a human in the loop**. The AI can score and summarize, but it can't understand your gut feeling about a company culture, or that you'd rather work somewhere with a smaller team even if the salary is lower. That part is yours.

So use the scores as a starting point, not a verdict.

## What it does

- **Searches 8 sources at once** — Remotive, Arbeitnow, RemoteOK, Jobicy, Himalayas, Greenhouse (direct ATS), Ashby (direct ATS), and optionally LinkedIn
- **Rates jobs with a local LLM** — auto-detects Ollama or llama.cpp, scores each job 0-100 on skills match, experience fit, salary fit, and remote fit
- **Remembers what you've seen** — persistent cache so you don't re-review the same jobs every run
- **Works completely offline** — all AI runs locally on your machine, no cloud APIs, no subscriptions
- **Looks good in the terminal** — color-coded scores, progress bars, clean tables
- **Web dashboard** — dark-mode SPA at localhost:3000 with Kanban pipeline, filters, and config editor

## Quick Install

### Option 1: One-liner (Linux / macOS)

> Run these commands from the directory where you want JobRadar installed (it will be created there).

```bash
mkdir -p ~/jobradar && cd ~/jobradar
curl -fsSL https://raw.githubusercontent.com/ANIRudH-lab-life/job-radar/main/setup.sh | bash
```

### Option 2: npm (all platforms)

```bash
npx jobradar-setup
# or
git clone https://github.com/ANIRudH-lab-life/job-radar.git
cd job-radar
npm run setup
```

### Option 3: PowerShell (Windows)

```powershell
git clone https://github.com/ANIRudH-lab-life/job-radar.git
cd job-radar
.\setup.ps1
```

### Option 4: Manual

```bash
git clone https://github.com/ANIRudH-lab-life/job-radar.git
cd job-radar
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
pip install -r dashboard/requirements.txt
```

### What the installer does

The smart installer (`setup.sh` / `setup.ps1`) checks each dependency before downloading:

| Step | Checks for | Downloads if missing |
|------|-----------|---------------------|
| 1. Python | 3.9+ in PATH | — (shows install link) |
| 2. pip packages | Each import individually | Only missing packages |
| 3. LLM Backend | **You choose**: Ollama or llama.cpp | Ollama install + model pull, or llama.cpp binary |
| 4. LLM Model | Only if llama.cpp chosen | qwen3-1.7b Q4_K_M (~1.1GB) GGUF |
| 5. Config | profile.yaml | Creates defaults |

Safe to re-run — second run is instant, nothing re-downloaded.

The installer asks which LLM backend you prefer:
- **Ollama (recommended)** — auto-installs the model, easy to manage, works out of the box
- **llama.cpp (faster)** — raw performance, downloads GGUF model manually

### Platform notes

| Platform | Installer | llama-server source |
|----------|-----------|---------------------|
| Linux (x64) | `bash setup.sh` | Ollama (recommended) or GitHub release zip |
| macOS (ARM) | `bash setup.sh` | Ollama (recommended) or `brew install llama.cpp` |
| macOS (Intel) | `bash setup.sh` | Ollama (recommended) or `brew install llama.cpp` |
| Windows (x64) | `.\setup.ps1` | Ollama (recommended) or GitHub release zip |

## Quick Start

```bash
cd job-radar
source .venv/bin/activate   # Windows: .venv\Scripts\activate

# Quick search (no AI — fast)
python -m jobradar -q "python developer" --no-ai

# Search with AI rating (needs a local LLM running)
python -m jobradar -q "python developer" -p profile.yaml

# Interactive mode — just run it and type queries
python -m jobradar

# Web dashboard
cd dashboard && bash run.sh   # Windows: python -m uvicorn app:app --port 3000
# Open http://localhost:3000

# Start the LLM server (for AI scoring)
# Option A: Ollama (recommended)
ollama serve &                              # if not already running
python -m jobradar -q "python dev" -p profile.yaml

# Option B: llama.cpp (faster)
llama-server --model models/qwen3-1.7b-q4_k_m.gguf --port 8080
python -m jobradar -q "python dev" -p profile.yaml
```

## Job Sources

| Source | Type | Notes |
|--------|------|-------|
| Remotive | Job board API | Remote jobs |
| Arbeitnow | Job board API | Worldwide, paginated |
| RemoteOK | Job board API | Remote jobs, good volume |
| Jobicy | Job board API | Remote jobs with salary data |
| Himalayas | Job board API | Remote jobs with seniority levels |
| Greenhouse | **Direct ATS** | 15 curated tech companies (Gitlab, Figma, Stripe, etc.) |
| Ashby | **Direct ATS** | 15 curated tech companies (OpenAI, Anthropic, Linear, etc.) |
| LinkedIn | Web scraping | ⚠️ Off by default — may violate ToS |

The Greenhouse and Ashby sources pull directly from company career pages via their public APIs. No login, no API keys. You can edit the company list in `companies.yaml`.

## Profile Setup

Create a `profile.yaml` with your details so the AI can score jobs against your actual background:

```yaml
name: "Your Name"
title: "Software Engineer"
experience_years: 5
skills: [Python, Docker, AWS, React]
desired_roles: [Backend Engineer, SRE]
salary_min: 100000
salary_max: 160000
location_preference: "Remote"
remote_ok: true
industries: [Fintech, SaaS]
```

The more detail you put in, the better the scoring. But remember — the AI's score is a suggestion, not a ranking you have to follow.

## Companies (ATS Sources)

Edit `companies.yaml` to add or remove companies for the Greenhouse and Ashby sources. Just use the company slug (the part of the URL on their careers page):

```yaml
greenhouse:
  - gitlab
  - figma
  - discord
  - shopify
  - stripe

ashby:
  - openai
  - anthropic
  - linear
  - resend
  - clerk
```

## Caching

JobRadar remembers jobs you've already seen so you don't re-review them on every run. By default, it keeps a 7-day cache in `~/.jobradar/seen_jobs.db`.

```bash
# Change cache duration to 30 days
python -m jobradar -q "python" --cache-days 30

# Skip the cache entirely
python -m jobradar -q "python" --no-cache

# Clear the cache
python -m jobradar --clear-cache
```

## Web Dashboard

The dashboard gives you a visual interface for everything:

- **Header stats** — total discovered, high match, pending review, applied
- **Job cards** with color-coded match scores (green/yellow/red)
- **Inspector panel** — full description, matched keywords, LLM reasoning
- **Kanban pipeline** — drag jobs from Discovered → Reviewing → Applied → Interviewing
- **Config editor** — edit profile.yaml and companies.yaml in the UI
- **Live activity log** — terminal-style console showing LLM scoring progress
- **Keyboard shortcuts** — J/K to scroll, E to edit, A to mark applied

Start it with:
```bash
cd dashboard
bash run.sh          # Linux/macOS
# or
python -m uvicorn app:app --port 3000   # Windows
```

Then open http://localhost:3000.

## CLI Reference

| Flag | Default | What it does |
|------|---------|-------------|
| `-q`, `--query` | — | Your search query |
| `-l`, `--location` | — | Filter by location |
| `-p`, `--profile` | `profile.yaml` | Path to your profile |
| `--no-ai` | off | Skip AI rating (faster) |
| `--export` | — | Save results to `.json` or `.csv` |
| `--limit` | `50` | Max jobs per source |
| `--max-pages` | `3` | Max pages per source |
| `--max-concurrency` | `3` | Concurrent AI rating calls |
| `--companies` | `companies.yaml` | Company list for ATS sources |
| `--cache-days` | `7` | Days to remember seen jobs |
| `--no-cache` | off | Disable the cache |
| `--clear-cache` | — | Clear cache and exit |
| `--list-ats-companies` | — | Show configured ATS companies |
| `--enable-linkedin` | off | ⚠️ Enable LinkedIn scraping |
| `--llm-url` | *(auto-detect)* | LLM server URL (auto-scans 11434, 8080, 1234) |
| `--llm-model` | `qwen3:1.7b` | LLM model name (override auto-detection) |

## Changing the Model

JobRadar defaults to `qwen3:1.7b` (1.1 GB, fast on CPU). If you want a different model:

```bash
# Pull a different model
ollama pull qwen3:8b          # larger, better reasoning, slower
ollama pull qwen2.5:1.5b      # smaller, faster, less accurate

# Use it with JobRadar
python -m jobradar -q "python dev" --llm-model qwen3:8b
```

Or set it permanently in your environment:
```bash
export LLM_MODEL="qwen3:8b"
python -m jobradar -q "python dev"
```

## Architecture

```
job-radar/
├── setup.sh              # Smart installer (Linux/macOS)
├── setup.ps1             # Smart installer (Windows)
├── uninstall.sh          # Uninstaller (Linux/macOS)
├── uninstall.ps1         # Uninstaller (Windows)
├── package.json          # npm wrapper
├── profile.yaml          # Your profile (edit this)
├── companies.yaml        # ATS company slugs (edit this)
├── jobradar/
│   ├── models.py         # Job and Profile dataclasses
│   ├── rating.py         # Local LLM rating with retry logic
│   ├── cache.py          # SQLite seen-jobs cache
│   ├── display.py        # Rich terminal UI
│   ├── cli.py            # Search pipeline + argparse
│   └── sources/
│       ├── remotive.py   # Remotive API
│       ├── arbeitnow.py  # Arbeitnow API (paginated)
│       ├── remoteok.py   # RemoteOK API
│       ├── jobicy.py     # Jobicy API
│       ├── himalayas.py  # Himalayas API
│       ├── greenhouse.py # Greenhouse ATS (direct API)
│       ├── ashby.py      # Ashby ATS (direct API)
│       └── linkedin.py   # LinkedIn scraping (opt-in)
└── dashboard/
    ├── app.py            # FastAPI backend
    ├── database.py       # SQLite storage
    ├── run.sh            # Dashboard launcher
    └── static/
        └── index.html    # Dark-mode SPA
```

## A Note on AI in Job Search

We built JobRadar because job searching is exhausting and the tools out there either dump too many listings on you or try to automate the whole thing. We think the sweet spot is: **let the machine do the grunt work (searching, filtering, summarizing) and keep the human making the actual decisions.**

The AI scoring is there to save you time reading through listings, not to tell you what to apply for. A 95/100 score doesn't mean "apply immediately" — it means "this one looks relevant, worth a closer look." A 40/100 doesn't mean "skip it" — it might be a role you'd love that the AI just doesn't have enough context for.

**You are the loop. The AI is just the filter.**

## ⚠️ LinkedIn Warning

LinkedIn scraping is **off by default**. It depends on undocumented HTML that breaks constantly and might violate their ToS. We keep it around because sometimes it's useful, but we'd rather you know the tradeoff:

```bash
python -m jobradar -q "python dev" --enable-linkedin
```

## Uninstalling

Run the uninstaller in the project directory — it removes everything the installer created (venv, models, binaries, caches, dashboard database) but **keeps your `profile.yaml` and `companies.yaml`**:

```bash
# Linux / macOS
bash uninstall.sh

# Windows
.\uninstall.ps1
```

Options:

| Flag | What it does |
|------|-------------|
| `--purge` / `-Purge` | Also delete `profile.yaml`, `companies.yaml`, `results.csv`, `results.json` |
| `--keep-cache` / `-KeepCache` | Keep the `~/.jobradar` seen-jobs cache |

Safe to re-run — a second run just reports what's already gone. Uninstalling does **not** remove Ollama or the models you pulled into it; those are managed separately (`ollama rm qwen3:1.7b` if you want them gone).

## Running Tests

```bash
pip install pytest
pytest tests/ -v
```

## License

MIT — see [LICENSE](LICENSE)
