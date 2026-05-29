"""Background scheduler: periodically scour eBay and alert on new green deals.

Started only when ``SCAN_INTERVAL_MIN > 0`` and eBay is configured, so tests and
local/demo runs are unaffected. On free hosts that sleep when idle, scans run only
while the app is awake — fine for now.
"""

from __future__ import annotations

import logging
from typing import Any

from apscheduler.schedulers.background import BackgroundScheduler

from ..providers.factory import build_alert_channel, build_browse_source
from .alerts import dispatch_alerts
from .scanner import scan
from .watchlist import cheapest_sweep_target, ending_soon_sweep_target

log = logging.getLogger(__name__)


def run_scan_cycle(app: Any) -> int:
    """Run one 'everything' scan + alert dispatch. Returns alerts sent."""
    source = build_browse_source(app.state.credentials, app.state.settings)
    if source is None:
        return 0
    targets = [*app.state.watchlist, cheapest_sweep_target(), ending_soon_sweep_target()]
    result = scan(
        targets,
        source,
        app.state.catalogue,
        app.state.sold_provider,
        quota=app.state.quota,
        cfg=app.state.pipeline_cfg,
    )
    app.state.deals = result.deals
    channel = build_alert_channel(app.state.settings)
    return dispatch_alerts(
        result.deals, channel, app.state.session_maker, channel_name=channel.name
    )


def start_scheduler(app: Any) -> BackgroundScheduler | None:
    interval = app.state.settings.scan_interval_min
    if interval <= 0:
        return None
    scheduler = BackgroundScheduler(timezone="UTC")

    def job() -> None:
        try:
            sent = run_scan_cycle(app)
            if sent:
                log.info("auto-scan: %d new alert(s) sent", sent)
        except Exception:  # pragma: no cover - never let a bad cycle kill the scheduler
            log.exception("auto-scan cycle failed")

    scheduler.add_job(job, "interval", minutes=interval, id="auto_scan", max_instances=1)
    scheduler.start()
    log.info("auto-scan scheduler started (every %d min)", interval)
    return scheduler
