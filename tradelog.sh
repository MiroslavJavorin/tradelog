#!/bin/sh

export POSIXLY_CORREXT=yes
export LC_NUMERIC="en_US.UTF-8" # for localization

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
	res=$((LIST_TICK + PROFIT + POS + LAST_PRICE + HIST_ORD + GRAPH_POS))
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
        EXIT_CODE=FILE_N_EXIST # change an exit code
		return
	fi
}

set_command() {
	# list of existing stock symbols.
	if [ "$LIST_TICK" -eq 1 ]; then
		COMMAND="| awk -F ';' '{ print \$2 }' | sort -u"

	# list total profit from closed positions.
	elif [ "$PROFIT" -eq 1 ]; then
		COMMAND="| awk -F ';' '\
			{ sum += ( \$3 ~ /^buy$/ ) ? -\$4 * \$6 : \$4 * \$6;}\
			END{ printf(\"%.2f\\n\", sum) }'"

	#list of values of currently held positions sorted in descending order by value"
	elif [ "$POS" -eq 1 ]; then

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


	# list the last known price for every known ticker.
	elif [ "$LAST_PRICE" -eq 1 ]; then
		COMMAND="| \
			awk -F ';' \
				'\
					{\
						last_price[\$2] = \$4\
					}\
					END\
					{\
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
	elif [ "$HIST_ORD" -eq 1 ]; then
		COMMAND="|\
			awk -F ';'\
			'\
				{\
					transactions[\$2] += 1;\
					max_len = ( max_len < transactions[\$2] ) ? transactions[\$2] : max_len;\
				}\
				END\
				{\
					trans_per_sym = (( $WIDTH ) ? max_len / $WIDTH : 1 );\
					for ( ticker in transactions )\
					{\
						printf( \"%-10s:\", ticker);\
						sym = \"#\";\
						upper_bound = transactions[ticker] - trans_per_sym;\
						for ( i = 0; i <= upper_bound; i += trans_per_sym )\
						{\
							if ( i == 0 ) printf(\" \" );
							printf(\"%s\", sym);\
						}\
						printf(\"\\n\");\
					}\
				}\
			'\
			| \
			sort -u\
			"
			

    # list of graph of values of held positions according to the ticker.
	elif [ "$GRAPH_POS" -eq 1 ]; then
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
					mon_per_sym = (( $WIDTH ) ? max_num / $WIDTH : 1000 );\
					for ( ticker in amount )\
					{\
						printf( \"%-10s:\", ticker);\
						pta = amount[ticker] * price[ticker];\
						sym = \"#\";\
						if ( pta < 0 )\
						{\
							sym = \"!\";\
							pta *= -1;\
						}\
						upper_bound = pta - mon_per_sym;\
						for ( i = 0; i <= upper_bound; i += mon_per_sym )\
						{\
							if ( i == 0 ) printf(\" \");\
							printf(\"%s\", sym);\
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
HIST_ORD=0                 # list of histogram of the number of transactions according to the ticker.
GRAPH_POS=0                # list of graph of values of held positions according to the ticker.

WIDTH=0                    #

TICKERS=".*"               # ticker sieve.
DT_A=""                    # datetime after
DT_B="9999-99-99 99:99:99" # datetime before

COMMAND=""

EXIT_CODE=""



while [ "$#" -gt 0 ]; do
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
			HIST_ORD=1
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
		;;

		# process logs before entered date
		-b) # -b YYYYMMDD HHMMSS
			shift
			DT_B="$1" # read year, month,  day
			shift
			DT_B="$DT_B $1" # read hour, minute, second
		;;

		# ticker name
		-t)
			shift
			if [ "$TICKERS" = ".*" ]; then
				TICKERS="$1" # add a ticker
				else
				TICKERS="$TICKERS|$1" # add a ticker
			fi
		;;

		-w)
			check_w_flag
			shift
			WIDTH="$1"
			check_w_num    "$WIDTH"
		;;

		# name of input file has been entered
		*.log)
			check_file "$1"
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

check_exit_code # if EXIT_CODE changed, raise an error
done



set_input # create command handling input

TICKERS_SIEVE="\$2 ~ /^$TICKERS$/"
DT_SIEVE="\$1 > \"$DT_A\" && \$1 <\"$DT_B\""

# $FILTERED is input filtered byticker name and data
FILTERED="$INPUT | awk -F ';' '$TICKERS_SIEVE && $DT_SIEVE { print \$0 }'"

# add a command to a variable $COMMAND
set_command



eval "$FILTERED $COMMAND"

