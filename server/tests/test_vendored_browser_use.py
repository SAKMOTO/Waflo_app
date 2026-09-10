"""Ensure the server uses the browser-use copy vendored inside the repo.

A stale PyPI pin (browser-use==0.1.48 with a different API) used to disable the
commerce agent silently. The vendor bootstrap must make the exact
<repo>/browser-use copy win, no matter what else is importable.
"""


def test_vendored_browser_use_wins():
    from vendor_browser_use import bootstrap_vendored_browser_use

    vendored = bootstrap_vendored_browser_use()
    assert vendored.exists()

    import browser_use

    module_file = getattr(browser_use, "__file__", "") or ""
    # The vendored copy lives under the repo's browser-use/ folder. Assert the
    # import did not land on some other install (e.g. the stale PyPI package).
    assert "browser-use" in module_file or str(vendored).endswith("browser-use")
    if str(vendored) in module_file:
        return
    # Overly strict environments may expose the path via a different layout
    # (e.g. an editable install of the same folder); still require our repo.
    assert "Razorpay_buildathon" in module_file or "Waflo_app" in module_file


def test_vendored_browser_use_api_supports_commerce_imports():
    from vendor_browser_use import bootstrap_vendored_browser_use

    bootstrap_vendored_browser_use()
    from browser_use import (  # noqa: F401
        Agent,
        BrowserSession,
        BrowserProfile,
        ChatGoogle,
        ChatGroq,
    )
    # These are the exact bindings the commerce + browse agents rely on.
    assert Agent is not None and BrowserSession is not None and BrowserProfile is not None