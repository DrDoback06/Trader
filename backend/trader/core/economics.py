"""Deal economics: fee model + profit / ROI / margin, plus a max-bid solver.

All fee values are config-driven (no hardcoded magic numbers in the maths). The
defaults in :meth:`FeeProfile.default_uk` are *estimates* for an eBay UK business
seller and should be verified against current eBay fees — they are deliberately
easy to override.
"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import ROUND_DOWN, Decimal

from .money import Money


@dataclass(frozen=True)
class FeeProfile:
    name: str
    marketplace: str = "EBAY_GB"
    # Final value fee as a fraction of the sale price (incl. payment processing
    # for eBay managed payments).
    final_value_fee_pct: Decimal = Decimal("0.128")
    # eBay UK "regulatory operating fee".
    regulatory_operating_fee_pct: Decimal = Decimal("0.0035")
    # Fixed fee per order.
    fixed_per_order: Money = Money(Decimal("0.30"), "GBP")
    # Only set if payment processing is billed separately from the FVF.
    payment_processing_pct: Decimal = Decimal("0")
    is_business_seller: bool = True
    # Cost to pack and to post the sold item to the buyer (when not recovered
    # from the buyer). Conservative defaults for a small card in a stamped
    # large letter.
    default_packaging: Money = Money(Decimal("0.40"), "GBP")
    default_outbound_postage: Money = Money(Decimal("1.55"), "GBP")
    effective_from: str = "2025-01-01"

    @classmethod
    def default_uk(cls) -> FeeProfile:
        """eBay UK business-seller estimate. Verify against live eBay fees."""
        return cls(name="eBay UK business (estimate)")

    @property
    def total_percentage_fee(self) -> Decimal:
        return (
            self.final_value_fee_pct
            + self.regulatory_operating_fee_pct
            + self.payment_processing_pct
        )


@dataclass(frozen=True)
class EconomicsResult:
    buy_cost: Money  # acquisition price + inbound postage you pay to receive it
    resale_gross: Money  # expected sale price (est. market value)
    selling_fees: Money
    outbound_postage: Money
    packaging: Money
    net_proceeds: Money  # what lands in your pocket after a sale
    profit: Money
    roi: float  # profit / buy_cost
    margin: float  # profit / resale_gross


def _resolve_costs(
    fee_profile: FeeProfile,
    currency: str,
    inbound_postage: Money | None,
    outbound_postage: Money | None,
    packaging: Money | None,
) -> tuple[Money, Money, Money]:
    inbound = inbound_postage if inbound_postage is not None else Money.zero(currency)
    outbound = (
        outbound_postage if outbound_postage is not None else fee_profile.default_outbound_postage
    )
    pack = packaging if packaging is not None else fee_profile.default_packaging
    return inbound, outbound, pack


def _selling_breakdown(
    resale: Money, fee_profile: FeeProfile, outbound: Money, packaging: Money
) -> tuple[Money, Money]:
    """Return (selling_fees, net_proceeds) for a sale at ``resale``."""
    pct_fee = Money(resale.amount * fee_profile.total_percentage_fee, resale.currency)
    selling_fees = (pct_fee + fee_profile.fixed_per_order).quantize()
    net_proceeds = (resale - selling_fees - outbound - packaging).quantize()
    return selling_fees, net_proceeds


def compute_economics(
    *,
    ask_price: Money,
    est_value: Money,
    fee_profile: FeeProfile,
    inbound_postage: Money | None = None,
    outbound_postage: Money | None = None,
    packaging: Money | None = None,
    acquisition_price: Money | None = None,
) -> EconomicsResult:
    """Compute the full economics of flipping one card.

    ``acquisition_price`` overrides ``ask_price`` as what you actually pay for the
    item (e.g. the current auction bid, or an accepted Best Offer). ``est_value``
    must be in the same currency as ``ask_price``.
    """
    currency = ask_price.currency
    if est_value.currency != currency:
        raise ValueError(
            f"est_value currency {est_value.currency} != ask currency {currency}; "
            "convert the valuation first."
        )

    inbound, outbound, pack = _resolve_costs(
        fee_profile, currency, inbound_postage, outbound_postage, packaging
    )
    effective = acquisition_price if acquisition_price is not None else ask_price

    buy_cost = (effective + inbound).quantize()
    resale = est_value.quantize()
    selling_fees, net_proceeds = _selling_breakdown(resale, fee_profile, outbound, pack)
    profit = (net_proceeds - buy_cost).quantize()

    roi = float(profit.amount / buy_cost.amount) if buy_cost.amount > 0 else 0.0
    margin = float(profit.amount / resale.amount) if resale.amount > 0 else 0.0

    return EconomicsResult(
        buy_cost=buy_cost,
        resale_gross=resale,
        selling_fees=selling_fees,
        outbound_postage=outbound,
        packaging=pack,
        net_proceeds=net_proceeds,
        profit=profit,
        roi=roi,
        margin=margin,
    )


def max_bid_for_target(
    *,
    est_value: Money,
    fee_profile: FeeProfile,
    min_roi: float,
    min_profit: Money,
    inbound_postage: Money | None = None,
    outbound_postage: Money | None = None,
    packaging: Money | None = None,
) -> Money:
    """Highest price to pay for the item (max bid / max offer) that still clears
    both ``min_roi`` and ``min_profit``. Excludes inbound postage you'd also pay."""
    currency = est_value.currency
    inbound, outbound, pack = _resolve_costs(
        fee_profile, currency, inbound_postage, outbound_postage, packaging
    )
    _, net_proceeds = _selling_breakdown(est_value.quantize(), fee_profile, outbound, pack)

    # buy_cost <= net - min_profit   AND   buy_cost <= net / (1 + min_roi)
    cap_profit = net_proceeds.amount - min_profit.amount
    divisor = Decimal("1") + Decimal(str(min_roi))
    cap_roi = net_proceeds.amount / divisor if divisor > 0 else net_proceeds.amount
    max_buy_cost = min(cap_profit, cap_roi)

    max_bid = max_buy_cost - inbound.amount
    if max_bid < 0:
        max_bid = Decimal("0")
    # Round DOWN: the max bid must never exceed the safe ceiling.
    return Money(max_bid.quantize(Decimal("0.01"), rounding=ROUND_DOWN), currency)
