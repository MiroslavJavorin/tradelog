#!/bin/sh

set -x
export POSIXLY_CORREXT=yes
export LC_NUMERIC="en_US.UTF-8"

debug_function() {
    if [ "$1" = "\n" ]; then
        echo "==============================$1"
        return
    fi
    echo "DEBUG: $1"
}

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

print_help() {
    echo "usage: tradelog [-h|--help]"
    echo "usage: tradelog [FILTER] [COMMAND] [LOG [LOG2 [...]]"
    echo "options:"
    echo "	COMMAND can be one of:"
    echo "		list-tick  - list of existing stock symbols \"tickers\"."
    echo "		profit     - list total profit from closed positions."
    echo "		pos        - list of values of currently held positions sorted in descending order by value"
    echo "		last-price - list the last known price for every known ticker."
    echo "		hist-ord   - list of histogram of the number of transactions according to the ticker."
    echo "		graph-pos  - list of graph of values of held positions according to the ticker."
    echo "	FITER can be one of"
    echo "		-a DATETIME - after DATETIME. Only records after this date are considered (without this date)"
    echo "		-b DATETIME - before DATETIME."
    echo "		-t TICKER   - list of entries corresponding to a given ticker. With multiple occurrences of the switch,"
    echo "		-w WIDTH    - sets the width of the graph listing, ie the length of the longest line on WIDTH."
    echo "-h and --help for help message"
}

check_command() {
    res=$("$LIST_TICK" + "$PROFIT" + "$POS" + "$LAST_PRICE" + "$HIST_ORG" + "$GRAPH_POS")
    debug_function "in check_command res == $res"
    debug_function "\n"
    if [ "$res" -ne 0 ];then
        EXIT_CODE=MORE_THAN_ONE_CMD
    fi
}

# check error code end terminate the program if error occured
check_exit_code() {

    debug_function "in check_exit_code(), EXIT_CODE is now \"$EXIT_CODE\""

    case $EXIT_CODE in
    UNKNOWN_COMMAND)
        echo >&2 "Unknown command: \"$1\"."
        exit 1
        ;;
    MORE_THAN_ONE_CMD)
        echo >&2 "More than 1 command entered: second command(you must not enter it) \"$1\"."
        exit 1
        ;;
    esac
}

# if source with data is empty, redirect input from stdin
check_data_input() {
    debug_function "in check_data_source"
    if [ "$DATA_FILES" = "" ]; then
        DATA_FILES="-"
        debug_function "in check_data_source, \$DATA_FILES == \"-\""
        debug_function "$DATA_FILES"
    fi
}

#====================================================#
#=====================MAIN_CYCLE=====================#
#====================================================#
# walk through all argument using while cycle
# add each valid to a COMMAND variable, then call function that will parse COMMAND
# In case of invalid argument change EXIT_CODE to an appropriate exit code.
#  By default variable has value NO_ARGS, because at the beginning no arguments are checked
# CURR_COMMAND="" # is it neccesary ?

POS_COMAND="" # list of values of currently held positions sorted in descending order by value.
TICKERS=".*"  # ticker sieve: tickers sefaratnd by | that were entered in commandline
DATA_FILES="" # input data. By default is from stdin

LINE_FROM=""
LINE_TO=""

LIST_TICK=0  # list of existing stock symbols \"tickers\".
PROFIT=0     # list total profit from closed positions.
POS=0        # list of values of currently held positions sorted in descending order by value
LAST_PRICE=0 # list the last known price for every known ticker.
HIST_ORD=0   # list of histogram of the number of transactions according to the ticker.
GRAPH_POS=0  # list of graph of values of held positions according to the ticker.


DT_A=""
DT_B="9999-99-99 99:99:99"

EXIT_CODE=""

while [ "$#" -gt 0 ]; do
    # CURR_COMMAND=$1 # is it neccesary ?
    debug_function "$1"
    case $1 in
    -h | --help)
        shift
        # if -h and some other argument entered
        if [ "$#" -ne 0 ]; then
            EXIT_CODE=UNKNOWN_COMMAND
            check_exit_code "$1"
        fi
        print_help
        break
        ;;

    # list of values of currently held positions sorted in descending order by value.
    pos)
        POS_COMAND="$POS_COMMAND | sort "
        ;;
    # list of existing stock symbols.
    list-tick)
        check_command # if one of th commands was entered before, return an error
        LIST_TICK=1
    ;;
    # list of values of currently held positions sorted in descending order by value"
    profit)
        check_command # -//-
        PROFIT=1
    ;;
    pos)
        check_command # -//-
        POS=1
    ;;
    # list the last known price for every known ticker."
    last-price)
        check_command # -//-
        LAST_PRICE=1
    ;;
    # list of histogram of the number of transactions according to the ticker."
    hist-ord)
        check_command # -//-
        HIST_ORG=1
    ;;
    # list of graph of values of held positions according to the ticker."
    graph-pos)
        check_command # -//-
        GRAPH_POS=1
    ;;
    -a) # -a YYYYMMDD HHMMSS
        shift
        DT_A="$1" # read year, month,  day
        shift
        DT_A="$DT_A $1" # read hour, minute, second
        debug_function "$DT_A"
        debug_function "Added date \"after\""
        ;;
    -b) # -b YYYYMMDD HHMMSS
        shift
        DT_B="$1" # read year, month,  day
        shift
        DT_B="$DT_B $1" # read hour, minute, second
        debug_function "$DT_B"
        debug_function "Added date \"before\""
        ;;
    -t)
        shift
        if [ "$TICKERS" = ".*" ]; then
            debug_function "1st ticker"
            TICKERS="$1" # add a ticker
        else
            TICKERS="$TICKERS|$1" # add a ticker
        fi
        debug_function "$TICKERS added"
        ;;
    -w) ;;

    *.log)
        debug_function "ADD FILENAME $1"
        DATA_FILES="$DATA_FILES $1"
        ;;
    *.gz)
        debug_function "ADD GZIP $1"
        GZIP_FILES="$GZIP_FILES $1"
        ;;
    *)
        debug_function "ADD TICKER $1"
        TICKERS="$TICKERS|$1"
        ;;
    esac
    shift
    debug_function "\n"
done
check_data_input # if script got no filenames, use stdin as input source
check_exit_code  # if EXIT_CODE changed, raise an error


INPUT="cat $DATA_FILES"
TICK_SIEVE_EXPR="\$2 ~ /^$TICKERS$/" # match lines with ticker from list of entered tickers

DT_SIEVE_EXPR="\$1 > \"$DT_A\" && \$1 <\"$DT_B\""

debug_function "$DT_SIEVE_EXPR"
debug_function "\n"

AFTER_FLAGS="eval "$INPUT | awk -F ';' '$TICK_SIEVE_EXPR && $DT_SIEVE_EXPR { print \$0}'""

if   [ "$LIST_TICK "   -eq 1 ];   then
    debug_function "LIST_TICK is about to run"
    # TODO implemet functions
elif [ "$PROFIT"     -eq 1 ];     then
    debug_function "PROFIT is about to run"
    # TODO implemet functions
elif [ "$POS"        -eq 1 ];        then
    debug_function "POS is about to run"
elif [ "$LAST_PRICE" -eq 1 ]; then
    debug_function "LAST_PRICE is about to run"
    # TODO implemet functions
elif [ "$HIST_ORG"   -eq 1 ];   then
    debug_function "HIST_ORG is about to run"
    # TODO implemet functions
elif [ "$GRAPH_POS"  -eq 1 ];  then
    debug_function "GRAPH_POS is about to run"
    # TODO implemet functions
fi











####======================SCRATCHES, DONT USE======================####
#GET_ALL_TICKERS="grep '^.*;\($TICKERS\)'" # get all tickers from the file

#AWK_COMMAND="awk 'comand' $DATA_FILES"

#READ_FILTERED="eval $READ_INPUT | awk -F ';' 'smth' "
####======================SCRATCHES, DONT USE======================####

# AWK
# $0 - every lines
# $1 - first column
# /regexp/
# awk '/regexp/ {printf $1}' - print all lines ;;with regexp matching
# awk '/regexp/ {printf $1,$2}' - print whole lines matchineg regexp
# awk '/regexp/ && $2>number {printf $1,$2}' - $2 > number !! for data
# awk -f FILENAME work filename
# awk '$1 == "TICKER" || $2 == "TICKER2" printf("privet" )'
# awk 'BEGIN { print( "bigin" )} {printf(" main body" )} END{ printf( "end" ) }'
# авк '{number_of_tickers = }'

# awk '  /$$DATETIME_COL > "$DATETIME_TO_YYYYMMDD $DATETIME_TO_HHMM" &&  {printf(" %6.2f\n", /$1)} $FILE'

# потом будет что-то типа
#   ;eval " DATETIME_FILTR | NUMBERS_FILTER | ... "



# TODO
# TODO
# TODO
# TODO
# TODO
# TODO
# TODO
