# Getting eBay Buy API (Browse) full access

This guide is for unlocking eBay's **whole-category "scour everything" sweeps**. You do
**not** need it to use Trader — keep reading to see why — but if you want the broad
category sweeps, here's exactly how to apply, with direct links.

---

## TL;DR — do you even need this?

**Probably not to get started.** eBay gives every production keyset enough access to run
**keyword searches** (searching by card name, e.g. `Pokemon 151 Charizard ex 199/165`).
Trader's scanner is built to run entirely on those — the **"Everything (scour eBay)"** mode
fans out across ~40 keyword searches (your watchlist, sealed product, graded grails, and
deliberately misspelled "hidden gem" queries). That works on a standard keyset today.

What needs **Buy API full access** is browsing an **entire category with no search term**
(eBay's `category_ids`-only request) — the literal "show me everything in Pokémon singles"
sweep. Trader only does that when you set `EBAY_BUY_API_FULL_ACCESS=true`, which you should
only do **after** eBay grants your keyset full access.

| You have | You can scan by card name | You can scour whole categories |
|---|---|---|
| Standard production keyset | ✅ yes (default) | ❌ no |
| Buy API full access (this guide) | ✅ yes | ✅ yes — set `EBAY_BUY_API_FULL_ACCESS=true` |

---

## ⚠️ Reality check

eBay's Buy APIs are a **limited release**, granted at eBay's discretion after a **business-
model review**. They are designed for applications that **send buyers to eBay** (shopping,
comparison, and affiliate experiences). eBay commonly **declines** pure reselling/arbitrage
tools.

The honest framing that gives you the best shot: Trader is a **closed loop that increases
your eBay activity on both sides** — it helps you **buy more on eBay** (sourcing inventory)
**and relist/sell on eBay** (Trader already integrates the eBay **Sell API** for relisting).
More buying + more selling = more eBay GMV and fees, which is the outcome eBay's program
rewards. Pair it with an **eBay Partner Network** account so the purchases it surfaces can
carry your affiliate links — that aligns you squarely with what eBay wants to approve.

Approval is **not guaranteed** and can take weeks. If it's declined, keyword scanning still
works — you lose nothing by staying on the default.

---

## Prerequisites checklist

- [ ] An **eBay developer account** — https://developer.ebay.com/
- [ ] A **Production keyset** (App ID / Cert ID you've already pasted into Trader) —
      https://developer.ebay.com/my/keys
- [ ] **Developer support activated** for a contact on your account (you can't open an
      Application Growth Check until support is active) — https://developer.ebay.com/my/support/
- [ ] An **eBay Partner Network (EPN)** account, with your business model registered —
      https://partnernetwork.ebay.com/

---

## Step by step (with direct links)

1. **Join eBay Partner Network** and register your business model:
   https://partnernetwork.ebay.com/
2. **Read the Buy API requirements** (eligibility + what eBay expects):
   https://developer.ebay.com/api-docs/buy/static/buy-requirements.html
3. **Work through "Get Started on a Buying Application"** (eBay's official walkthrough):
   https://developer.ebay.com/develop/get-started/get-started-on-a-buying-application
4. **Activate developer support** for a contact (required before the next step):
   https://developer.ebay.com/my/support/
5. **Open the Application Growth Check request** — this is the actual "apply" form:
   https://developer.ebay.com/my/support/tickets?tab=app-check
   - Subject line: **`Buy API Production Access (your eBay user ID)`**
   - Reference docs: https://developer.ebay.com/api-docs/static/gs_apply-for-the-application.html
     and https://developer.ebay.com/grow/application-growth-check
6. **Reply to eBay's confirmation email** with **mockups** and the **data flow** of your
   user experience (see the ready-to-use answers below).
7. When eBay approves your keyset, set **`EBAY_BUY_API_FULL_ACCESS=true`** in your `.env`
   (or environment) and restart Trader. The "scour everything" sweeps switch on.

---

## Ready-to-paste application answers

Adapt these to your own words — eBay can tell boilerplate from a real description.

**Application name:** Trader — UK TCG sourcing & resale assistant

**What does your application do?**
> A personal decision-support dashboard for trading-card sellers. It searches active eBay UK
> listings for trading cards, values each against real eBay UK sold prices, and ranks the
> underpriced ones so I can **buy them on eBay**. After a card sells, it prepares and
> **relists inventory back onto eBay via the Sell API**. It does not buy automatically — every
> purchase is a manual decision made on eBay.

**Which Buy APIs do you need and why?**
> **Browse API** (`item_summary/search`) to find active eBay UK listings to evaluate. I need
> category-level browsing in addition to keyword search so the tool can surface mispriced
> cards across a whole category, not only specific named cards.

**Business model / how it benefits eBay:**
> It increases my transaction volume on eBay on **both sides of the marketplace**: it drives
> my **purchases** (sourcing stock) and my **sales** (relisting via the Sell API). I am an
> eBay Partner Network member, so surfaced listings carry my EPN affiliate links. Net effect:
> more eBay GMV, more eBay fees, more buyer traffic to eBay.

**Expected call volume:**
> Low — a single user. Well under eBay's default daily Browse quota (the app caps itself at a
> configurable daily call budget, default 4,500/day).

**Marketplaces:** eBay UK (`EBAY_GB`).

**Compliance:**
> Listing data is used only to value and rank items for my own purchasing decisions; it is not
> redistributed, scraped at scale, or used to build a competing catalogue. I agree to the eBay
> API License Agreement and Buy API requirements.

---

## What to attach (mockups + data flow)

eBay wants to see a real user experience. Screenshot Trader's actual screens:

- **Deals** — ranked underpriced listings with profit-after-fees (the buying decision).
- **Check a card** — type a card + the price you'd pay; it values it against eBay UK sold data.
- **Portfolio / Relist** — mark a card bought, then relist it back onto eBay (Sell API).

And describe the data flow in one diagram or paragraph:

> eBay **Browse API** (active UK listings) → identify & value against eBay UK **sold prices**
> → rank by profit after eBay fees → **I manually buy the card on eBay** → after it arrives,
> **relist on eBay via the Sell API**.

The point to land: data comes **from** eBay and results in **purchases and sales back on
eBay** — a closed loop, not data extraction.

---

## Common reasons applications get declined

- **Pure arbitrage with no benefit to eBay** — frame the buy-and-relist loop and EPN clearly.
- **No EPN account / unregistered business model** — do step 1 first.
- **Vague description or obvious boilerplate** — be specific about cards, eBay UK, your flow.
- **Requesting more than you need** — ask only for the Browse API.
- **Support not activated** — you can't even open the request until it is (step 4).

---

## Links

- eBay Developers Program: https://developer.ebay.com/
- Your keysets: https://developer.ebay.com/my/keys
- Buy API requirements: https://developer.ebay.com/api-docs/buy/static/buy-requirements.html
- Get Started on a Buying Application: https://developer.ebay.com/develop/get-started/get-started-on-a-buying-application
- Application Growth Check overview: https://developer.ebay.com/grow/application-growth-check
- Apply for the Application Growth Check: https://developer.ebay.com/api-docs/static/gs_apply-for-the-application.html
- Open the request (form): https://developer.ebay.com/my/support/tickets?tab=app-check
- eBay Partner Network: https://partnernetwork.ebay.com/
- Browse API reference: https://developer.ebay.com/api-docs/buy/browse/resources/methods
