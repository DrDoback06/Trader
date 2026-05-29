"""Build an accurate eBay listing draft for a card you own.

Pure logic (no I/O), so the compliance-critical part — honest title, condition, and
description — is fully testable. Images are intentionally NOT carried over from the
source listing: you must publish with your OWN photos (reusing another seller's
images breaches eBay policy).
"""

from __future__ import annotations

from dataclasses import dataclass

from ..core.money import Money

# Best-effort map from our condition buckets to eBay Inventory API condition enums.
# Verify against your category before publishing — overridable via condition_map.
_CONDITION_ENUM: dict[str, str] = {
    "RAW_NM": "USED_EXCELLENT",
    "RAW_LP": "USED_VERY_GOOD",
    "RAW_MP": "USED_GOOD",
    "RAW_HP": "USED_ACCEPTABLE",
    "RAW_DAMAGED": "USED_ACCEPTABLE",
    "GRADED": "LIKE_NEW",  # graded slab; the exact grade goes in the title + description
}
_CONDITION_TEXT: dict[str, str] = {
    "RAW_NM": "Near Mint",
    "RAW_LP": "Lightly Played",
    "RAW_MP": "Moderately Played",
    "RAW_HP": "Heavily Played",
    "RAW_DAMAGED": "Damaged",
    "GRADED": "Graded",
}
_MAX_TITLE = 80  # eBay title limit


@dataclass(frozen=True)
class ListingDraft:
    sku: str
    title: str
    description: str
    condition: str  # eBay Inventory API condition enum
    price: Money
    category_id: str
    quantity: int = 1
    grade: str = ""


def build_listing_draft(
    *,
    sku: str,
    card_name: str,
    number: str = "",
    set_name: str = "",
    grade: str = "",
    condition: str = "RAW_NM",
    price: Money,
    category_id: str,
    quantity: int = 1,
    condition_map: dict[str, str] | None = None,
) -> ListingDraft:
    parts = [card_name, number, set_name, grade]
    title = " ".join(p for p in parts if p)
    title = f"{title} Pokemon TCG".strip()
    if len(title) > _MAX_TITLE:
        title = title[:_MAX_TITLE].rstrip()

    condition_text = grade or _CONDITION_TEXT.get(condition, condition)
    ebay_condition = "LIKE_NEW" if grade else (condition_map or _CONDITION_ENUM).get(
        condition, "USED_GOOD"
    )
    description = (
        f"{card_name} {number} ({set_name}).\n"
        f"Condition: {condition_text}.\n"
        "Photos form part of the description — please review them before buying.\n"
        "Carefully sleeved, top-loaded and posted promptly. UK seller."
    ).strip()

    return ListingDraft(
        sku=sku,
        title=title,
        description=description,
        condition=ebay_condition,
        price=price.quantize(),
        category_id=category_id,
        quantity=quantity,
        grade=grade,
    )
