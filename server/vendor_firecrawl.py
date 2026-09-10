"""Make the server use the Firecrawl Python SDK vendored inside this project.

The repo ships a full copy of the Firecrawl service (self-hosted) in
``<repo>/firecrawl`` with the Python SDK at ``<repo>/firecrawl/apps/python-sdk``
(package name ``firecrawl-py``, version 4.41.0). This loader puts that folder at
the FRONT of ``sys.path`` before any ``import firecrawl`` happens and drops any
previously imported ``firecrawl`` module that resolves to a DIFFERENT install,
so the vendored SDK is always the one that runs.

Usage (must run before ``from firecrawl import ...``)::

    from vendor_firecrawl import bootstrap_vendored_firecrawl
    bootstrap_vendored_firecrawl()
    from firecrawl import FirecrawlClient
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

# <repo>/server/vendor_firecrawl.py -> <repo>/firecrawl/apps/python-sdk
_SERVER_DIR = Path(__file__).resolve().parent
VENDORED_FIRECRAWL_SDK_DIR = _SERVER_DIR.parent / "firecrawl" / "apps" / "python-sdk"
IS_FIRECRAWL_PRESENT = VENDORED_FIRECRAWL_SDK_DIR.exists() and (
    VENDORED_FIRECRAWL_SDK_DIR / "firecrawl" / "__init__.py"
).exists()


def bootstrap_vendored_firecrawl() -> Path:
    """Ensure the vendored Firecrawl Python SDK is the one Python imports."""
    vendored = VENDORED_FIRECRAWL_SDK_DIR

    if not IS_FIRECRAWL_PRESENT:
        # Keep the package importable even when the vendored folder was removed:
        # leave sys.path untouched so an installed firecrawl-py can still resolve.
        return vendored

    vendored_str = str(vendored)
    if vendored_str not in sys.path:
        sys.path.insert(0, vendored_str)

    # A previously-imported firecrawl from another install would shadow ours.
    # Drop it (and its submodules) so the vendored copy is re-imported.
    for module_name in [
        key for key in list(sys.modules)
        if key == "firecrawl" or key.startswith("firecrawl.")
    ]:
        module = sys.modules.get(module_name)
        module_file = getattr(module, "__file__", "") or ""
        # The repo-root firecrawl/ folder is NOT a module (no __init__.py), but
        # an implicit namespace package could still resolve there; require files
        # under the vendored SDK directory.
        if module_file and not module_file.startswith(vendored_str + os.sep):
            del sys.modules[module_name]

    return vendored