#!/bin/sh

export POSIXLY_CORREXT=yes
export LC_NUMERIC="en_US.UTF-8" # for localization

#==============DEBUG===============
debug_function() {
    if [ "$1" = "\n" ]; then
        echo "==============================$1"
    else
        echo "DEBUG: $1"
    fi
}
# set -x
set -u # error if variable is not defined
#==============DEBUG===============

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

check_w_flag() {
    if [ ! "$WIDTH" = 0 ]; then
        EXIT_CODE=MORE_THAN_ONCE
    fi
}

# in the script there cannot be entered more than one command, so
# this function checks if no more than one caommand have been entered
check_command() {
    res=$((LIST_TICK + PROFIT + POS + LAST_PRICE + HIST_ORG + GRAPH_POS))
    debug_function "in check_command res == $res"
    debug_function "\n"
    if [ "$res" -ne 0 ]; then
        EXIT_CODE=MORE_THAN_ONE_CMD
    fi
}

check_w_num() {
    if [ ! "$1" -ge 0 ]; then
        EXIT_CODE=NON_INTEGER_AFTER_W
    fi
}

set_input() {
    if [ ! "$GZIP_FILES" = "" ]; then
        INPUT="gzip -d -c $GZIP_FILES | cat - $LOG_FILES"
    elif [ ! "$LOG_FILES" == "" ]; then
        INPUT="cat $LOG_FILES" # create stdin input
    else INPUT="cat -"
    fi
}
# check error code end terminate the program if error occurred
check_exit_code() {

    debug_function "in check_exit_code(), EXIT_CODE is now \"$EXIT_CODE\""

    case $EXIT_CODE in
    UNKNOWN_COMMAND)
        echo >&2 "Unknown command: \"$1\"."
        exit 1
        ;;
    MORE_THAN_ONCE)
        echo >&2 "More than 1 command entered: second command(you must not enter it) \"$1\"."
        exit 1
        ;;
    NON_INTEGER_AFTER_W)
        echo >&2 "Number that was entered after \"-w\" is not a positive whole number \"$1\"."
        exit 1
        ;;
    esac
}

# chevk if file exists
check_file() {
    if [ ! -f "$1" ]; then # if file does not exist
        debug_function "File with name \"$1\" doe not exist"
        debug_function "Terminatng"
        debug_function "\n"
        EXIT_CODE=FILE_N_EXIST # change an exit code
        return
    fi
    debug_function "ADD FILENAME $1"
}

set_command() {
    # list of existing stock symbols.
    if [ "$LIST_TICK" -eq 1 ]; then
        debug_function "LIST_TICK is about to run"
        COMMAND="| awk -F ';' '{ print \$2 }' | sort -u"

    # list total profit from closed positions.
    elif [ "$PROFIT" -eq 1 ]; then
        debug_function "PROFIT is about to run"
        COMMAND="| awk -F ';' '\
            {if(\$3 ~ /^buy$/){sum-=\$4 * \$6}else{sum+=\$4 * \$6}}\
            END{printf(\"%.2f\\n\", sum)}'"

    #list of values of currently held positions sorted in descending order by value"
    elif [ "$POS" -eq 1 ]; then

        debug_function "POS is about to run"
        COMMAND="|\
                    awk -F ';' \
                        '\
                            {\
                                price[\$2] = \$4;\
                                ticks[\$2] += ( \$3 ~ /^buy$/ ) ? \$6 : -\$6;\
                            }\
                            END \
                            {\
                                for (tick_name in ticks)\
                                {\
                                    printf( \"%-10s: %11.2f\\n\", tick_name, ticks[tick_name] * price[tick_name])\
                                }\
                            }\
                        '\
                    | \
                    sort -n -t ':' -k2 -r\
                 "


    # list the last known price for every known ticker."
    elif [ "$LAST_PRICE" -eq 1 ]; then
        debug_function "LAST_PRICE is about to run"
        COMMAND="| \
                awk -F ';' \
                    '\
                        {\
                            last_price[\$2] = \$4
                        }\
                        END {\
                            for (tick_name in last_price)\
                            {\
                                printf( \"%-10s: %8.2f\\n\", tick_name, last_price[tick_name])\
                            }\
                        }\
                    '\
                | \
                sort -u\
             "

    # list of histogram of the number of transactions according to the ticker."
    elif [ "$HIST_ORG" -eq 1 ]; then
        debug_function "HIST_ORG is about to run"
                COMMAND="|\
                awk -F ';' \
                    '\
                        {\
                            transactions[\$2] += 1;\
                            if (max_len < transactions[\$2] ) { max_len = transactions[\$2] }\
                        }\
                        END\
                        {\
                            for ( tick_name in transactions )\
                            {\
                                printf( \"%-10s: \", tick_name);\
                                sym=\"#\";\
                                step = max_len/(($WIDTH == 0) ? 1 : $WIDTH);\
                                for ( num = step; num <= transactions[tick_name]; num += step )\
                                {\
                                    printf(\"%s\", sym)\
                                };\
                                printf(\"\\n\")\
                            }\
                        }\
                    '\
                |\
                sort -u\
             "

    # list of graph of values of held positions according to the ticker.
    elif [ "$GRAPH_POS" -eq 1 ]; then
        debug_function "GRAPH_POS is about to run"
        COMMAND="|\
                awk -F ';'\
                    '\
                        {\
                            amount[\$2] += (\$3 ~ /^buy$/) ? \$6 : -\$6;\
                            price[\$2]   = \$4;\
                        }\
                        END\
                        {\
                            for ( ticker in amount )\
                            {\
                                pta = price[ticker] * amount[ticker];\
                                pta *= ( pta < 0 ) ? -1 : 1;\
                                max_num = (max_num < pta) ? pta : max_num;\
                            }\
                            mon_per_sym = max_num / (( $WIDTH ) ? $WIDTH : 1 );\
                            for ( ticker in amount )\
                            {\
                                printf( \"%-10s: \", ticker);\
                                pta = amount[ticker] * price[ticker];\
                                sym = \"#\";\
                                if ( pta < 0 )\
                                {\
                                    sym = \"!\";\
                                    pta *= -1;\
                                }\
                                i = mon_per_sym;\
                                while ( pta > i )\
                                {\
                                    printf(\"%s\", sym);\
                                    i += mon_per_sym;\
                                }\
                                printf(\"\\n\");\
                            }\
                        }\
                    '\
                | \
                sort -u\
                "
    fi
}

LOG_FILES=""
GZIP_FILES=""

LIST_TICK=0                # list of existing stock symbols \"tickers\".
PROFIT=0                   # list total profit from closed positions.
POS=0                      # list of values of currently held positions sorted in descending order by value
LAST_PRICE=0               # list the last known price for every known ticker.
HIST_ORG=0                 # list of histogram of the number of transactions according to the ticker.
GRAPH_POS=0                # list of graph of values of held positions according to the ticker.

WIDTH=0                    #

TICKERS=".*"               # ticker sieve.
DT_A=""                    # datetime after
DT_B="9999-99-99 99:99:99" # datetime before

COMMAND=""

EXIT_CODE=""


debug_function "NUMBER OF ARGS: $#"
debug_function "\n"

while [ "$#" -gt 0 ]; do
    debug_function "$1"
    #=================FILTER====================
    case $1 in
    -h | --help)
        shift
        # if -h and some other argument entered
        if [ "$#" -ne 0 ]; then
            EXIT_CODE=UNKNOWN_COMMAND
            check_exit_code "$1"
        fi
        print_help
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

    #list of values of currently held positions sorted in descending order by value"
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

        #=================FILTER====================

        #=================COMMAND====================
    # process logs after entered date
    -a)
        shift
        DT_A="$1" # read year, month,  day
        shift
        DT_A="$DT_A $1" # read hour, minute, second
        debug_function "$DT_A"
        debug_function "Added date \"after\""
        ;;

        # process logs before entered date
    -b) # -b YYYYMMDD HHMMSS
        shift
        DT_B="$1" # read year, month,  day
        shift
        DT_B="$DT_B $1" # read hour, minute, second
        debug_function "$DT_B"
        debug_function "Added date \"before\""
        ;;

    # ticker name
    -t)
        shift
        if [ "$TICKERS" = ".*" ]; then
            TICKERS="$1" # add a ticker
        else
            TICKERS="$TICKERS|$1" # add a ticker
        fi
        debug_function "TICKERS: $TICKERS added"
        ;;

        # u výpisu grafů nastavuje jejich šířku, tedy délku nejdelšího řádku na WIDTH.
        # Tedy, WIDTH musí být kladné celé číslo. Více výskytů přepínače je chybné spuštění.
    -w)
        check_w_flag
        shift
        WIDTH="$1"
        check_w_num    "$WIDTH"
        debug_function "WIDTH: $1"
        ;;

    # name of input file has been entered
    *.log)
        check_file "$1"
        debug_function "$1"
        LOG_FILES="$LOG_FILES $1"
        ;;

    # name of an archived file has been entered
    *.gz)
        check_file     "$1"
        GZIP_FILES="$GZIP_FILES $1"
        ;;

    # TICKERS
    *)
        TICKERS="$TICKERS|$1"
        ;;
    esac
    #=================COMMAND====================
    shift
    debug_function "\n"

    check_exit_code # if EXIT_CODE changed, raise an error
done

# check_data_input # if script got no filenames, use stdin as input source
# ^^^^^^^^^^^^^^^^DELETEME dont need to redirect input to stdin

debug_function "GZIP_FILES: $GZIP_FILES"
debug_function "\n"

# add gzip files
set_input # create command handling input

TICKERS_SIEVE="\$2 ~ /^$TICKERS$/"
DT_SIEVE="\$1 > \"$DT_A\" && \$1 <\"$DT_B\""

FILTERED="$INPUT | awk -F ';' '$TICKERS_SIEVE && $DT_SIEVE { print \$0 }'"

set_command

eval "$FILTERED $COMMAND"

