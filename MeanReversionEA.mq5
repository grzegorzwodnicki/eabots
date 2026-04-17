//+------------------------------------------------------------------+
//|                                              MeanReversionEA.mq5 |
//|                                  Copyright 2024, Gemini CLI EA   |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Gemini CLI EA"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//--- INPUT PARAMETERS ---

//-- Timeframes
input ENUM_TIMEFRAMES InpEntryTimeframe = PERIOD_M5;     // Entry Timeframe
input ENUM_TIMEFRAMES InpFilterTimeframe = PERIOD_M15;   // Filter Timeframe

//-- Indicator Periods
input int InpEMA_Mean_Period = 20;       // EMA Mean Period (Entry TF)
input int InpEMA_Filter_Period = 50;     // EMA Filter Period (Filter TF)
input int InpATR_Period = 14;            // ATR Period (Entry TF)
input int InpRSI_Period = 14;            // RSI Period (Entry TF)
input int InpADX_Period = 14;            // ADX Period (Filter TF)

//-- ATR / Bands / Stretch
input double InpAtrBandMultiplier = 2.0; // ATR Band Multiplier
input double InpMinStretchATR = 1.0;     // Min Stretch (ATR units)
input double InpMinSL_ATR = 1.5;         // Min SL Distance (ATR units)
input double InpMaxSL_ATR = 3.5;         // Max SL Distance (ATR units)

//-- RSI Thresholds
input int InpRSI_Long_Threshold = 30;    // RSI Long Threshold
input int InpRSI_Short_Threshold = 70;   // RSI Short Threshold

//-- ADX / Slope
input int InpADX_Max = 25;               // Max ADX for Range Regime
input int InpSlopeLookback = 3;          // EMA Slope Lookback
input double InpMaxSlope = 0.0001;       // Max EMA Slope (Adjust per symbol)

//-- Trade Management
input int InpMaxBarsInTrade = 20;        // Max Bars in Trade
input int InpStopBufferPoints = 50;      // SL Buffer (Points)
input int InpEntryBufferPoints = 0;      // Entry Buffer (Points) - reserved for future use
input int InpMaxSpreadPoints = 30;       // Max Allowed Spread (Points)

//-- Risk Management
input double InpRiskPercent = 1.0;            // Risk Per Trade (%)
input double InpMaxDailyLossPercent = 3.0;    // Max Daily Loss (%)
input int InpMaxLossesPerDay = 3;             // Max Losses Per Day
input int InpMaxTradesPerDay = 5;             // Max Trades Per Day
input int InpMaxTradesPerSymbolPerDay = 2;    // Max Trades Per Symbol Per Day

//-- Session Filter
input bool InpUseSessionFilter = false;       // Use Session Filter
input string InpSession1Start = "09:00";      // Session 1 Start (HH:MM)
input string InpSession1End = "12:00";        // Session 1 End (HH:MM)
input string InpSession2Start = "14:00";      // Session 2 Start (HH:MM)
input string InpSession2End = "17:00";        // Session 2 End (HH:MM)

//-- News Filter
input bool InpUseNewsFilter = false;          // Use News Filter (Placeholder)
input int InpNewsBlockBeforeMin = 30;         // Block Before News (Min)
input int InpNewsBlockAfterMin = 30;          // Block After News (Min)

//-- Optional Filters
input bool InpUseWickFilter = true;           // Use Wick Confirmation
input double InpWickToBodyRatio = 0.5;        // Min Wick/Body Ratio
input bool InpUseEmergencyExit = true;        // Exit if re-breaks band

//--- GLOBAL VARIABLES ---
CTrade         trade;
CPositionInfo  posInfo;
CSymbolInfo    symInfo;

int handleEMA_Mean, handleEMA_Filter, handleATR, handleRSI, handleADX;

datetime lastBarTime = 0;
int dailyTradesCount = 0;
int dailyLossesCount = 0;
double dailyProfitLoss = 0;
datetime lastDailyReset = 0;

//--- DATA BUFFERS ---
double bufferEMA_Mean[], bufferEMA_Filter[], bufferATR[], bufferRSI[], bufferADX[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    if(!symInfo.Name(_Symbol)) 
    {
        Print("Symbol initialization failed!");
        return INIT_FAILED;
    }
    
    // Initialize Handles
    handleEMA_Mean = iMA(_Symbol, InpEntryTimeframe, InpEMA_Mean_Period, 0, MODE_EMA, PRICE_CLOSE);
    handleATR = iATR(_Symbol, InpEntryTimeframe, InpATR_Period);
    handleRSI = iRSI(_Symbol, InpEntryTimeframe, InpRSI_Period, PRICE_CLOSE);
    
    handleEMA_Filter = iMA(_Symbol, InpFilterTimeframe, InpEMA_Filter_Period, 0, MODE_EMA, PRICE_CLOSE);
    handleADX = iADX(_Symbol, InpFilterTimeframe, InpADX_Period);
    
    if(handleEMA_Mean == INVALID_HANDLE || handleATR == INVALID_HANDLE || handleRSI == INVALID_HANDLE ||
       handleEMA_Filter == INVALID_HANDLE || handleADX == INVALID_HANDLE)
    {
        Print("Error initializing indicator handles.");
        return INIT_FAILED;
    }
    
    // Set Arrays as series
    ArraySetAsSeries(bufferEMA_Mean, true);
    ArraySetAsSeries(bufferEMA_Filter, true);
    ArraySetAsSeries(bufferATR, true);
    ArraySetAsSeries(bufferRSI, true);
    ArraySetAsSeries(bufferADX, true);
    
    trade.SetExpertMagicNumber(123456);
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    IndicatorRelease(handleEMA_Mean);
    IndicatorRelease(handleEMA_Filter);
    IndicatorRelease(handleATR);
    IndicatorRelease(handleRSI);
    IndicatorRelease(handleADX);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Update Daily Limits/Stats
    ResetDailyStatsIfNeeded();
    
    // 1. Manage open positions every tick (Emergency exit, Time Stop)
    if(!IsNewBar()) 
    {
        ManageOpenPosition();
        return;
    }
    
    // --- FROM HERE: ONLY ON NEW BAR ---
    
    // 2. Update indicators for the new bar
    if(!UpdateIndicators()) return;
    
    // 3. Manage open positions on the new bar as well
    ManageOpenPosition();
    
    // 4. Pre-entry filters
    if(HasOpenPosition()) return;
    if(!SessionFilterAllowsTrade()) return;
    if(InpUseNewsFilter && !NewsFilterAllowsTrade()) return;
    if(!SpreadIsAcceptable()) return;
    if(!RiskManagerAllowsNewTrade()) return;
    if(!MarketRegimeAllowsTrade()) return;
    
    // 5. Check Setups & Execute
    if(CheckLongSetup())
    {
        ExecuteLongTrade();
        return;
    }
    
    if(CheckShortSetup())
    {
        ExecuteShortTrade();
        return;
    }
}

//+------------------------------------------------------------------+
//| LOGIC FUNCTIONS                                                  |
//+------------------------------------------------------------------+

bool IsNewBar()
{
    datetime currentTime = iTime(_Symbol, InpEntryTimeframe, 0);
    if(currentTime != lastBarTime)
    {
        lastBarTime = currentTime;
        return true;
    }
    return false;
}

bool UpdateIndicators()
{
    // Copy slightly more buffers just to be safe with lookbacks
    if(CopyBuffer(handleEMA_Mean, 0, 0, 5, bufferEMA_Mean) < 5) return false;
    if(CopyBuffer(handleATR, 0, 0, 5, bufferATR) < 5) return false;
    if(CopyBuffer(handleRSI, 0, 0, 5, bufferRSI) < 5) return false;
    
    // Filter TF buffers might need more data due to slope lookback
    int requiredFilterBars = InpSlopeLookback + 5;
    if(CopyBuffer(handleEMA_Filter, 0, 0, requiredFilterBars, bufferEMA_Filter) < requiredFilterBars) return false;
    if(CopyBuffer(handleADX, 0, 0, 5, bufferADX) < 5) return false;
    
    return true;
}

bool SessionFilterAllowsTrade()
{
    if(!InpUseSessionFilter) return true;
    
    datetime now = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(now, dt);
    
    string timeStr = StringFormat("%02d:%02d", dt.hour, dt.min);
    
    bool inSession1 = (timeStr >= InpSession1Start && timeStr <= InpSession1End);
    bool inSession2 = (timeStr >= InpSession2Start && timeStr <= InpSession2End);
    
    return (inSession1 || inSession2);
}

bool NewsFilterAllowsTrade()
{
    // News filter implementation would require a news events library or web requests.
    // For this prototype, we return true and leave this as a stub.
    // TODO: Integrate an Economic Calendar API here.
    return true;
}

bool SpreadIsAcceptable()
{
    symInfo.Refresh();
    int spread = (int)symInfo.Spread();
    return (spread <= InpMaxSpreadPoints);
}

bool RiskManagerAllowsNewTrade()
{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double dailyLossLimit = accountBalance * (InpMaxDailyLossPercent / 100.0);
    
    if(dailyLossesCount >= InpMaxLossesPerDay) return false;
    if(dailyTradesCount >= InpMaxTradesPerDay) return false;
    if(dailyProfitLoss <= -dailyLossLimit) return false; // Fixed sign: if loss exceeds limit
    
    // Check per-symbol count (Simplified - assuming this EA only trades this symbol)
    // To be perfectly accurate, we should iterate history. For prototype, we use global counter.
    if(dailyTradesCount >= InpMaxTradesPerSymbolPerDay) return false;
    
    return true;
}

bool MarketRegimeAllowsTrade()
{
    // ADX Filter (Index 1 is the last closed candle on FilterTF)
    // Note: To be perfectly synchronized, one should fetch ADX based on exact time, 
    // but MQL5 CopyBuffer(0,0,x) on a different timeframe handles current alignment implicitly.
    if(bufferADX[1] >= InpADX_Max) return false;
    
    // Slope Filter (Index 1 is closed, index [1+Lookback] is past)
    double slope = bufferEMA_Filter[1] - bufferEMA_Filter[1 + InpSlopeLookback];
    if(MathAbs(slope) >= InpMaxSlope) return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| SETUP CHECKS                                                     |
//| Note: 1 = candle that just closed (Signal).                      |
//|       2 = candle before that (Breakout).                         |
//+------------------------------------------------------------------+

bool CheckLongSetup()
{
    double lowerBandPrev = bufferEMA_Mean[2] - (bufferATR[2] * InpAtrBandMultiplier);
    double lowerBandCurr = bufferEMA_Mean[1] - (bufferATR[1] * InpAtrBandMultiplier);
    
    double closePrev = iClose(_Symbol, InpEntryTimeframe, 2);
    double closeCurr = iClose(_Symbol, InpEntryTimeframe, 1);
    
    double stretchDistance = bufferEMA_Mean[2] - closePrev;
    
    // 1. Breakout Candle must have closed below the lower band
    if(closePrev >= lowerBandPrev) return false;
    
    // 2. Must be stretched enough
    if(stretchDistance <= bufferATR[2] * InpMinStretchATR) return false;
    
    // 3. Trigger Candle must close back ABOVE the lower band
    if(closeCurr <= lowerBandCurr) return false;
    
    // 4. RSI Filters
    if(bufferRSI[2] >= InpRSI_Long_Threshold) return false;
    if(bufferRSI[1] <= bufferRSI[2]) return false;
    
    // 5. Wick Filter
    if(InpUseWickFilter && !SignalCandleHasLongWick(true, 1)) return false;
    
    return true;
}

bool CheckShortSetup()
{
    double upperBandPrev = bufferEMA_Mean[2] + (bufferATR[2] * InpAtrBandMultiplier);
    double upperBandCurr = bufferEMA_Mean[1] + (bufferATR[1] * InpAtrBandMultiplier);
    
    double closePrev = iClose(_Symbol, InpEntryTimeframe, 2);
    double closeCurr = iClose(_Symbol, InpEntryTimeframe, 1);
    
    double stretchDistance = closePrev - bufferEMA_Mean[2];
    
    // 1. Breakout Candle must have closed above the upper band
    if(closePrev <= upperBandPrev) return false;
    
    // 2. Must be stretched enough
    if(stretchDistance <= bufferATR[2] * InpMinStretchATR) return false;
    
    // 3. Trigger Candle must close back BELOW the upper band
    if(closeCurr >= upperBandCurr) return false;
    
    // 4. RSI Filters
    if(bufferRSI[2] <= InpRSI_Short_Threshold) return false;
    if(bufferRSI[1] >= bufferRSI[2]) return false;
    
    // 5. Wick Filter
    if(InpUseWickFilter && !SignalCandleHasLongWick(false, 1)) return false;
    
    return true;
}

bool SignalCandleHasLongWick(bool isLong, int shift)
{
    double open = iOpen(_Symbol, InpEntryTimeframe, shift);
    double close = iClose(_Symbol, InpEntryTimeframe, shift);
    double high = iHigh(_Symbol, InpEntryTimeframe, shift);
    double low = iLow(_Symbol, InpEntryTimeframe, shift);
    
    double body = MathAbs(open - close);
    // Avoid division by zero if body is extremely small (doji)
    if(body < _Point) body = _Point;
    
    if(isLong)
    {
        double lowerWick = MathMin(open, close) - low;
        return (lowerWick > body * InpWickToBodyRatio);
    }
    else
    {
        double upperWick = high - MathMax(open, close);
        return (upperWick > body * InpWickToBodyRatio);
    }
}

//+------------------------------------------------------------------+
//| EXECUTION                                                        |
//+------------------------------------------------------------------+

void ExecuteLongTrade()
{
    symInfo.RefreshRates();
    double ask = symInfo.Ask();
    double signalLow = iLow(_Symbol, InpEntryTimeframe, 1);
    
    double slByStructure = signalLow - (InpStopBufferPoints * _Point);
    double slByATR = ask - (bufferATR[1] * InpMinSL_ATR);
    
    // Logic: Select the SL that is lower (gives more breathing room)
    double sl = MathMin(slByStructure, slByATR);
    
    double slDistance = ask - sl;
    if(slDistance <= 0) return;
    if(slDistance > bufferATR[1] * InpMaxSL_ATR) return;
    
    double tp = bufferEMA_Mean[1];
    
    double lot = CalculateLotByRisk(slDistance);
    if(lot <= 0) return;
    
    if(trade.Buy(lot, _Symbol, ask, sl, tp, "MR Long"))
    {
        LogTradeEntry("LONG", ask, sl, tp, lot);
        dailyTradesCount++;
    }
}

void ExecuteShortTrade()
{
    symInfo.RefreshRates();
    double bid = symInfo.Bid();
    double signalHigh = iHigh(_Symbol, InpEntryTimeframe, 1);
    
    double slByStructure = signalHigh + (InpStopBufferPoints * _Point);
    double slByATR = bid + (bufferATR[1] * InpMinSL_ATR);
    
    // Logic: Select the SL that is higher (gives more breathing room)
    double sl = MathMax(slByStructure, slByATR);
    
    double slDistance = sl - bid;
    if(slDistance <= 0) return;
    if(slDistance > bufferATR[1] * InpMaxSL_ATR) return;
    
    double tp = bufferEMA_Mean[1];
    
    double lot = CalculateLotByRisk(slDistance);
    if(lot <= 0) return;
    
    if(trade.Sell(lot, _Symbol, bid, sl, tp, "MR Short"))
    {
        LogTradeEntry("SHORT", bid, sl, tp, lot);
        dailyTradesCount++;
    }
}

double CalculateLotByRisk(double slDistancePoints)
{
    double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * (InpRiskPercent / 100.0);
    
    symInfo.Refresh();
    double tickValue = symInfo.TickValue();
    double tickSize = symInfo.TickSize();
    
    if(slDistancePoints <= 0 || tickValue <= 0 || tickSize <= 0) return 0;
    
    // Calculation:
    // Loss in money = Lot * (SL distance in points / Tick Size) * Tick Value
    // Lot = Risk Money / ( (SL distance / TickSize) * TickValue )
    double pointsLost = slDistancePoints / tickSize;
    double lot = riskMoney / (pointsLost * tickValue);
    
    // Normalize lot
    double minLot = symInfo.LotMin();
    double maxLot = symInfo.LotMax();
    double lotStep = symInfo.LotStep();
    
    lot = MathFloor(lot / lotStep) * lotStep;
    if(lot < minLot) return 0;
    if(lot > maxLot) lot = maxLot;
    
    return lot;
}

//+------------------------------------------------------------------+
//| POSITION MANAGEMENT                                              |
//+------------------------------------------------------------------+

bool HasOpenPosition()
{
    return PositionSelect(_Symbol);
}

void ManageOpenPosition()
{
    if(!HasOpenPosition()) return;
    
    long posType = PositionGetInteger(POSITION_TYPE);
    long entryTime = PositionGetInteger(POSITION_TIME);
    
    // 1. Time Stop
    int barsPassed = iBarShift(_Symbol, InpEntryTimeframe, (datetime)entryTime);
    if(barsPassed >= InpMaxBarsInTrade)
    {
        LogTradeExit("TIME_STOP", PositionGetDouble(POSITION_PRICE_OPEN), PositionGetDouble(POSITION_PRICE_CURRENT));
        trade.PositionClose(_Symbol);
        return;
    }
    
    // 2. Emergency Exit (using current open candle [0])
    if(InpUseEmergencyExit)
    {
        // Require at least EMA and ATR data for the current open candle
        if(CopyBuffer(handleEMA_Mean, 0, 0, 1, bufferEMA_Mean) < 1) return;
        if(CopyBuffer(handleATR, 0, 0, 1, bufferATR) < 1) return;
        
        double closeCurr = iClose(_Symbol, InpEntryTimeframe, 0); // Current live price
        
        if(posType == POSITION_TYPE_BUY)
        {
            double lowerBand = bufferEMA_Mean[0] - (bufferATR[0] * InpAtrBandMultiplier);
            if(closeCurr < lowerBand)
            {
                LogTradeExit("EMERGENCY_EXIT_LONG", PositionGetDouble(POSITION_PRICE_OPEN), closeCurr);
                trade.PositionClose(_Symbol);
                return;
            }
        }
        else if(posType == POSITION_TYPE_SELL)
        {
            double upperBand = bufferEMA_Mean[0] + (bufferATR[0] * InpAtrBandMultiplier);
            if(closeCurr > upperBand)
            {
                LogTradeExit("EMERGENCY_EXIT_SHORT", PositionGetDouble(POSITION_PRICE_OPEN), closeCurr);
                trade.PositionClose(_Symbol);
                return;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| HELPER LOGGING / STATS                                           |
//+------------------------------------------------------------------+

void ResetDailyStatsIfNeeded()
{
    datetime today = iTime(_Symbol, PERIOD_D1, 0);
    if(today != lastDailyReset)
    {
        // Ideally, query history to verify actual daily PnL, but as a prototype we reset globals.
        dailyTradesCount = 0;
        dailyLossesCount = 0;
        dailyProfitLoss = 0;
        lastDailyReset = today;
    }
}

void LogTradeEntry(string dir, double price, double sl, double tp, double lot)
{
    symInfo.Refresh();
    PrintFormat("ENTRY %s | Symbol: %s | Time: %s | Price: %f | SL: %f | TP: %f | Lot: %f | ADX: %f | Spread: %d", 
                dir, _Symbol, TimeToString(TimeCurrent()), price, sl, tp, lot, bufferADX[1], (int)symInfo.Spread());
}

void LogTradeExit(string reason, double entryPrice, double exitPrice)
{
    double rDist = MathAbs(entryPrice - exitPrice);
    PrintFormat("EXIT %s | Time: %s | Entry: %f | Exit: %f | Diff: %f", 
                reason, TimeToString(TimeCurrent()), entryPrice, exitPrice, rDist);
}
//+------------------------------------------------------------------+
