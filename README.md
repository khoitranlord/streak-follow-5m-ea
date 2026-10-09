# StreakFollow5m — intraday momentum continuation (MT5 EA)

Trend-following EA for NAS100/US100.cash. After 5 consecutive
same-direction M5 closes **in a clean trend** (efficiency ratio filter),
follow the move — most trades exit at end of day.

## Strategy

```
signal bar (M5 close, RTH 09:30–15:30 ET):
  1. 5 consecutive closes in the same direction (streak)
  2. ER20 > 0.4 with matching sign:
       ER = |close - close[20 bars ago]| / sum(|close-to-close|)
     → filters out fake streaks inside chop

entry  = MARKET at next bar open
stop   = streak extreme -/+ 0.1 * ATR(14, M5)   (median ~80 pts)
target = 8R  (hit only ~4% of the time — its job is to NOT cap winners)
exit   = stop | target | FORCE-FLAT at 15:55 ET (intraday only)
one position at a time; optionally blocks if ANY position is open
         (BlockAnyPos=true — don't fight another EA like RejectionBlock5m)
```

## Why it works

Momentum continuation on NQ is real — fading 5-bar streaks loses ~-1.0R
per trade in backtest. The edge lives in the **fat right tail**: ~45%
winners pay for the losers, so never trail or take profit early.
Tested variants that all LOSE to the fixed-target version: trailing stop,
exit at opposite liquidity pool (PDH/PDL, day extreme, swing).

## Presets

`presets/SF5m_ftmo_<size>.set` for 10k/25k/50k/100k/200k FTMO accounts.
RiskPct=0.6%, MaxDailyLossUSD ≈ 3% of account, MaxTradesDay=2.

## Install

1. Copy `StreakFollow5m.mq5` → `MQL5/Experts/`, compile in MetaEditor (F7)
2. Attach to a US100/NAS100 chart (any timeframe — EA reads M5 internally)
3. Load the matching `.set` preset, enable Algo Trading

## Pairs well with

`RejectionBlock5m` — mean-reversion scalper, daily P&L correlation ≈ -0.02
(RB wins in choppy/sweep days, SF wins in trend days).
See https://github.com/khoitranlord/rb5m-ea

Backtest methodology & full stats: see `PERFORMANCE.md`.
