# Claude Code Prompt: Build MT5 Tick Scalper EA

I want you to build a production-ready MetaTrader 5 Expert Advisor (EA) in MQL5 that performs tick-based scalping on XAUUSD (Gold). This is a real trading bot, so code quality, safety checks, and correctness matter more than speed of delivery.

## Your Task

Build a complete, compilable MQL5 project with a modular architecture. Work step by step: plan the structure first, then create files one at a time, explaining decisions as you go. After each major file, pause briefly so I can review before you continue.

Do **not** write everything in one massive response. Break it into logical commits.

## Working Method

1. **First**, create a project plan: list all files you'll create, in what order, and why.
2. **Second**, create the folder structure and a `README.md` with installation instructions and a warning about prop firm HFT restrictions.
3. **Third**, build the include files (`.mqh`) in dependency order: Logger → SessionFilter → RiskManager → TradeManager → SignalEngine.
4. **Fourth**, build the main `TickScalperEA.mq5` that wires everything together.
5. **Fifth**, do a self-review: walk through the code and flag anything that might fail to compile or behave incorrectly at runtime. Fix those issues.
6. **Sixth**, give me a final summary: file tree, how to install, how to run the first backtest, and the top 3 parameters to tune first.

If you have questions about ambiguous requirements, ask before coding — don't guess.

## Project Specification

### Folder Structure

```
TickScalperEA/
├── TickScalperEA.mq5
├── Include/
│   ├── Logger.mqh
│   ├── SessionFilter.mqh
│   ├── RiskManager.mqh
│   ├── TradeManager.mqh
│   └── SignalEngine.mqh
└── README.md
```

### Trading Strategy: Tick-Based Scalping on XAUUSD

The EA reads every tick via `OnTick()` and maintains a rolling buffer of the last N ticks (default 50). It generates signals from three sources and combines them:

1. **Tick momentum**: In the buffer, count bullish ticks (price went up) vs bearish ticks (price went down). If ≥70% moved in one direction, emit a directional signal.

2. **Micro breakout**: Track the highest and lowest bid in the buffer. If the current tick breaks above the high by MicroBreakoutPoints (default 10) → buy signal; breaks below the low → sell signal.

3. **Spread sanity**: If current spread > MaxSpreadPoints (default 30), block all signals this tick. Also compute rolling average spread over last 100 ticks; if current spread > 3× average, log a warning and block.

Combination modes (configurable enum `SignalConfirmationMode`): `ANY_SIGNAL`, `TWO_OF_THREE` (default), `ALL_THREE`.

### Entry Rules

- Max concurrent positions: input `MaxConcurrentPositions` (default 1).
- Cooldown after closing a position: `CooldownMs` (default 2000ms) before a new entry is allowed.
- Block entries outside the trading session.
- Block entries if any risk management lockout is active.

### Exit Rules

Every position must have:
- Hard SL: `StopLossPoints` (default 35 points).
- Hard TP: `TakeProfitPoints` (default 50 points).
- Time-based exit: close at market if held > `MaxHoldSeconds` (default 120).
- Optional trailing stop: activates after `TrailingActivationPoints` (default 20) of favorable movement, trails by `TrailingDistancePoints` (default 15). Toggle via `UseTrailingStop` (default true).

### Risk Management (critical — this is what keeps drawdown low)

Implement in `RiskManager.mqh`:

- **Daily loss limit**: `MaxDailyLossUSD` (default 50). Halt trading for the rest of the day if floating + closed P/L for today ≤ −MaxDailyLossUSD. Reset at broker midnight.
- **Daily profit target** (optional): `MaxDailyProfitUSD` (default 0 = disabled). Halt trading for the day once reached.
- **Max daily trades**: `MaxDailyTrades` (default 500).
- **Total drawdown limit**: `MaxTotalDrawdownPercent` (default 4.0). Halt all trading permanently for this session if `equity ≤ initialBalance * (1 − pct/100)`. Store initial balance on first `OnInit()` run in a global variable so it persists across restarts.
- **Max open risk**: `MaxOpenRiskUSD` (default 30). Sum of `(entry − SL) * lots * tickValue / tickSize` across open positions must not exceed this before a new entry.
- **Consecutive loss lockout**: after `ConsecutiveLossLimit` (default 5) losing trades in a row, pause for `LockoutMinutes` (default 30). Reset on first win.

### Session & Time Filter

In `SessionFilter.mqh`:

- `StartHour` / `EndHour` (server time, defaults 8 and 20). Inclusive of start, exclusive of end.
- Friday cutoff: `FridayEndHour` (default 18) — block trading after this on Fridays, close all open positions at the cutoff.
- News blackout stub: `NewsBlackoutMinutes` (default 0). Provide function `IsNewsBlackout()` that currently returns false — add a `// TODO: integrate news calendar` comment.

### Position Sizing

In `TradeManager.mqh`:

- Default: fixed lot size `LotSize` (default 0.01).
- Optional risk-based sizing: if `UseRiskBasedSizing` is true, calculate lots so SL hit equals `RiskPerTradePercent` of balance (default 0.25%).
- Always normalize to `SYMBOL_VOLUME_STEP` and clamp to `[SYMBOL_VOLUME_MIN, SYMBOL_VOLUME_MAX]`.

### Trade Manager

Wrap `CTrade`. Must provide:

- `OpenBuy(lots, sl, tp, comment)` / `OpenSell(lots, sl, tp, comment)` — returns ticket or 0 on failure.
- `CloseAll()`, `CloseByTicket(ticket)`, `ModifySLTP(ticket, sl, tp)`.
- `CountOpenPositions()` filtered by magic number.
- Retry up to 3 times on `TRADE_RETCODE_REQUOTE` or `TRADE_RETCODE_PRICE_OFF` with refreshed prices.
- Use `MagicNumber` input (default 20260420).
- Log every trade action via Logger.

### Logger

In `Logger.mqh`:

- Log levels enum: `LOG_DEBUG`, `LOG_INFO`, `LOG_WARN`, `LOG_ERROR`. Input `LogLevel` (default `LOG_INFO`).
- Every call writes to both `Print()` and a CSV file `MQL5/Files/TickScalper_YYYYMMDD.csv`.
- CSV header (written once per day on first log): `timestamp,level,event_type,ticket,symbol,direction,lots,price,sl,tp,profit,comment`.
- Open the file in append mode (`FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI`, seek to end).
- Flush after each write so logs survive crashes.

### Input Parameters (in main EA file)

Group with `input group "..."`:

```
--- General ---
input long    MagicNumber = 20260420;
input string  TradeComment = "TickScalper";
input ENUM_LOG_LEVEL LogLevel = LOG_INFO;
input string  SymbolOverride = ""; // empty = current chart symbol

--- Position Sizing ---
input double  LotSize = 0.01;
input bool    UseRiskBasedSizing = false;
input double  RiskPerTradePercent = 0.25;

--- Entry ---
input int     TickBufferSize = 50;
input ENUM_SIGNAL_MODE SignalConfirmationMode = TWO_OF_THREE;
input double  MomentumThresholdPercent = 70.0;
input int     MicroBreakoutPoints = 10;
input int     MaxSpreadPoints = 30;
input int     CooldownMs = 2000;
input int     MaxConcurrentPositions = 1;

--- Exit ---
input int     TakeProfitPoints = 50;
input int     StopLossPoints = 35;
input int     MaxHoldSeconds = 120;
input bool    UseTrailingStop = true;
input int     TrailingActivationPoints = 20;
input int     TrailingDistancePoints = 15;

--- Risk Management ---
input double  MaxDailyLossUSD = 50.0;
input double  MaxDailyProfitUSD = 0.0;
input int     MaxDailyTrades = 500;
input double  MaxTotalDrawdownPercent = 4.0;
input double  MaxOpenRiskUSD = 30.0;
input int     ConsecutiveLossLimit = 5;
input int     LockoutMinutes = 30;

--- Session Filter ---
input int     StartHour = 8;
input int     EndHour = 20;
input int     FridayEndHour = 18;
input int     NewsBlackoutMinutes = 0;
```

### Technical Requirements

- **MQL5 only** (not MQL4). Use `CTrade`, `CPositionInfo`, `CSymbolInfo`.
- Validate all inputs in `OnInit()`. Return `INIT_PARAMETERS_INCORRECT` with a clear `Print()` error if any input is invalid (e.g. `StopLossPoints ≤ 0`, `EndHour ≤ StartHour`).
- Detect symbol digits (`SYMBOL_DIGITS`) — XAUUSD is typically 2 or 3 digits, so point conversion must be dynamic: `points * _Point`.
- Use `OnTimer()` for periodic checks (run every 1 second): max-hold exit, Friday cutoff, daily reset at midnight.
- `OnTick()` must be fast — no disk I/O unless a trade actually happens. Cache expensive lookups.
- Release all handles in `OnDeinit()`.
- Print a summary report in `OnDeinit()`: total trades, wins, losses, win rate, gross profit, gross loss, profit factor, max equity DD, avg win, avg loss, avg hold time.
- Zero compile warnings.

### Code Quality

- File-level header comment on every file: purpose, version, author, date.
- Every public function needs a doc comment: `/// @brief ... @param ... @return ...`.
- Meaningful variable names. No magic numbers — everything is an input or named constant.
- Consistent indentation (4 spaces), consistent brace style.

## Deliverable Checklist

Before you finish, confirm all of the following:

- [ ] All files created in the structure above.
- [ ] Main EA compiles cleanly (state this explicitly; if you can't compile, say so and explain what's needed).
- [ ] README explains installation, compilation, recommended backtest settings, and includes the prop firm warning.
- [ ] Every risk management limit from the spec is implemented and actively checked.
- [ ] Summary report prints in `OnDeinit()`.
- [ ] Final message to me lists: file tree, install steps, first-backtest recipe, and top 3 parameters to tune.

Start now with step 1 (project plan).
