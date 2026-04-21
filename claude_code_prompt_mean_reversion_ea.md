# Claude Code Prompt: Mean Reversion Expert Advisor for MetaTrader 5

Copy everything below this line into Claude Code.

---

I need you to build a production-quality Mean Reversion Expert Advisor (EA) for MetaTrader 5 in MQL5. This is not a toy — it will be forward-tested on demo for months before going live, so code quality, logging, and testability matter. Read this entire brief before writing any code. Ask me clarifying questions if anything is ambiguous before you start.

## Project structure

Create the following files:
- `MeanReversionEA.mq5` — main EA file
- `/Include/MR_Signals.mqh` — entry/exit signal logic
- `/Include/MR_Filters.mqh` — regime and session filters
- `/Include/MR_RiskManager.mqh` — position sizing and risk calculations
- `/Include/MR_TradeManager.mqh` — order execution, partial exits, trailing
- `/Include/MR_Logger.mqh` — structured CSV logging for later analysis

All parameters must be exposed as `input` variables with sensible defaults and comments. No magic numbers inside functions.

## Core strategy

**Setup (entry signal):**
- Bollinger Bands on close price, default period 20, default deviation 2.0
- RSI with default period 14
- Entry long: price closes below lower BB AND RSI < 30 (configurable oversold level)
- Entry short: price closes above upper BB AND RSI > 70 (configurable overbought level)
- Both thresholds must be `input` parameters

**Exit signal:**
- Primary: price touches the middle BB (SMA 20) — this is the mean reversion target
- Secondary: fixed stop loss in ATR multiples (default 1.5 × ATR(14))
- Time stop: close position if still open after N bars (default 24 bars on M15 = 6 hours) — mean reversion that doesn't revert within a window usually means trend, get out
- All three exit reasons must be logged separately so I can analyze which exits are profitable

**Partial exits (important — don't skip this):**
- Take 50% off at 0.5 × distance from entry to middle BB (halfway target)
- Move stop to breakeven when partial is taken
- Let remaining 50% ride to middle BB or time stop
- This must be toggleable via `input bool UsePartialExits`

## Filters (regime detection — this is critical)

The EA must NOT trade in trending markets. Implement a layered filter system:

**Filter 1: ADX trend filter**
- Calculate ADX(14) on the current timeframe
- Only allow entries when ADX < threshold (default 25, exposed as input)
- When ADX > threshold, EA should log "skipped entry: trending market" and do nothing

**Filter 2: Higher timeframe regime**
- Check ADX(14) on H4 timeframe as well
- If H4 ADX > 30 AND H4 trend direction opposes trade direction, skip the trade
- This prevents fighting strong higher-timeframe trends

**Filter 3: Volatility filter**
- Calculate ATR(14) as % of price
- Skip entries when ATR% is in top 10% or bottom 10% of trailing 100-bar window
- Extreme high vol = news-driven, fat tails likely
- Extreme low vol = no movement, spread eats profit

**Filter 4: Session filter (explicit requirement)**
- Configurable trading window via inputs `TradingStartHourGMT` and `TradingEndHourGMT`
- Default window: 07:00 GMT to 21:00 GMT (avoid Asian low-liquidity hours and post-US-close widening spreads)
- **Hard close all positions at `ForceCloseHourGMT` (default 22:00 GMT)** — no exceptions, even if in profit, close before US session closes and spreads blow out
- No new entries within `NoNewEntriesBeforeCloseMinutes` (default 60 min) before force close
- Use `TimeGMT()` not `TimeCurrent()` — broker time varies, GMT is consistent

**Filter 5: News filter (stub for now)**
- Add a function `IsHighImpactNewsNear()` that returns bool
- For v1 implementation: just check if current time is within ±30 min of top-of-hour on Tuesday-Thursday (rough proxy for common news times)
- Leave a TODO to integrate proper economic calendar later (ForexFactory CSV or MT5 calendar functions)

## Risk management

**Position sizing must be risk-based, not fixed lot:**
- Input `RiskPerTradePercent` default 0.5
- Calculate lot size from: `(AccountBalance × RiskPercent/100) / (StopDistanceInPips × PipValue)`
- Round down to broker's lot step, respect min/max lot
- If calculated lot < min lot, skip trade and log "position size too small for risk level"

**Daily risk limits:**
- Input `MaxDailyLossPercent` default 2.0 — if daily loss hits this, stop trading until next day
- Input `MaxConsecutiveLosses` default 4 — pause trading for N hours after this many losses in a row
- Input `MaxOpenPositions` default 2 — cap concurrent exposure
- Input `MaxPositionsPerSymbol` default 1 — no stacking on same pair

**Spread protection:**
- Before every entry, check current spread
- Input `MaxSpreadPoints` default 20 (adjust per pair — EUR/USD might be 15, GBP/JPY 40)
- If spread > max, skip trade and log

## Multi-symbol support

EA should work attached to one chart but trade multiple symbols. Input `SymbolsToTrade` is a comma-separated string (default `"EURUSD,GBPUSD,AUDUSD,USDJPY,EURGBP"`). Parse this into an array at OnInit.

For each symbol, maintain independent:
- Last signal time (avoid re-entering within N bars)
- Current position state
- Consecutive loss counter

Run the full analysis loop for each symbol on every OnTick (or better, on new bar detection per symbol's M15).

## Logging (critical for forward testing)

Create a CSV log file in `MQL5/Files/MR_EA_Log_YYYYMMDD.csv` with columns:
`timestamp, symbol, event_type, signal_reason, entry_price, stop_loss, take_profit, lot_size, spread, atr_value, adx_m15, adx_h4, rsi, bb_position, trade_id, pnl, exit_reason, notes`

Log every:
- Entry signal (taken or skipped — with skip reason)
- Partial exit
- Full exit (with reason: TP / SL / time stop / force close / daily loss limit)
- Filter trigger (when a trade is skipped due to filter)
- Daily summary at EOD

I will analyze these logs in Python after forward testing. Make columns machine-parseable (no commas inside fields, use ISO timestamps).

## Code quality requirements

1. Use `CTrade` class from `<Trade/Trade.mqh>` for all order operations — do not use raw `OrderSend`
2. Wrap every indicator handle in proper `iXXX()` init at OnInit and release at OnDeinit
3. Check indicator buffer copy success — never assume `CopyBuffer` worked
4. All magic numbers should be `#define` or `input` — no hardcoded values in logic
5. Add defensive checks: is market open, is symbol tradeable, is account connected
6. Include a `BacktestMode` input that disables the news filter and session force-close during optimization (so backtests aren't distorted by these real-world-only features)
7. Comment every function with purpose, inputs, outputs
8. Use descriptive variable names — `rsiValue` not `r`, `isOversold` not `flag1`

## Backtesting considerations

- EA must work in MT5 Strategy Tester with "Every tick based on real ticks" mode
- Include an `input` to set deviation/slippage tolerance for orders (default 10 points)
- Include spread simulation: `input` to add N points to spread during backtest for realism (default 2)
- Write a separate Python script `analyze_results.py` that reads the CSV log and calculates:
  - Win rate, profit factor, Sharpe, max drawdown, avg win/loss
  - Breakdown by exit reason (TP vs SL vs time stop — this tells me where the edge really is)
  - Performance by hour of day, day of week, and symbol
  - Performance in different ADX regime buckets (to validate the regime filter is working)

## Deliverables checklist

Before saying you're done, confirm:
- [ ] EA compiles with zero errors and zero warnings in MetaEditor
- [ ] All inputs have descriptive comments visible in the EA settings dialog
- [ ] CSV logging works and produces parseable output
- [ ] Force-close at 22:00 GMT is tested and works even if position is in profit
- [ ] Position sizing calculation is verified with a manual test case in comments
- [ ] Multi-symbol loop handles errors per-symbol without crashing the whole EA
- [ ] Python analysis script runs on a sample log without errors
- [ ] README.md explains: how to install, how to configure, how to backtest, known limitations

## What I do NOT want

- Do not add machine learning, neural networks, or "AI" components. This is a rules-based system.
- Do not add martingale, grid, or averaging-down logic. One entry per signal, full stop loss, that's it.
- Do not optimize parameters yourself — leave defaults as stated, I'll optimize via walk-forward later.
- Do not add fancy GUI panels. This EA runs on a VPS, nobody is watching the chart.
- Do not use any third-party libraries that aren't standard MQL5 includes.

## Start here

Begin by asking me any clarifying questions you have. Then propose the file structure and a brief pseudo-code sketch of the main OnTick logic so I can approve the approach before you write the full implementation. After my approval, implement incrementally — show me each include file, let me review, then move on. Do not dump 2000 lines of code in one go.

---

End of brief. Please confirm you've read this and list your clarifying questions before writing any code.
