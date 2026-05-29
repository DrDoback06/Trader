"""External I/O behind swappable interfaces.

The pure core never imports a concrete provider; everything goes through the
Protocols in :mod:`trader.providers.base`, so live eBay / sold-price / alert
implementations can be slotted in (or mocked) without touching the engine.
"""
