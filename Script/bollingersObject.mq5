//+------------------------------------------------------------------+
//|                                             bollingersObject.mq5 |
//|                                  Copyright 2021, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2021, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "----------------------------------------------------------"
input group "Horário de negociação"
input int hrStart = 9; //Hora de início, HH 
input int minStart = 10; //Minuto de início, MM (entre 0 e 60)
input int hrFinish = 17; //Hora do fim, HH 
input int minFinish = 30; //Minuto do fim, MM (entre 0 e 60)
input group "----------------------------------------------------------"
input int Volume = 1; //Volume de Negociação
input ulong MagicNumber = 123456; // Magic Number
input double LDN = -100; //loss diario (Número negativo)
//+------------------------------------------------------------------+
//| Variáveis Globais                                                |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh> //biblioteca Ctrade
#include <Trade/PositionInfo.mqh> // position info
MqlDateTime atualTime; //reconhece o horario atual
MqlTick tick;
CTrade trade; 
CPositionInfo _PosicaoInfo;
// Variável para o Indicador
int BollingerBands = INVALID_HANDLE; //cria as bandas
double MiddleBandArray[];
double UpperBandArray[];
double LowerBandArray[];

// variáveis para controle de posições
bool comprado = false;
bool vendido  = false;
ulong ticketComprado = 0;
ulong ticketVendido = 0;

//variaveis do stop loss
double   tmp_profit = 0;
double   maximo_do_dia = 0;

int OnInit()
  {
//---  
   if( !CheckInputErrors() )
     {
      return(INIT_PARAMETERS_INCORRECT);
     }
//---      
   if( !InitializeIndicators() )
     {
      return(INIT_FAILED);
     }
//---      
   trade.SetExpertMagicNumber(MagicNumber);
//--- create timer
   EventSetTimer(120);
//---   
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- destroy timer
   EventKillTimer();
   for(int i=PositionsTotal();i<1;i--)
     {
      if(PositionsTotal() > 0)
      {
        trade.PositionClose(_PosicaoInfo.Ticket());
      } 
     }  
   DeleteAllIndicators();   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(isNewBar())
     {
     if(timeToStart())
       {
        if(GetData())
          {
           if(CheckPositionsAndOrders())
             {
              if( !takeprofit())
                {
                 Print("Lógica operacional não realizada com sucesso!");
                 ExpertRemove();
                }
              if( !TradeLogic())
                {
                 Print("Lógica operacional não realizada com sucesso!");
                 ExpertRemove();
                }
              if( Loss_Diario())
                {  
                 ExpertRemove();
                }  
             }
          }
       }
     }
  }
//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
//---
   if(timeToStop())
     {
      ExpertRemove();
     }
  }
//+------------------------------------------------------------------+

bool isNewBar() //função para reconhecer candle
   {
//memoriza o tempo de abertura da ultima barra em uma variável estatica
   static datetime last_time=0;
//tempo atual
   datetime lastbar_time=(datetime)SeriesInfoInteger(Symbol(),Period(),SERIES_LASTBAR_DATE);
//o if da primeira chamada
   if(last_time==0)
      {
//configura o tempo e sai
      last_time=lastbar_time;
      return(false);
      }
//se o tempo for diferente
   if(last_time!=lastbar_time)
     {
//recebe o tempo e retorna verdadeiro
      last_time=lastbar_time;
      return(true);
     }
//se passar pela função e a barra não for nova, retorna falso.
     return(false);
   }

//+------------------------------------------------------------------+

bool timeToStart() //Hora de inicio
   {
   TimeToStruct(TimeCurrent(),atualTime);
   if(atualTime.hour>=hrStart && atualTime.min>=minStart)
     {
      return true;
     } 
     else
       {
        return false;
       }
   }
//+------------------------------------------------------------------+   
bool timeToStop() //hora de fim
   {
   TimeToStruct(TimeCurrent(),atualTime);
   if(atualTime.hour>=hrFinish && atualTime.min>=minFinish)
     {
      return true;
     } 
     else
       {
        return false;
       }
   }
//+------------------------------------------------------------------+     
double normalizePrice(double price) //normaliza o preço em relação ao tick do ativo
{
   double range_tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE); //obtem o tamanho de cada tick
   if(range_tick==0.0)
   {
      return(NormalizeDouble(price,_Digits)); //retorna preço normalizado
   }
      return(NormalizeDouble(MathRound(price/range_tick)*range_tick,_Digits));
}
//+------------------------------------------------------------------+ 
bool CheckInputErrors()
  {
   double minLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   
   // caso lote seja menor que o lote mínimo
   if(Volume<minLot)
     {
      Print("ERRO -> Lote escolhido pelo usuário é inferior ao lote mínimo");
      return(false);
     }
   
   // lote maior que o lote máxima
   if(Volume>maxLot)
     {
      Print("ERRO -> Lote escolhido pelo usuário é maior que o lote máximo");
      return(false);
     }
   
   // todas as verificações foram feitas com sucesso! -> não tem erro de input
   return(true);
  }
//+------------------------------------------------------------------+   
bool InitializeIndicators()
{
// Coloca Indicador no script
   ArraySetAsSeries(MiddleBandArray,true);
   ArraySetAsSeries(UpperBandArray,true);
   ArraySetAsSeries(LowerBandArray,true);  
   BollingerBands = iBands(_Symbol,_Period,20,0,2,PRICE_CLOSE); //cria bandas de bollinger
//
  if(BollingerBands==INVALID_HANDLE)
     {
      Print("ERRO -> Falha na inicialização dos indicadores");
      return(false);
     }
   
   // colocar os indicadores no gráfico
   if( !ChartIndicatorAdd(0,0,BollingerBands) )
     {
      Print("ERRO -> Erro ao colocar indicador ma1 no gráfico");
      return(false);
     }
  
   return(true);
}
//+------------------------------------------------------------------+ 
bool GetData()
{
   int barsToCopy = 5;
   int copied1 = CopyBuffer(BollingerBands,0,0,barsToCopy,MiddleBandArray);
   int copied2 = CopyBuffer(BollingerBands,1,0,barsToCopy,UpperBandArray);
   int copied3 = CopyBuffer(BollingerBands,2,0,barsToCopy,LowerBandArray);
   //
   if(copied1!=barsToCopy || copied2!=barsToCopy || copied3!=barsToCopy)
     {
      Print("ERRO -> Dados de indicadores não foram copiados corretamente");
      return(false);
     }
   
   //
   if( !SymbolInfoTick(_Symbol,tick) )
     {
      Print("ERRO -> Dados de ticks não foram copiados corretamente");
      return(false);
     }
   return(true);
}
//+------------------------------------------------------------------+ 
bool CheckPositionsAndOrders()
  {
   // variáveis para controle de posições
   comprado = false;
   vendido  = false;
   ticketComprado = 0;
   ticketVendido = 0;
   //+------------------------------------------------------------------+
   //| LOOP NAS POSIÇÕES                                                |
   //+------------------------------------------------------------------+
   // caso não tenha posição -> compra a mercado
   int positionsTotal = PositionsTotal();
   for(int i=0;i<positionsTotal;i++)
     {
      ulong posTicket = PositionGetTicket(i);
      //
      if(PositionSelectByTicket(posTicket))
        {
         ulong posMagic = PositionGetInteger(POSITION_MAGIC);
         string posSymbol = PositionGetString(POSITION_SYMBOL);
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         
         // já tenho posição com meu magic number
         if(posSymbol==_Symbol && posMagic==MagicNumber)
           {
            if(posType==POSITION_TYPE_BUY)
              {
               comprado = true;
               ticketComprado = posTicket;
              }
            //
            if(posType==POSITION_TYPE_SELL)
              {
               vendido  = true;
               ticketVendido = posTicket;
              }
           }
        }
      else
        {
         Print("ERRO -> Posição não selecionada com sucesso");
         return(false);
        }
     }
      // returna verdadeiro depois de atualizadas as variáveis de controle
      return(true);
}
//+------------------------------------------------------------------+
bool TradeLogic()
  {
   bool sinalCompra = false;
   bool sinalVenda = false;
   
   if(iClose(_Symbol,_Period,0) > UpperBandArray[1])
     {
      sinalVenda = true;
     }
   if(iClose(_Symbol,_Period,0) < LowerBandArray[1])
     {
      sinalCompra = true;
     }  
   //--------------------------------------------------------------------
   if(!comprado && !vendido)
     {
      if(sinalCompra)
        {
         double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         bool ok = trade.Buy(Volume,_Symbol,ask,normalizePrice(iClose(_Symbol,_Period,1)-(MiddleBandArray[1]-iClose(_Symbol,_Period,1))),0,"comprei");
         if(ok)
           {
            if( trade.ResultRetcode()==10008 || trade.ResultRetcode()==10009 )
              {
               Print("Posição COMPRADA aberta com sucesso");
              }
            else
              {
               Print("ERRO - > Retorno inesperado do servidor");
               return(false);
              }
           }
         else
           {
            Print("ERRO - > Erro ao enviar trade.Buy");
            return(false);
           }
        }
      if(sinalVenda)
        {
         double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
         bool ok = trade.Sell(Volume,_Symbol,bid,normalizePrice((iClose(_Symbol,_Period,1)-MiddleBandArray[1])+iClose(_Symbol,_Period,1)),0,"vendi");
         if(ok)
           {
            if( trade.ResultRetcode()==10008 || trade.ResultRetcode()==10009 )
              {
               Print("Posição VENDIDA aberta com sucesso");
              }
            else
              {
               Print("ERRO - > Retorno inesperado do servidor");
               return(false);
              }
           }
         else
           {
            Print("ERRO - > Erro ao enviar trade.Buy");
            return(false);
           }
        }
     }    
  
   return(true);
  }
//--------------------------------------------------------------------
bool takeprofit()
  {
   ulong order;
   if(comprado || vendido)
     {
      order = trade.RequestOrder(); //ver como recuperar o ticket da ordem
      bool modify = trade.PositionModify(_Symbol,normalizePrice(trade.RequestSL()),normalizePrice(MiddleBandArray[0]));  //arrumar o jeito de recuperar o ticket da ordem 
     } 
   return(true);
  }
//--------------------------------------------------------------------    
bool  Loss_Diario()
  {
   if(LDN == 0)
      return(false);
   string         tmp_x;
   double         tmp_resultado_financeiro_dia;
   int            tmp_contador;
   MqlDateTime    tmp_data_b;
   TimeCurrent(tmp_data_b);
   tmp_resultado_financeiro_dia = 0;
   tmp_x = string(tmp_data_b.year) + "." + string(tmp_data_b.mon) + "." + string(tmp_data_b.day) + " 00:00:01";
   HistorySelect(StringToTime(tmp_x), TimeCurrent());
   int      tmp_total = HistoryDealsTotal();
   ulong    tmp_ticket = 0;
   string   tmp_symboll;
//--- para todos os negócios
   for(tmp_contador = 0; tmp_contador < tmp_total; tmp_contador++)
     {
      //--- tentar obter ticket negócios
      if((tmp_ticket = HistoryDealGetTicket(tmp_contador)) > 0)
        {
         if(tmp_profit+tmp_resultado_financeiro_dia > maximo_do_dia)
           {
            maximo_do_dia = tmp_resultado_financeiro_dia + tmp_profit;
           } 
         //--- obter as propriedades negócios
         tmp_symboll = HistoryDealGetString(tmp_ticket, DEAL_SYMBOL);
         tmp_profit = HistoryDealGetDouble(tmp_ticket, DEAL_PROFIT);
         if(tmp_symboll == Symbol())
            tmp_resultado_financeiro_dia = tmp_resultado_financeiro_dia + tmp_profit;  
        }
     }
   if(tmp_resultado_financeiro_dia - maximo_do_dia <= LDN)
     {
      Alert("Perda diária de R$"+DoubleToString(LDN, 2)+" foi atingida. Robô stopado!");
      Print("Perda diária de R$"+DoubleToString(LDN, 2)+" foi atingida. Robô stopado!");
      Print("");
      return(true);
     }
   return(false);

  }
//--------------------------------------------------------------------    
bool DeleteAllIndicators()
  {
   int subWindows = (int)ChartGetInteger(0,CHART_WINDOWS_TOTAL);
   for(int i=subWindows-1;i>=0;i--)
     {
      int inds = ChartIndicatorsTotal(0,i);
      if(inds>=1)
        {
         for(int j=inds;j>=0;j--)
           {
            string indName = ChartIndicatorName(0,i,j);
            ChartIndicatorDelete(0,i,indName);
           }
        }
     }
   return(true);
  }
