/*      .=====================================.
       /               Spread 5x               \
      |               by Edorenta               |
       \             Spread Scalper            /
        '====================================='
*/

#property copyright "Edorenta"
#property link      "http://algamma.us"
#property version   "1.00"
#property strict

extern double s2s = 5;                       //Spread to Step (1/Cost of Trade)
extern double stp_wid = 1;                   //Sted Widdener
extern double max_step_pct = 0.4;            //Max Step % 
extern double tp_wid = 1;                    //Take Profit Widdener
extern bool   vol_filter_on = true;          //Activate Volatility Filter
extern int    vol_p = 15;                    //Volatility Filter Lookback

enum tgtt   {fixed_m_tgt                     //Fixed Absolute [TT0]
            ,fixed_pct_tgt                   //Fixed Relative [TT1]
            ,dynamic_pct_tgt                 //Dynamic Relative [TT2]
            ,};
extern tgtt   tgt_type = dynamic_pct_tgt;    //Target Type

enum tgtm   {static_tgt                      //Static Target [TM0]
            ,proportional                    //Proportional Target [TM1]
            ,semi_proportional               //Semi-Proportional Target [TM2]
            ,};
extern tgtm   tgt_mgmt = proportional;       //Target Management Mode

extern double b_money = 1.5;                 //Base Money Target [Absolute]
extern double b_money_risk = 0.1;            //Base Money Target [Relative%]

enum mm     {classic                         //Classic [MM0]
            ,mart                            //Martingale [MM1]
            ,scale                           //Scale-in Loss [MM2]
            ,};
extern mm  mm_mode = mart;                   //Money Management Mode
extern int mm_step = 1;                      //MM Trades Step
extern int mm_step_start = 1;                //MM Step Starting Trade
extern int mm_step_end = 50;                 //MM Step Ending Trade

extern double xtor = 1.66;                   //Martingale Target Multiplier [MM1]
extern double increment = 100;               //Scaler Target Increment % [MM2]
extern double max_xtor = 60;                 //Max Multiplier [MM1]
extern double max_increment = 1000;          //Max Increment % [MM2]
extern int    max_longs = 7;                 //Max Long Trades
extern int    max_shorts = 7;                //Max Long Trades

extern int    magic = 42;                    //Magic Number
extern int    slippage = 15;                 //Max Slippage
       double starting_equity = 0;
       
       int OnInit() {

      starting_equity = AccountEquity();
      return (INIT_SUCCEEDED);
  }

  void OnTick() {

      check_cycle_profits();

      if (low_vol() == true) {

          if (trades_info(1) == 0)
              BUY_ECN();
          else spam_long_ECN();

          if (trades_info(2) == 0)
              SELL_ECN();
          else spam_short_ECN();

          spam_long_ECN();
          spam_short_ECN();
      }
  }

  void check_cycle_profits() {

      double tgt = 0, tgt_long = 0, tgt_short = 0;
      int nb_longs = trades_info(1);
      int nb_shorts = trades_info(2);
      double profit_long = data_counter(24);
      double profit_short = data_counter(25);

      switch (tgt_type) {
      case fixed_m_tgt:
          tgt = b_money;
          break;
      case fixed_pct_tgt:
          tgt = (starting_equity * b_money_risk) / 100;
          break;
      case dynamic_pct_tgt:
          tgt = (AccountEquity() * b_money_risk) / 100;
          break;
      }

      switch (tgt_mgmt) {
      case static_tgt:
          tgt_long = tgt;
          tgt_short = tgt;
          break;
      case proportional:
          tgt_long = tgt * nb_longs;
          tgt_short = tgt * nb_shorts;
          break;
      case semi_proportional:
          tgt_long = tgt + ((nb_longs - 1) * tgt) / 2;
          tgt_short = tgt + ((nb_shorts - 1) * tgt) / 2;
          break;
      }

      if (tgt_long < profit_long) {
          close_long();
      }
      if (tgt_short < profit_short) {
          close_short();
      }
      Comment("profit short: ", profit_short, " target: ", tgt_short, "profit long: ", profit_long, " target: ", tgt_long);
  }

  bool low_vol() {

      bool cond = true;

      if (vol_filter_on == true) {
          double atr, sdev;
          atr = iATR(Symbol(), 0, vol_p, 0);
          sdev = iStdDev(Symbol(), 0, vol_p, 0, MODE_EMA, PRICE_CLOSE, 0);
          if (atr < sdev) {
              cond = false;
          }
      }
      return (cond);
  }

  double lotsize_long() {

      int nb_longs = trades_info(1);
      int trade_step = nb_longs;

      if (mm_step > 1) {
          if (nb_longs >= mm_step_start && nb_longs <= mm_step_end) {
              trade_step = MathCeil(nb_longs / mm_step);
          }
      }

      double temp_lots, risk_to_SL, mlots = 0;
      double equity = AccountEquity();
      double margin = AccountFreeMargin();
      double maxlot = MarketInfo(Symbol(), MODE_MAXLOT);
      double minlot = MarketInfo(Symbol(), MODE_MINLOT);
      double pip_value = MarketInfo(Symbol(), MODE_TICKVALUE);
      double pip_size = MarketInfo(Symbol(), MODE_TICKSIZE);
      int leverage = AccountLeverage();
      double TP;

      if (trades_info(1) == 0)
          TP = STEP();

      else
          TP = STEP() * (pow(stp_wid, trades_info(1)));

      risk_to_SL = TP * (pip_value / pip_size);

      if (TP != 0) {
          switch (tgt_type) {
          case fixed_m_tgt:
              temp_lots = NormalizeDouble(b_money / (risk_to_SL), 2);
              break;
          case fixed_pct_tgt:
              temp_lots = NormalizeDouble((b_money_risk * starting_equity) / (risk_to_SL * 1000), 2);
              break;
          case dynamic_pct_tgt:
              temp_lots = NormalizeDouble((b_money_risk * equity) / (risk_to_SL * 1000), 2);
              break;
          }
      }

      if (temp_lots < minlot) temp_lots = minlot;
      if (temp_lots > maxlot) temp_lots = maxlot;

      switch (mm_mode) {
      case mart:
          mlots = NormalizeDouble(temp_lots * (MathPow(xtor, (trade_step))), 2);
          if (mlots > temp_lots * max_xtor) mlots = NormalizeDouble(temp_lots * max_xtor, 2);
          break;
      case scale:
          mlots = temp_lots + ((increment / 100) * trade_step) * temp_lots;
          if (mlots > temp_lots * (1 + (max_increment / 100))) mlots = temp_lots * (1 + (max_increment / 100));
          break;
      case classic:
          mlots = temp_lots;
          break;
      }

      if (mlots < minlot) mlots = minlot;
      if (mlots > maxlot) mlots = maxlot;

      return (mlots);
  }

  double lotsize_short() {

      int nb_shorts = trades_info(2);

      int trade_step = nb_shorts;

      if (mm_step > 1) {
          if (nb_shorts >= mm_step_start && nb_shorts <= mm_step_end) {
              trade_step = MathCeil(nb_shorts / mm_step);
          }
      }

      double temp_lots, risk_to_SL, mlots = 0;
      double equity = AccountEquity();
      double margin = AccountFreeMargin();
      double maxlot = MarketInfo(Symbol(), MODE_MAXLOT);
      double minlot = MarketInfo(Symbol(), MODE_MINLOT);
      double pip_value = MarketInfo(Symbol(), MODE_TICKVALUE);
      double pip_size = MarketInfo(Symbol(), MODE_TICKSIZE);
      int leverage = AccountLeverage();
      double TP = STEP() * (pow(stp_wid, nb_shorts));

      risk_to_SL = TP * (pip_value / pip_size);

      if (TP != 0) {
          switch (tgt_type) {
          case fixed_m_tgt:
              temp_lots = NormalizeDouble(b_money / (risk_to_SL), 2);
              break;
          case fixed_pct_tgt:
              temp_lots = NormalizeDouble((b_money_risk * starting_equity) / (risk_to_SL * 1000), 2);
              break;
          case dynamic_pct_tgt:
              temp_lots = NormalizeDouble((b_money_risk * equity) / (risk_to_SL * 1000), 2);
              break;
          }
      }

      if (temp_lots < minlot) temp_lots = minlot;
      if (temp_lots > maxlot) temp_lots = maxlot;

      switch (mm_mode) {
      case mart:
          mlots = NormalizeDouble(temp_lots * (MathPow(xtor, (trade_step))), 2);
          if (mlots > temp_lots * max_xtor) mlots = NormalizeDouble(temp_lots * max_xtor, 2);
          break;
      case scale:
          mlots = temp_lots + ((increment / 100) * trade_step) * temp_lots;
          if (mlots > temp_lots * (1 + (max_increment / 100))) mlots = temp_lots * (1 + (max_increment / 100));
          break;
      case classic:
          mlots = temp_lots;
          break;
      }

      if (mlots < minlot) mlots = minlot;
      if (mlots > maxlot) mlots = maxlot;

      return (mlots);
  }

  double STEP() {

      double step_pts;
      double freezelvl = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;
      double stoplvl = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
      double step_multiplier;

      step_multiplier = pow(stp_wid, trades_info(3));
      step_pts = NormalizeDouble(s2s * (Ask - Bid) * step_multiplier, Digits);
      //   step_pts = (step_pts*trades_info(3));

      if (freezelvl >= step_pts) step_pts = freezelvl;

      return (step_pts);
  }

  /*    .-----------------------.
        |    ORDER FUNCTIONS    |
        '-----------------------'
  */

  void close_all() {

      for (int i = OrdersTotal() - 1; i >= 0; i--) {
          OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
          if (OrderSymbol() == Symbol() && OrderMagicNumber() == magic) {
              if (OrderType() == OP_BUY) {
                  OrderClose(OrderTicket(), OrderLots(), Bid, slippage, Turquoise);
              }
              if (OrderType() == OP_SELL) {
                  OrderClose(OrderTicket(), OrderLots(), Ask, slippage, Magenta);
              }
          }
      }
  }
  void close_long() {

      for (int i = OrdersTotal() - 1; i >= 0; i--) {
          OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
          if (OrderSymbol() == Symbol() && OrderMagicNumber() == magic) {
              if (OrderType() == OP_BUY) {
                  OrderClose(OrderTicket(), OrderLots(), Bid, slippage, Turquoise);
              }
          }
      }
  }
  void close_short() {

      for (int i = OrdersTotal() - 1; i >= 0; i--) {
          OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
          if (OrderSymbol() == Symbol() && OrderMagicNumber() == magic) {
              if (OrderType() == OP_SELL) {
                  OrderClose(OrderTicket(), OrderLots(), Ask, slippage, Magenta);
              }
          }
      }
  }

  void spam_long_ECN() {
      if (trades_info(1) < max_longs) {
          if (Bid <= (trades_info(4) - STEP())) {
              BUY_ECN();
          }
      }
  }
  void spam_short_ECN() {
      if (trades_info(2) < max_shorts) {
          if (Ask >= (trades_info(7) + STEP())) {
              SELL_ECN();
          }
      }
  }

  void BUY_ECN() {

      double SL = 0;
      double TP = 0;
      int ticket;
      ticket = OrderSend(Symbol(), OP_BUY, lotsize_long(), Ask, slippage, 0, 0, "Keops " + DoubleToStr(lotsize_long(), 2) + " on " + Symbol(), magic, 0, Turquoise);
      if (ticket < 0) {
          Comment("OrderSend Error: ", GetLastError());
      }
      for (int i = 0; i < OrdersTotal(); i++) {
          OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
          if (OrderMagicNumber() == magic && OrderSymbol() == Symbol() && OrderType() == OP_BUY) {
              OrderModify(OrderTicket(), OrderOpenPrice(), SL, TP, 0, Turquoise);
          }
      }
  }
  void SELL_ECN() {

      double SL = 0;
      double TP = 0;
      int ticket;
      ticket = OrderSend(Symbol(), OP_SELL, lotsize_short(), Bid, slippage, 0, 0, "Keops " + DoubleToStr(lotsize_short(), 2) + " on " + Symbol(), magic, 0, Magenta);
      if (ticket < 0) {
          Comment("OrderSend Error: ", GetLastError());
      }
      for (int i = 0; i < OrdersTotal(); i++) {
          OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
          if (OrderMagicNumber() == magic && OrderSymbol() == Symbol() && OrderType() == OP_SELL) {
              OrderModify(OrderTicket(), OrderOpenPrice(), SL, TP, 0, Magenta);
          }
      }
  }

  /*    .-----------------------.
        |     ORDER COUNTER     |
        '-----------------------'
  */

  double trades_info(int key) {

      double nb_longs = 0, nb_shorts = 0, nb_trades = 0, nb = 0;
      double buy_min = 0, buy_max = 0, sell_min = 0, sell_max = 0;

      for (int i = OrdersTotal(); i >= 0; i--) {
          OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
          if (OrderSymbol() == Symbol() && OrderMagicNumber() == magic) {
              if (OrderType() == OP_BUY) {
                  nb_longs++;
                  if (OrderOpenPrice() < buy_min || buy_min == 0) {
                      buy_min = OrderOpenPrice();
                  }
                  if (OrderOpenPrice() > buy_max || buy_min == 0) {
                      buy_max = OrderOpenPrice();
                  }
              }
              if (OrderType() == OP_SELL) {
                  nb_shorts++;
                  if (OrderOpenPrice() > sell_max || sell_max == 0) {
                      sell_max = OrderOpenPrice();
                  }
                  if (OrderOpenPrice() < sell_min || sell_min == 0) {
                      sell_min = OrderOpenPrice();
                  }
              }
          }
      }

      nb_trades = nb_longs + nb_shorts;

      switch (key) {
      case 1:
          nb = nb_longs;
          break;
      case 2:
          nb = nb_shorts;
          break;
      case 3:
          nb = nb_trades;
          break;
      case 4:
          nb = buy_min;
          break;
      case 5:
          nb = buy_max;
          break;
      case 6:
          nb = sell_min;
          break;
      case 7:
          nb = sell_max;
          break;
      }
      return (nb);
  }

  double data_counter(int key) {

      double count_tot = 0, balance = AccountBalance(), equity = AccountEquity();
      double drawdown = 0, runup = 0, lots = 0, profit = 0;

      switch (key) {

      case (1): //All time wins counter
          for (int i = 0; i < OrdersHistoryTotal(); i++) {
              if (!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
              if (OrderMagicNumber() == magic && OrderSymbol() == Symbol() && OrderProfit() > 0) {
                  count_tot++;
              }
          }
          break;

      case (2): //All time loss counter
          for (int i = 0; i < OrdersHistoryTotal(); i++) {
              if (!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
              if (OrderMagicNumber() == magic && OrderSymbol() == Symbol() && OrderProfit() < 0) {
                  count_tot++;
              }
          }
          break;

      case (3): //All time profit
          for (int i = 0; i < OrdersHistoryTotal(); i++) {
              if (!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
              if (OrderMagicNumber() == magic && OrderSymbol() == Symbol()) {
                  profit = profit + OrderProfit() + OrderCommission() + OrderSwap();
              }
              count_tot = profit;
          }
          break;

      case (4): //All time lots
          for (int i = 0; i < OrdersHistoryTotal(); i++) {
              if (!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
              if (OrderMagicNumber() == magic && OrderSymbol() == Symbol()) {
                  lots = lots + OrderLots();
              }
              count_tot = lots;
          }
          break;

      case (5): //Chain Loss
          for (int i = 0; i < OrdersHistoryTotal(); i++) {
              if (!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
              if (OrderMagicNumber() == magic && OrderSymbol() == Symbol() && OrderProfit() < 0) {
                  count_tot++;
              }
              if (OrderMagicNumber() == magic && OrderSymbol() == Symbol() && OrderProfit() > 0) {
                  count_tot = 0;
              }
              //         if (OrderMagicNumber() == magic && OrderSymbol() == Symbol() && OrderProfit()<0 && count_tot>max_risk_trades) count_tot = 0;
          }
          break;

      case (6): //Chain Win
          for (int i = 0; i < OrdersHistoryTotal(); i++) {
              if (!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
              if (OrderMagicNumber() == magic && OrderSymbol() == Symbol() && OrderProfit() > 0) {
                  count_tot++;
              }
              if (OrderMagicNumber() == magic && OrderSymbol() == Symbol() && OrderProfit() < 0) {
                  count_tot = 0;
              }
              //         if (OrderMagicNumber() == magic && OrderSymbol() == Symbol() && OrderProfit()>0 && count_tot>max_risk_trades) count_tot = 0;
          }
          break;

      case (7): //Chart Drawdown % (if equity < balance)
          for (int i = 0; i <= OrdersTotal(); i++) {
              if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
              if (OrderMagicNumber() == magic && OrderSymbol() == Symbol()) {
                  profit = profit + OrderProfit() + OrderCommission() + OrderSwap();
              }
          }
          if (profit > 0) drawdown = 0;
          else drawdown = NormalizeDouble((profit / balance) * 100, 2);
          count_tot = drawdown;
          break;

      case (8): //Acc Drawdown % (if equity < balance)
          if (equity >= balance) drawdown = 0;
          else drawdown = NormalizeDouble(((equity - balance) * 100) / balance, 2);
          count_tot = drawdown;
          break;

      case (9): //Chart dd money (if equity < balance)
          for (int i = 0; i <= OrdersTotal(); i++) {
              if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
              if (OrderMagicNumber() == magic && OrderSymbol() == Symbol()) {
                  profit = profit + OrderProfit() + OrderCommission() + OrderSwap();
              }
          }
          if (profit >= 0) drawdown = 0;
          else drawdown = profit;
          count_tot = drawdown;
          break;

      case (10): //Acc dd money (if equiy < balance)
          if (equity >= balance) drawdown = 0;
          else drawdown = equity - balance;
          count_tot = drawdown;
          break;

      case (11): //Chart Runup %
          for (int i = 0; i <= OrdersTotal(); i++) {
              if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
              if (OrderMagicNumber() == magic && OrderSymbol() == Symbol()) {
                  profit = profit + OrderProfit() + OrderCommission() + OrderSwap();
              }
          }
          if (profit < 0) runup = 0;
          else runup = NormalizeDouble((profit / balance) * 100, 2);
          count_tot = runup;
          break;

      case (12): //Acc Runup %
          if (equity < balance) runup = 0;
          else runup = NormalizeDouble(((equity - balance) * 100) / balance, 2);
          count_tot = runup;
          break;

      case (13): //Chart runup money
          for (int i = 0; i <= OrdersTotal(); i++) {
              if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
              if (OrderMagicNumber() == magic && OrderSymbol() == Symbol()) {
                  profit = profit + OrderProfit() + OrderCommission() + OrderSwap();
              }
          }
          if (profit < 0) runup = 0;
          else runup = profit;
          count_tot = runup;
          break;

      case (14): //Acc runup money
          if (equity < balance) runup = 0;
          else runup = equity - balance;
          count_tot = runup;
          break;

      case (15): //Current profit here
          for (int i = 0; i <= OrdersTotal(); i++) {
              if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
              if (OrderMagicNumber() == magic && OrderSymbol() == Symbol()) {
                  profit = profit + OrderProfit() + OrderCommission() + OrderSwap();
              }
          }
          count_tot = profit;
          break;

      case (16): //Current profit acc
          count_tot = AccountProfit();
          break;

      case (17): //Gross profits
          for (int i = 0; i < OrdersHistoryTotal(); i++) {
              if (!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
              if (OrderMagicNumber() == magic && OrderSymbol() == Symbol() && OrderProfit() > 0) {
                  profit = profit + OrderProfit() + OrderCommission() + OrderSwap();
              }
          }
          count_tot = profit;
          break;

      case (18): //Gross loss
          for (int i = 0; i < OrdersHistoryTotal(); i++) {
              if (!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
              if (OrderMagicNumber() == magic && OrderSymbol() == Symbol() && OrderProfit() < 0) {
                  profit = profit + OrderProfit() + OrderCommission() + OrderSwap();
              }
          }
          count_tot = profit;
          break;

      case (19): //(average buying price longs)
          for (int i = 0; i <= OrdersTotal(); i++) {
              if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
              if (OrderMagicNumber() == magic && OrderSymbol() == Symbol() && OrderType() == OP_BUY) {
                  count_tot = count_tot + OrderLots() * (OrderOpenPrice());
              }
          }
          break;

      case (20): //(average buying price shorts)
          for (int i = 0; i <= OrdersTotal(); i++) {
              if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
              if (OrderMagicNumber() == magic && OrderSymbol() == Symbol() && OrderType() == OP_SELL) {
                  count_tot = count_tot + OrderLots() * (OrderOpenPrice());
              }
          }
          break;

      case (21): //Current lots long
          for (int i = 0; i <= OrdersTotal(); i++) {
              if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
              if (OrderMagicNumber() == magic && OrderSymbol() == Symbol() && OrderType() == OP_BUY) {
                  count_tot = count_tot + OrderLots();
              }
          }
          break;

      case (22): //Current lots short
          for (int i = 0; i <= OrdersTotal(); i++) {
              if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
              if (OrderMagicNumber() == magic && OrderSymbol() == Symbol() && OrderType() == OP_SELL) {
                  count_tot = count_tot + OrderLots();
              }
          }
          break;

      case (23): //Current lots all
          for (int i = 0; i <= OrdersTotal(); i++) {
              if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
              if (OrderMagicNumber() == magic && OrderSymbol() == Symbol()) {
                  count_tot = count_tot + OrderLots();
              }
          }
          break;

      case (24): //Current profit here Long
          for (int i = 0; i <= OrdersTotal(); i++) {
              if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
              if (OrderMagicNumber() == magic && OrderSymbol() == Symbol() && OrderType() == OP_BUY) {
                  profit = profit + OrderProfit() + OrderCommission() + OrderSwap();
              }
          }
          count_tot = profit;
          break;

      case (25): //Current profit here Short
          for (int i = 0; i <= OrdersTotal(); i++) {
              if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
              if (OrderMagicNumber() == magic && OrderSymbol() == Symbol() && OrderType() == OP_SELL) {
                  profit = profit + OrderProfit() + OrderCommission() + OrderSwap();
              }
          }
          count_tot = profit;
          break;
      }
      return (count_tot);
  }