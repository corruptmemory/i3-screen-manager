# NVMe SSD & NAND Flash Price Research: Dec 2025 – Mar 2026

Research compiled 2026-03-28 from two sources:
- Perplexity deep research (web synthesis, 1TB retail prices)
- Gamers Nexus "SSDs: WTF?" (upstream NAND spot prices + supply chain analysis)

---

## The Real Picture: Spot Prices vs. Retail

Retail prices doubling is the *lagged consumer view*. The upstream NAND wafer spot prices are the actual leading indicator — and they're catastrophic:

| Memory Type | Jul–Sep 2025 (baseline) | Mar 2026 | Multiplier |
|---|---|---|---|
| 512 Gbit TLC NAND (SSD supply) | ~$2.70 | ~$23 | **8.5–9x** |
| DDR5 16 Gbit | ~$10 | ~$40 | **6–6.7x** |
| DDR4 16 Gbit | ~$8 | ~$80 | **~9x** |

SSDs are worse than RAM at the spot price level. Consumer retail prices have a "buffer" — existing inventory absorbs the shock with a lag. When that buffer depletes, retail prices surge to match. **The doubling we've seen so far is the beginning, not the peak.**

---

## 1TB Retail Price Trend (Perplexity, Dec 2025 – Mar 2026)

| Period | Mainstream 1TB Range | Samsung 990 Pro |
|--------|---------------------|-----------------|
| Dec 2025 | $100 – $150 | ~$140 – $150 |
| Jan 2026 | $140 – $160 | ~$150 – $160 |
| Feb 2026 | $160 – $180 | ~$180 – $190 |
| Mar 2026 | $180 – $220 | ~$200 – $213 |

---

## 2TB NVMe Retail Prices (Gamers Nexus / Newegg, ~Mar 2026)

| Drive | Nov 2025 | Mar 2026 | Increase |
|---|---|---|---|
| Crucial P310 2TB | $145 | $300 | +107% |
| WD SN850X 2TB | $190 | $350 | +84% |
| Kingston NV3 2TB | $150 | $380 | **+153%** |
| Samsung 990 Pro 2TB | $190 | $400 | +111% |
| **Average** | **$169** | **$358** | **+113.7%** |

2TB SATA SSDs: $150 → $350.

---

## Specific 1TB Model Data Points (Perplexity)

| Model | Oct/Nov 2025 Low | Mar 2026 Price | % Increase |
|-------|-----------------|----------------|------------|
| Samsung 990 Pro 1TB | ~$100 | $199 – $213 | ~100% |
| WD Black SN850X 1TB | $108 (BF 2025) | $194 – $200 | ~80% |
| Crucial P310 1TB | $69 (Oct 2025) | $140 – $160 | ~120% |
| Silicon Power UD90 1TB | $69 (Oct 2025) | $143 – $158 | ~120% |
| Samsung 9100 Pro 1TB | $124 | $209 | ~69% |

---

## Root Causes

### AI Is Eating the World's Flash
- Nvidia's ICMS (Inference Context Memory Storage) projected at **2.8% of all global NAND demand in 2026**, **9.3% in 2027** — more than tripling in one year
- Enterprise SSD market spending grew **97.3%** in Q2 2025 alone
- Azure, AWS, and Microsoft each bought more than 10,000 units in data center buildouts
- Hard drive shortages are pushing hyperscalers to substitute with enterprise SSDs, further crowding out consumer supply
- AI/datacenter customers getting 40-60% of NAND production priority

### Manufacturers Are Deliberately Making It Worse
- Samsung pushed 20-30% wholesale price hikes in supply negotiations
- NAND wafer spot prices up 17% in Nov 2025 alone
- Contract prices up 33-60% Q1 2026
- **At peak demand, Samsung cut NAND wafer output: 4.9M → 4.68M (less than their 2024 cuts)**
- **SK Hynix also cutting: 1.9M → 1.7M wafers**
- This is not a supply crunch they're scrambling to fix. They are deliberately constraining supply to protect margins — the same DRAM cartel playbook, same companies, same behavior.

### Supply Chain is Effectively Sold Out
- **Kioxia** (14% global market share, #3): *"This year's production is already sold out."*
- **Western Digital CEO** (Q2 2026 earnings): *"We're pretty much sold out for calendar 2026."* — 89% of revenue now comes from cloud/enterprise
- Valve confirmed Steam Deck out of stock "due to memory and storage shortages"
- Faison (NAND controller mfr) began requesting prepayments; 8GB eMMC modules went from $1.50 to $20 in one year; under 30% fulfillment rate
- Consumer inventory at major retailers depleted by late March

### Market Concentration Makes This Structural
- Samsung, Micron, SK Hynix control 93% of DRAM market and 62.9% of NAND market combined
- Same oligopoly, same pricing power, same history of collusion
- YMTC (Chinese newcomer, ~7% share) is also raising prices in lockstep rather than undercutting — they're learning the same cooperative competitor game

---

## Retailer Snapshot (Late Mar 2026)

- **Best Buy**: $160 – $230 for mainstream 1TB drives
- **Newegg**: $145 – $200 mainstream, wider range with 3rd-party sellers
- Many popular models showing out-of-stock

---

## Outlook

**There is no meaningful relief coming in the near term.**

TrendForce (Mar 2026): *"With limited near-term NAND capacity expansion and surging AI demand, pricing momentum is expected to remain strong throughout 2026."*

GN assessment: *"It will probably get worse before it gets better. When the consumer inventory buffer depletes, there'll be a sudden surge in retail pricing to catch up with spot prices."* Current 1TB retail prices around $180-220 are likely heading toward $300+ if spot prices hold.

The structural drivers — AI inference demand growing 3x annually, manufacturers running oligopoly supply management, hard drives also in shortage — are not 1-2 quarter problems. The DRAM cartel pricing cycles historically lasted years. The 2024 norm of ~$40/TB is not coming back on any visible horizon. Anyone building systems or stocking storage products in 2026-2027 should plan around $150-200/TB as the new floor, with serious upside risk.

---

## Sources

- Gamers Nexus "SSDs: WTF?" (video transcript, Mar 2026)
- Tom's Hardware SSD price tracking 2026
- Qootec SSD price trend 2026 forecast
- Technetbooks SSD prices forecast 2026
- Pangoly price history (Samsung 990 Pro)
- Hardware Busters NVMe price rise analysis
- TrendForce NAND market data via Acemagic/oscooshop analysis
- How-To Geek SSD buying guide
- IDC global memory shortage crisis analysis
- DCD (Data Center Dynamics) enterprise SSD report
- Chosen Biz / Omdia NAND wafer output data
- DRAM Exchange / dramchange.com spot price data
