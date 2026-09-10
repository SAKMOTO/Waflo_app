"""Make the server use the browser-use checkout vendored inside this project.

The repo ships a full copy of the browser-use library in ``<repo>/browser-use``
(version 0.13.8) so installs do not depend on whoever published a specific PyPI
version. This loader puts that folder at the FRONT of ``sys.path`` before any
``import browser_use`` happens, and drops any previously imported ``browser_use``
module that resolves to a DIFFERENT install (e.g. a stale ``browser-use==0.1.48``
PyPI wheel) so the vendored copy is always the one that runs.

Usage (must run before ``from browser_use import ...``)::

    from vendor_browser_use import bootstrap_vendored_browser_use
    bootstrap_vendored_browser_use()
    from browser_use import Agent, BrowserSession, BrowserProfile
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

# <repo>/server/vendor_browser_use.py -> <repo>/browser-use/
_SERVER_DIR = Path(__file__).resolve().parent
VENDORED_BROWSER_USE_DIR = _SERVER_DIR.parent / "browser-use"
IS_VENDORED_PRESENT = VENDORED_BROWSER_USE_DIR.exists()


def bootstrap_vendored_browser_use() -> Path:
    """Ensure the vendored browser-use package is the one Python imports."""
    vendored = VENDORED_BROWSER_USE_DIR

    if not IS_VENDORED_PRESENT:
        # Keep the package importable even when the vendored folder was removed:
        # leave sys.path untouched so an installed browser-use can still resolve.
        return vendored

    vendored_str = str(vendored)
    if vendored_str not in sys.path:
        sys.path.insert(0, vendored_str)

    # A previously-imported browser_use from another install would shadow ours.
    # Drop it (and its submodules) so the vendored copy is re-imported.
    for module_name in [
        key for key in list(sys.modules)
        if key == "browser_use" or key.startswith("browser_use.")
    ]:
        module = sys.modules.get(module_name)
        module_file = getattr(module, "__file__", "") or ""
        if module_file and not module_file.startswith(vendored_str):
            del sys.modules[module_name]

    return vendored