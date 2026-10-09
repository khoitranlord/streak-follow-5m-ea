# Performance — StreakFollow5m

Backtest: Databento NQ 1-minute data aggregated to M5, 2021-01 → 2026-09.
Engine applies 0.25pt slippage per side + additional 1.1pt round-trip
haircut per trade → **~1.6pt total cost** (≈2% of the ~80pt median stop).

## Headline (RTH session, streak k=5 + ER20>0.4, target 8R, EOD exit)

| Metric | Value |
|--------|-------|
| Trades | 813 (~140/yr, ~2.4/week) |
| Win rate | 45% |
| **Net expectancy** | **+0.158R** |
| Total | +129R |
| Max drawdown | ~15R |
| Median hold | ~5.5h (flat by session end) |
| Longest losing streak | 8 |

Per-year net R: **+32 / +27 / +28 / +31 / +10 / 0**
(2021→2026) — positive every year but **2025-26 weakening**
(momentum regime softer recently — see caveats).

## Hold-time / exit sweep (streak k=5, no ER filter)

| Config | n | win | net exp | total |
|--------|---|-----|---------|-------|
| R=2, cap 3h | 2,263 | 49% | +0.052R | +117R |
| R=3, cap 24h | 1,620 | 35% | +0.158R | +256R |
| **R=8, EOD** | **1,747** | **43%** | **+0.095R** | **+167R** |
| trail24 | 2,019 | 41% | +0.058R | +118R |
| liquidity-pool exit | ~1,000 | ~30% | ≈0 | ~0-40R |

Larger targets don't help intraday — most trades resolve at EOD
mark-to-market. The edge IS the intraday drift after a clean streak.

## Regime filter (ER20)

| Filter | n | net exp | total | maxDD |
|--------|---|---------|-------|-------|
| none | 1,747 | +0.095R | +167R | 34R |
| ER20 > 0.2 | 1,320 | +0.138R | +182R | 26R |
| **ER20 > 0.4** | **813** | **+0.158R** | **+129R** | **15R** |

ER filters out streaks formed inside chop — halves the drawdown.

## Dollar sim ($100k, MNQ $2/pt, DD ≤ 10%)

Risk 0.6%/trade (median ~4 MNQ contracts @ 80pt stop):

- $100k → **~$214k** (+115% over 5.7yr flat-risk equivalent)
- maxDD ≈ 8.6% (backtest — expect 1.5-2x worse live)

## Caveats

- **Momentum regime is decaying**: 2025 +10R, 2026 ~flat. Pair with a
  mean-reversion system (RejectionBlock5m) which is currently strengthening.
- This is a tail-driven system: 8+ consecutive losses are normal — do NOT
  reduce RRTarget or add a trailing stop, it kills the edge.
- Entry is market-on-open-of-bar: spread sensitivity is real; MaxSpreadPts
  guard included.
