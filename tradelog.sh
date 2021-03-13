#!/bin/sh

export POSIXLY_CORREXT=yes
export LC_NUMERIC="en_US.UTF-8"

###
# sed: sed -i
# awk/gawk


##################################################################
# Každý obchodovaný artikl má jednoznačný identifikátor, tzv. ticker
# INTEL = INTC, BITCOIN = BTC
# cena artiklu se meni v case
# long position, short position 
# prikazy buy a sell urciteho mnozstvi jednotek artiklu
# ...
# -a DATETIME – after: jsou uvažovány pouze záznamy PO tomto datu (bez tohoto data).
# DATETIME je formátu YYYY-MM-DD HH:MM:SS.
# -t TICKER – jsou uvažovány pouze záznamy odpovídající danému tickeru. Při více výskytech přepínače se bere množina všech uvedených tickerů.
########           Popis
# Skript filtruje záznamy z nástroje pro obchodování na burze. Pokud je skriptu zadán také příkaz, nad filtrovanými záznamy daný příkaz provede.
# Pokud skript nedostane ani filtr ani příkaz, opisuje záznamy na standardní výstup.
# Skript umí zpracovat i záznamy komprimované pomocí nástroje gzip (v případě, že název souboru končí .gz).
# V případě, že skript na příkazové řádce nedostane soubory se záznamy (LOG, LOG2 …), očekává záznamy na standardním vstupu.
# Pokud má skript vypsat seznam, každá položka je vypsána na jeden řádek a pouze jednou.
# Není-li uvedeno jinak, je pořadí řádků dáno abecedně dle tickerů. Položky se nesmí opakovat.
# Grafy jsou vykresleny pomocí ASCII a jsou otočené doprava. Každý řádek histogramu udává ticker. Kladná hodnota či četnost jsou vyobrazeny posloupností znaku mřížky #, záporná hodnota (u graph-pos) je vyobrazena posloupností znaku vykřičníku !.

########          Podrobne pozadavky
# 1) Skript analyzuje záznamy (logy) pouze ze zadaných souborů v daném pořadí.
# 2) Formát logu je CSV kde oddělovačem je znak středníku ;. 
# |   Formát je řádkový, každý řádek odpovídá záznamu o jedné transakci ve tvaru
# |           DATUM A CAS        ;TICKER;TYP TRANSAKCE;JEDNOTKOVA CENA;MENA;OBJEM;ID
# |           YYYY-MM-DD HH:MM:SS;NAME  ;buy|sell     ;{0-9}          ;USD ;quant;id   
# | kde
# |	DATUM A CAS jsou ve formátu YYYY-MM-DD HH:MM:SS
# |	TICKER je řetězec neobsahující bílé znaky a znak středníku
# |	TYP TRANSAKCE nabývá hodnoty buy nebo sell 
# |	JEDNOTKOVA CENA je cena s přesností na maximálně dvě desetinná místa; 
# | jako oddělovač jednotek a desetin slouží znak tečky .; Např. 1234567.89
# |	MENA je třípísmenný USD, EUR, CZK, SEK, GBP atd.
# |	OBJEM značí množství jednotek v transakci
# |	ID je identifikátor transakce (řetězec neobsahující bílé znaky a znak středníku)
# |	Hodnota transakce je JEDNOTKOVA CENA * OBJEM. Příklad záznamů:
# |	
# |		2021-07-29 23:43:13;TSM;buy;667.90;USD;306;65fb53f6-7943-11eb-80cb-8c85906a186d
# |		2021-07-29 23:43:15;BTC;sell;50100;USD;5;65467d26-7943-11eb-80cb-8c85906a186d
# |	První záznam značí nákup 306 akcií firmy TSMC (ticker TSM) za cenu 667.90 USD / akcie. Hodnota transakce je tedy 204377.40 USD.
# |	Druhý záznam značí prodej 5 bitcoinů (ticker BTC) za cenu 50 100 USD / bitcoin. Hodnota transakce je tedy 250500.00 USD.
# 3) Předpokládejte, že měna je u všech záznamů stejná (není potřeba ověřovat).
# 4) Skript žádný soubor nemodifikuje. Skript nepoužívá dočasné soubory.
# 5) Můžete předpokládat, že záznamy jsou ve vstupních souborech uvedeny chronologicky a je-li na vstupu více souborů, 
# | jejich pořadí je také chronologické.
# 6) Celkový zisk z uzavřených pozic (příkaz profit) se spočítá jako suma hodnot sell transakcí - suma hodnot buy transakcí.
# 7) Hodnota aktuálně držených pozic (příkazy pos a graph-pos) se pro každý ticker spočítá jako počet držených jednotek * jednotková cena z poslední transakce, kde počet držených jednotek je dán jako suma objemů buy transakcí - suma objemů sell transakcí.

#########          Navratova hodnota
# Skript vrací úspěch v případě úspěšné operace. 
# Interní chyba skriptu nebo chybné argumenty budou doprovázeny chybovým hlášením a neúspěšným návratovým kódem.


print_help()
{
    echo "usage: tradelog [-h|--help]"
    echo "usage: tradelog [FILTER] [COMMAND] [LOG [LOG2 [...]]"
    echo "options:"
    echo "	COMMAND can be one of:"
    echo "		ilst-tick  - list of existing stock symbols \"tickers\"."
    echo "		profit     - list total profit from closed positions."
    echo "		pos        - list of values of currently held positions sorted in descending order by value"
    echo "		last-price - list the last known price for every known ticker."
    echo "		hist-ord   - list of histogram of the number of transactions according to the ticker."
    echo "		graph-pos  - list of graph of values of held positions according to the ticker."
    echo "	FITER can be one of"
    echo "		-a DATETIME - after DATETIME. Only records after this date are considered (without this date)"
    echo "		-b DATETIME - before DATETIME."
    echo "		-t TICKER	- list of entries corresponding to a given ticker. With multiple occurrences of the switch,"
    echo "		-w WIDTH    - sets the width of the graph listing, ie the length of the longest line on WIDTH."
    echo "-h and --help for help mmessage"
}




# test
print_help

