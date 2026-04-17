# Gemini CLI - Project Context: EA Mean Reversion Prototype

## Project Overview
This project is an Expert Advisor (EA) for MetaTrader 5 written in MQL5. It implements a **Mean Reversion** strategy based on EMA, ATR bands, RSI, and ADX filters.

## Strategy Logic
- **Mean:** EMA on Entry Timeframe.
- **Deviation:** ATR bands around the EMA.
- **Regime Filter:** 
    - ADX < `InpADX_Max` (to ensure range-bound market).
    - EMA Slope < `InpMaxSlope`.
- **Stretch Filter:** Price must close outside the ATR bands and be at least `InpMinStretchATR` away from the EMA.
- **Entry Trigger:** 
    - Price must return and close back inside the ATR band.
    - RSI confirmation (Threshold + Direction).
    - Optional Wick confirmation.
- **Risk Management:** 
    - Percentage-based position sizing.
    - Daily loss and trade limits.
    - Max 1 position per symbol.

## Artifacts
- `MeanReversionEA.mq5`: Complete source code for the EA.

## Implementation Details
The code is modular and divided into the following key functions:
- `OnInit()` / `OnDeinit()` / `OnTick()`: Standard MQL5 event handlers.
- `IsNewBar()`: Ensures signals are only checked at the start of a new candle.
- `UpdateIndicators()`: Refreshes handles and buffers.
- `SessionFilterAllowsTrade()`: Handles time-based trading windows.
- `MarketRegimeAllowsTrade()`: Validates ADX and EMA slope.
- `CheckLongSetup()` / `CheckShortSetup()`: Core signal logic using closed candles (`[1]` and `[2]`).
- `ExecuteLongTrade()` / `ExecuteShortTrade()`: Market execution and SL/TP placement.
- `CalculateLotByRisk()`: Dynamic position sizing based on SL distance.
- `ManageOpenPosition()`: Handles Time Stop and Emergency Exit (band re-break).

## Configuration
All critical parameters are exposed as `input` variables:
- `InpEntryTimeframe` / `InpFilterTimeframe`
- `InpEMA_Mean_Period` / `InpEMA_Filter_Period` / `InpATR_Period` / `InpRSI_Period` / `InpADX_Period`
- `InpAtrBandMultiplier` / `InpMinStretchATR` / `InpMinSL_ATR` / `InpMaxSL_ATR`
- `InpRSI_Long_Threshold` / `InpRSI_Short_Threshold`
- `InpRiskPercent` / `InpMaxDailyLossPercent`
- `InpMaxBarsInTrade` / `InpStopBufferPoints` / `InpMaxSpreadPoints`

## Status
- **V1.00 Prototype:** Implemented and saved in `MeanReversionEA.mq5`.
- **Pending Features:** News Filter (placeholder/stub implemented).

---
*Created by Gemini CLI - April 17, 2026*
