# Getting Started — the dummy-proof guide

This walks you from nothing to a working app that finds underpriced Pokémon cards on
eBay UK, values them against real UK sold prices, and ranks the best buys. No prior
experience assumed. **The app never buys anything for you — you always click buy yourself.**

---

## 1. The keys at a glance

| # | Key | What it switches on | Needed? | Cost |
|---|-----|---------------------|---------|------|
| 1 | **RapidAPI key** | UK *sold* prices (what cards actually sell for = the "market value") | **Yes** | Free tier, then ~£10–40/mo |
| 2 | **eBay Client ID + Secret** | Live eBay UK *listings* (what's for sale right now = the deals to scan) | **Yes** | Free |
| 3 | Claude (Anthropic) key | Read a card from the listing **photo** when the title is too vague | Optional | Pay-per-use, pennies |
| 4 | eBay **seller token** | Auto-**relisting** cards you own (preview-first) | Optional, later | Free |

You only need **#1 and #2** to go fully live. Until you add them, the app still runs and
shows **demo** deals so you can learn the interface.

---

## 2. Key #1 — RapidAPI (UK sold prices)

This is the key in the screenshot you were looking at.

1. Go to **rapidapi.com** and sign in (or sign up — Google/GitHub login is fine).
2. Open the API page: **"eBay Average Selling Price"** by *ecommet*
   (search it, or use the link from the app's *Sources & Keys* page).
3. Click the **Pricing** tab → **Subscribe** to the **Basic** plan (free to start; paid
   plans just give more calls per month). **This step is essential** — without an active
   subscription the key returns a `403` error.
4. Your key is the long string shown in the **`X-RapidAPI-Key`** box on the *Endpoints*
   page (it looks like `86178c3a…`). Click the copy icon.
5. In the app → **Sources & Keys** → paste it into **"RapidAPI key — eBay UK sold prices"** → **Save keys**.

> 🔒 Treat this key like a password. Don't post it publicly or put it in a git commit.
> If it ever leaks, regenerate it on RapidAPI (your old one stops working).

---

## 3. Key #2 — eBay developer (Client ID + Secret)

This lets the app read live eBay UK listings to find deals.

1. Go to **developer.ebay.com** → **Register** (or sign in with your normal eBay account).
2. Open **My Account → Application Keysets** (sometimes shown as "Keys").
3. Create a **Production** keyset (not Sandbox). You'll get two values:
   - **App ID (Client ID)** → this is your **eBay Client ID**.
   - **Cert ID (Client Secret)** → this is your **eBay Client Secret**.
4. If eBay asks you to **accept terms** or **apply for Browse/Buy API access**, do it and
   follow the prompt — that's normal and usually instant for the Browse API.
5. In the app → **Sources & Keys** → paste them into **eBay Client ID** and **eBay Client
   Secret** → **Save keys**.

> The app uses these to read public listings only (no buying). Buying always stays a
> manual tap on eBay — that's deliberate, to stay within eBay's rules.

---

## 4. Key #3 (optional) — Claude photo ID

Lets the app read a card off the listing **image** when the title is too vague to match.

1. Go to **console.anthropic.com** → **API Keys** → **Create key** → copy it.
2. App → **Sources & Keys** → **"Claude API key — photo card ID"** → paste → **Save keys**.
3. Tick the **Photo ID (Claude AI)** source to turn it on.

It's pay-per-use and only fires on promising-but-unclear listings, so it costs pennies.

---

## 5. Key #4 (optional, later) — eBay seller token (auto-relist)

For automatically **listing cards you own** for resale (preview-first, your own photos).
It's a bigger one-time setup (eBay login consent + business policies), so leave it until
you're actively reselling. Full steps: **`docs/DEPLOY.md` → "Relisting (eBay Sell API)"**.

---

## 6. Get the app running — pick ONE

### Option A — Render (easiest, gives you a web link for any device) ⭐
No terminal needed; you get an `https://…onrender.com` URL you can open on your phone too.
Full click-by-click steps are in **`docs/DEPLOY.md` → "Option A — Render"**. Short version:

1. **render.com** → sign in with GitHub.
2. **New + → Blueprint** → connect the **`drdoback06/trader`** repo → **Apply**
   (it auto-uses the right branch and settings).
3. Set **`ACCESS_PASSWORD`** to a password of your choice (this locks your public URL).
   You can add the eBay/RapidAPI keys here as environment variables too, *or* type them
   into the app later — but on the free plan, **env-var keys survive restarts and in-app
   keys don't**, so env vars are the safer place.
4. Wait ~3–6 min for the build → open the URL → log in (any username + your password).

### Option B — On your own laptop
Needs **Python 3.11+** and **Node 18+** installed. Then in a terminal:

```bash
git clone https://github.com/drdoback06/trader.git
cd trader
git checkout claude/vibrant-faraday-HuOEu
./run.sh
```

Open **http://localhost:8000**. (On Windows, run that from Git Bash or WSL.)

---

## 7. Put your keys in

1. In the app, open the **Sources & Keys** tab.
2. Paste each key into its box and click **Save keys**. Current values show masked (••••).
3. Tick the checkboxes for **eBay UK — Sold prices** and **eBay UK — Active listings** so
   both are enabled. (A source shows **"active"** when it's enabled *and* keyed.)
4. Every input has a **"Where to get this ↗"** link if you need to go back to the source.

---

## 8. Your first scan

1. Go to the **Deals** tab.
2. Pick a mode:
   - **Everything (scour eBay)** — the broad "find me deals" sweep.
   - **Cheapest** / **Ending soon** (with a 1–12h window) — for buy-it-now bargains or
     auctions about to end.
   - **Graded** — slabbed cards, tuned for longer-term holds (look for the 💎 badge).
3. Click **Run live eBay scan**.
4. Read each row:
   - **Profit light** 🟢🟡🔴 + **ROI %** — green = high profit after fees.
   - **Sell-through light** — how likely/quickly it actually sells (high margin but red
     here = it may sit a while).
   - **% below market**, plus **💎 Hold** on graded long-term picks.
   - **Open ↗** — opens the listing on eBay so **you** can buy it.

---

## 9. If something isn't working

| Symptom | Fix |
|---------|-----|
| Source shows **"needs key"** | The key wasn't saved, or you saved it in the wrong box. Re-paste and Save. |
| Sold-price source errors / `403` | You haven't **Subscribed** to the RapidAPI plan (step 2.3). |
| Live scan returns nothing | Check the eBay Client ID/Secret are correct and the **Active listings** source is ticked. |
| Render link is slow the first time | Free plan went to sleep; it wakes in ~30s. |
| Keys disappeared after a Render redeploy | Free plan resets its disk — set keys as **environment variables** in Render instead. |
| Browser keeps asking for a password | That's the `ACCESS_PASSWORD` gate. Username can be anything; password is what you set. |

---

That's the whole journey: **2 keys → run it → paste keys → scan → read the lights → tap buy.**
Everything else (alerts, portfolio, grading holds, relisting) builds on top once you're live.
