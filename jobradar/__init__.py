"""JobRadar — AI-Powered Job Search Agent."""

import sys
from pathlib import Path

# Make dependencies installed in the project's .venv importable even when the
# package is run with a system interpreter that doesn't have them (e.g.
# `python3 -m jobradar` without activating the virtual environment).
_ROOT = Path(__file__).resolve().parent.parent
_VENV_LIB = _ROOT / ".venv" / "lib"
if _VENV_LIB.is_dir():
    for _site_packages in _VENV_LIB.glob("python*/site-packages"):
        _sp = str(_site_packages)
        if _sp not in sys.path:
            sys.path.insert(0, _sp)

__version__ = "2.0.0"
