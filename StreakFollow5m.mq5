//+------------------------------------------------------------------+
//| StreakFollow5m.mq5 — intraday momentum continuation on M5 (NQ)     |
//| 5 consecutive same-direction M5 closes + ER20>0.4 (clean trend)    |
//| -> market at next bar open, stop = streak extreme -+ 0.1*ATR,      |
//| target 8R (rarely hit: keeps winners open), force-exit at EOD.     |
//| Backtest 2021-2026/09: n=813, win 45%, net +0.158R after 1.6pt     |
//| slippage/trade. See PERFORMANCE.md. Session: RTH 09:30-16:00 ET.   |
//+------------------------------------------------------------------+
#property version   "1.00"
#property strict
#include <Trade\Trade.mqh>

input group "=== Session (New York time) ==="
input int      SessStartMinET = 570;    // 09:30 ET — signals allowed from
input int      LastSignalMinET= 930;    // no new signals at/after 15:30 ET
input int      ForceExitMinET = 955;    // flatten everything at 15:55 ET

input group "=== Streak rules ==="
input int      StreakK        = 5;      // consecutive same-direction closes
input int      ERWindow       = 20;     // efficiency-ratio window (bars)
input double   ERMin          = 0.4;    // |ER| threshold, sign must match
input double   StopBufATR     = 0.1;    // stop = streak extreme -+ buf*ATR
input double   RRTarget       = 8.0;    // target = RR * risk (keeps tail open)

input group "=== Risk / guards ==="
input double   RiskPct        = 0.5;    // % equity risked per trade
input double   MaxDailyLossUSD= 1500.0; // stop day after -$X realized+open
input int      MaxTradesDay   = 2;      // max entries per NY day
input double   MaxSpreadPts   = 3.0;    // skip if spread > N points
input int      MaxConsecLosses= 3;      // stop day after N losing exits
input double   MinStopPts     = 15.0;   // skip if stop distance < N points
input double   MaxStopPts     = 250.0;  // skip insane stops (news spikes)

input group "=== Options ==="
input bool     BlockAnyPos    = true;   // skip if ANY position open on symbol
input int      Magic          = 260923;

CTrade  trade;
int     atrHandle;
datetime lastBarTime = 0;
int      tradesToday = 0;
double   dayStartEquity = 0;
datetime curDay = 0;

//+------------------------------------------------------------------+
// NY time helpers (same as RejectionBlock)
//+------------------------------------------------------------------+
bool IsEDT(datetime t)
{
   MqlDateTime dt; TimeToStruct(t, dt);
   if(dt.mon < 3 || dt.mon > 11) return false;
   if(dt.mon > 3 && dt.mon < 11) return true;
   int dom = dt.day, dow = dt.day_of_week;
   if(dt.mon == 3)  return (dom - dow > 7);
   return (dom - dow <= 0);
}
datetime ToNY(datetime t)      { return t + (IsEDT(t) ? -4 : -5) * 3600; }
int NYMinute(datetime t) { MqlDateTime d; TimeToStruct(ToNY(t), d); return d.hour*60 + d.min; }
int NYDay(datetime t)    { MqlDateTime d; TimeToStruct(ToNY(t) + 21600, d); return d.year*372 + d.mon*31 + d.day; }

//+------------------------------------------------------------------+
int OnInit()
{
   atrHandle = iATR(_Symbol, PERIOD_M5, 14);
   trade.SetExpertMagicNumber(Magic);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(10);
   int tm = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(tm != SYMBOL_TRADE_MODE_FULL)
   {
      Print("SF5m: trading disabled/restricted on ", _Symbol);
      return INIT_FAILED;
   }
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void ManageDayState()
{
   datetime today = NYDay(TimeGMT());
   if(today != curDay) { curDay = today; tradesToday = 0; dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY); }
}

int ConsecLossToday()
{
   datetime now = TimeCurrent();
   if(!HistorySelect(now - 4*86400, now)) return 0;
   int cnt = 0;
   for(int k = HistoryDealsTotal() - 1; k >= 0; k--)
   {
      ulong tk = HistoryDealGetTicket(k);
      if(tk == 0) continue;
      if(HistoryDealGetInteger(tk, DEAL_MAGIC) != Magic) continue;
      if(NYDay((datetime)HistoryDealGetInteger(tk, DEAL_TIME)) != curDay) break;
      if(HistoryDealGetInteger(tk, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      double pf = HistoryDealGetDouble(tk, DEAL_PROFIT)
                + HistoryDealGetDouble(tk, DEAL_SWAP)
                + HistoryDealGetDouble(tk, DEAL_COMMISSION);
      if(pf < 0) cnt++;
      else       break;
   }
   return cnt;
}

bool HasOwnPosition()
{
   return PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == Magic;
}

//+------------------------------------------------------------------+
// Force-close own position at end of RTH (intraday system)
//+------------------------------------------------------------------+
void CheckForceExit()
{
   int m = NYMinute(TimeGMT());
   if(m < ForceExitMinET || m >= 960) return;         // only 15:55-16:00 window
   if(!HasOwnPosition()) return;
   Print("SF5m: EOD force-exit");
   trade.PositionClose(_Symbol);
}

bool TradingAllowed()
{
   int m = NYMinute(TimeGMT());
   if(m < SessStartMinET || m >= LastSignalMinET) return false;
   if(tradesToday >= MaxTradesDay) return false;
   if(MaxConsecLosses > 0 && ConsecLossToday() >= MaxConsecLosses) return false;
   if(dayStartEquity - AccountInfoDouble(ACCOUNT_EQUITY) >= MaxDailyLossUSD) return false;
   double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(spread > MaxSpreadPts) return false;
   return true;
}

//+------------------------------------------------------------------+
double CalcLots(double entry, double stop)
{
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double dist    = MathAbs(entry - stop);
   double riskUsd = AccountInfoDouble(ACCOUNT_EQUITY) * RiskPct / 100.0;
   if(tickVal <= 0 || tickSz <= 0 || dist <= 0) return 0;
   double lossPerLot = dist / tickSz * tickVal;
   double lots = MathFloor(riskUsd / lossPerLot / SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP))
                 * SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   return lots < mn ? 0 : MathMin(lots, mx);
}

//+------------------------------------------------------------------+
void OnTick()
{
   ManageDayState();
   CheckForceExit();                       // runs every tick, not per-bar

   // act once per closed M5 bar
   datetime bt = iTime(_Symbol, PERIOD_M5, 0);
   if(bt == lastBarTime) return;
   lastBarTime = bt;
   if(!TradingAllowed()) return;
   if(HasOwnPosition()) return;            // one position at a time
   if(BlockAnyPos && PositionSelect(_Symbol)) return;

   int need = ERWindow + 5;
   MqlRates r[];
   if(CopyRates(_Symbol, PERIOD_M5, 0, need + 2, r) < need + 2) return;
   ArraySetAsSeries(r, true);              // r[0] forming, r[1] just closed = signal bar
   double atr[]; CopyBuffer(atrHandle, 0, 1, 1, atr);
   double atrv = atr[0];

   // streak: r[1]..r[1+StreakK-1] closes monotone; signal bar = r[1]
   int runUp = 0, runDn = 0;
   for(int j = 1; j <= StreakK; j++)
   {
      if(NYDay(r[j].time) != NYDay(r[1].time)) break;      // same day only
      if(r[j].close > r[j+1].close) runUp++; else break;
   }
   for(int j = 1; j <= StreakK; j++)
   {
      if(NYDay(r[j].time) != NYDay(r[1].time)) break;
      if(r[j].close < r[j+1].close) runDn++; else break;
   }
   int dir = runUp >= StreakK ? 1 : (runDn >= StreakK ? -1 : 0);
   if(dir == 0) return;

   // ER20 signed: |c1 - c20| / path, must agree with direction
   double path = 0;
   for(int j = 1; j <= ERWindow; j++) path += MathAbs(r[j].close - r[j+1].close);
   if(path <= 0) return;
   double er = (r[1].close - r[1+ERWindow].close) / path;
   if(MathAbs(er) < ERMin || MathSign(er) != dir) return;

   // entry = current market (open of forming bar), stop = streak extreme
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = dir == 1 ? ask : bid;
   double exLo = r[1].low, exHi = r[1].high;
   for(int j = 1; j <= StreakK; j++)
   {
      exLo = MathMin(exLo, r[j].low);
      exHi = MathMax(exHi, r[j].high);
   }
   double stop = dir == 1 ? exLo - StopBufATR * atrv : exHi + StopBufATR * atrv;
   double risk = MathAbs(entry - stop);
   if(risk < MinStopPts || risk > MaxStopPts) return;
   double tgt  = entry + dir * RRTarget * risk;
   double lots = CalcLots(entry, stop);
   if(lots <= 0) return;

   stop = NormalizeDouble(stop, _Digits);
   tgt  = NormalizeDouble(tgt, _Digits);
   bool ok = dir == 1 ? trade.Buy(lots, _Symbol, 0, stop, tgt, "SF5m long")
                      : trade.Sell(lots, _Symbol, 0, stop, tgt, "SF5m short");
   if(ok)
   {
      tradesToday++;
      PrintFormat("SF5m %s: entry=%.1f stop=%.1f tgt=%.1f lots=%.2f er=%.2f",
                  dir == 1 ? "LONG" : "SHORT", entry, stop, tgt, lots, er);
   }
   else
      PrintFormat("SF5m order FAILED: retcode=%d (%s) err=%d",
                  (int)trade.ResultRetcode(), trade.ResultRetcodeDescription(), GetLastError());
}

int MathSign(double v) { return v > 0 ? 1 : (v < 0 ? -1 : 0); }
//+------------------------------------------------------------------+
