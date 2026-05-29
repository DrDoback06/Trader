"""Deal economics: fee model + profit / ROI / margin.

All fee values are config-driven (no hardcoded magic numbers in the maths). The
defaults in :meth:`FeeProfile.default_uk` are *estimates* for an eBay UK business
seller and should be verified against current eBay fees — they are deliberately
easy to override.
"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal

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
    buy_cost: Money  # ask price + inbound postage you pay to receive it
    resale_gross: Money  # expected sale price (est. market value)
    selling_fees: Money
    outbound_postage: Money
    packaging: Money
    net_proceeds: Money  # what lands in your pocket after a sale
    profit: Money
    roi: float  # profit / buy_cost
    margin: float  # profit / resale_gross


def compute_economics(
    *,
    ask_price: Money,
    est_value: Money,
    fee_profile: FeeProfile,
    inbound_postage: Money | None = None,
    outbound_postage: Money | None = None,
    packaging: Money | None = None,
) -> EconomicsResult:
    """Compute the full economics of flipping one card.

    ``est_value`` must already be in the same currency as ``ask_price`` — convert
    any foreign-currency valuation with :meth:`Money.convert` before calling.
    """
    currency = ask_price.currency
    if est_value.currency != currency:
        raise ValueError(
            f"est_value currency {est_value.currency} != ask currency {currency}; "
            "convert the valuation first."
        )

    inbound = inbound_postage if inbound_postage is not None else Money.zero(currency)
    outbound = (
        outbound_postage
        if outbound_postage is not None
        else fee_profile.default_outbound_postage
    )
    pack = packaging if packaging is not None else fee_profile.default_packaging

    buy_cost = (ask_price + inbound).quantize()
    resale = est_value.quantize()

    pct_fee = Money(resale.amount * fee_profile.total_percentage_fee, currency)
    selling_fees = (pct_fee + fee_profile.fixed_per_order).quantize()

    net_proceeds = (resale - selling_fees - outbound - pack).quantize()
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
