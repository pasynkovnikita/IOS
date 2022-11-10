#!/bin/bash

export POSIXLY_CORRECT=yes
export LC_NUMERIC=en_US.UTF-8

function main() {
    NUM_REGEX="^[0-9]+$"
    DATE_REGEX="^[0-9]{4}-[0-9]{2}-[0-9]{2}+$"
    FILE_TOP="id,datum,vek,pohlavi,kraj_nuts_kod,okres_lau_kod,nakaza_v_zahranici,nakaza_zeme_csu_kod,reportovano_khs"
    FILE_REGEX="^.*\.csv+$"
    GZ_FILE_REGEX="^.*\.gz+$"
    BZ2_FILE_REGEX="^.*\.bz2+$"

    get_input $@
    filter_input
    procces_commands
}

function print_help() {
	echo "Usage: corona [-h]"
	echo "       corona [FILTERS] [COMMAND] [LOG [LOG2 [...]]"
	echo "Analyzes, filters and displays statistics of confirmed COVID-19 cases in Czech republic"
	echo "FILTERS - can accept any number of following arguments"
	echo " -a DATETIME ... shows records AFTER given date <DATETIME, ...), format YYYY-MM-DD"
	echo " -b DATETIME ... shows records BEFORE given date (..., DATETIME>, format YYYY-MM-DD"
	echo " -g GENDER ... shows records of chosen GENDER M-males, Z-females"
	echo " -s [WIDTH] ... optional parameter, width of histograms, must be GREATER THAN ZERO"
	echo "                works with commands: gender,age,daily,monthly,yearly,countries,districts,regions"
	echo "    -d DISTRICT_FILE ... when combined with command districts replaces LAU-1 code with district name"
	echo "    -r REGIONS_FILE ... when combined with command regions replaces NUTS-3 code with region name"
	echo "COMMANDS - can accept only one of the following commands"
	echo " infected ... displays number of infected people"
	echo " merge ... merges multiple files into one, preserves defauly order"
	echo " gender ... displays the number of infected people for both genders"
	echo " age ... displays statistics on the number of infected people by age"
	echo " daily ... displays statistics of infected people for each day"
	echo " monthly ... displays statistics of infected people for individual months"
	echo " yearly ... displays statistics of infected people for individual years"
	echo " countries ... displays statistics of infected people for each country excluding Czech republic (code CZ)"
	echo " districts ... displays statistics of infected people for individual districts"
	echo " regions ... displays statistics of infected people for individual regions"
	echo "-h ... displays help"
}

function validate_date() {
    is_valid="false"
    if [[ $1 =~ $DATE_REGEX ]] && date -d "$1" >/dev/null 2>&1; then
        is_valid="true"
    else 
        echo "Invalid date format" 1>&2
        exit 1
    fi
}

function validate_gender() {
    is_valid="false"
    if [[ $1 == 'M' || $1 == 'Z' ]]; then
        is_valid="true"
    else 
        echo "Invalid gender" 1>&2
        exit 1
    fi
}

function get_input() {
    local OPTIND opt i
    while getopts ':a:b:g:s:h' opt; do
        case $opt in
            a)
                validate_date "$OPTARG"
                if [[ $is_valid == "true" ]]; then
                    A_DATETIME="$OPTARG"
                else
                    exit 1
                fi;;
            b)
                validate_date "$OPTARG"
                if [[ $is_valid == "true" ]]; then
                    B_DATETIME="$OPTARG"
                else
                    exit 1
                fi;;
            g)
                validate_gender "$OPTARG"
                if [[ $is_valid == "true" ]]; then
                    GENDER="$OPTARG"
                else
                    exit 1
                fi;;
            s) 
                eval next_arg=\${$((OPTIND-1))}
				if [[ $next_arg =~ $NUM_REGEX ]]; then
					WIDTH="$OPTARG"
				else
                	WIDTH="default_width"
                    OPTIND=$((OPTIND-1))
				fi
                DRAW_HISTOGRAM=1;;
            h) print_help
                exit 0;;
            *) 
                echo "Invalid argument" 1>&2
                exit 1
        esac
    done
    shift $((OPTIND - 1))
    proccess_args "$@"
}

function proccess_args() {
    while (( "$#" )); do 
        if [[ $1 =~ $FILE_REGEX || $1 =~ $GZ_FILE_REGEX || $1 =~ $BZ2_FILE_REGEX ]]; then
            if [[ $FILES_NUM -eq 0 ]]; then
                if [[ $1 =~ $FILE_REGEX ]]; then
                    FILES="$(cat "$1")"
                elif [[ $1 =~ $GZ_FILE_REGEX ]]; then
                    FILES="$(zcat "$1")"
                elif [[ $1 =~ $BZ2_FILE_REGEX ]]; then
                    FILES="$(bzcat "$1")"
                fi
            else
                if [[ $1 =~ $FILE_REGEX ]]; then
                    READ_INPUT="$(cat "$1" | sed 1d)"
                elif [[ $1 =~ $GZ_FILE_REGEX ]]; then
                    READ_INPUT="$(zcat "$1" | sed 1d)"
                elif [[ $1 =~ $BZ2_FILE_REGEX ]]; then
                    READ_INPUT="$(bzcat "$1" | sed 1d)"
                fi
                FILES="$FILES
$READ_INPUT"
            fi
            FILES_NUM=$((FILES_NUM+1))
        else
            if [[ -z $COMMAND ]]; then
                case $1 in
                    infected | merge | gender | age | daily | monthly | yearly | countries | districts | regions) COMMAND=$1;;
                esac
                if [[ -z $COMMAND ]]; then
                    echo "Invalid command" 1>&2
                    exit 1
                fi
            else
                echo "You can pick only one command" 1>&2
                exit 1
            fi
        fi
        shift
    done
    
    if [[ $FILES_NUM -eq 0 ]]; then
        FILES="$(cat)"
	if [[ $FILES == "" ]]; then
	    echo "$FILE_TOP"
	    exit 0
	fi
    fi
}

function filter_input() {
    VALIDATE=$(echo "$FILES" | \
                        tr -d " \t\r" | \
                        grep "\S" | \
                        awk \
                        -F ',' \
                        '{
                            if (NR > 1) {
                                if ($3 != "") {
                                    if ($3 ~ /^[0-9]+$/) {}
                                    else {
                                        printf("Invalid age: %s\n", $0)
                                        next
                                    }
                                }
                            }
                        }' \
                   )

    FILTERED_INPUT=$(echo "$FILES" | \
                        tr -d " \t\r" | \
                        grep "\S" | \
                        awk \
                        -v a_datetime=$A_DATETIME \
                        -v b_datetime=$B_DATETIME \
                        -v gender=$GENDER \
                        -F ',' \
                        '{  
                            if (NR > 1) {
                                if (a_datetime != "") {
                                    if(a_datetime > $2) { next }
                                }
                                if (b_datetime != "") {
                                    if(b_datetime < $2) { next }
                                }
                                if (gender != "") {
                                    if(gender != $4) { next }
                                }
                                if ($3 != "") {
                                    if ($3 ~ /^[0-9]+$/) {}
                                    else {
                                        next
                                    }
                                }
                                if ($2 != "") {
                                    if ($2 ~ /^[0-9]{4}-(02-(0[1-9]|[12][0-9])|(0[469]|11)-(0[1-9]|[12][0-9]|30)|(0[13578]|1[02])-(0[1-9]|[12][0-9]|3[01]))+$/) {}
                                    else {
                                        next
                                    }
                                }
				print$0
                            }
			    else {
				print(substr($0, 2, length($0)))
		 	    }
                        }'
                    )
    if [[ $COMMAND == "" ]]; then
        echo "$FILTERED_INPUT"
	if [[ $VALIDATE != "" ]]; then
        	echo "$VALIDATE"
	fi
        exit 0
    fi
}

function print_infected {
    OUTPUT=$(echo "$FILTERED_INPUT" | \
                awk \
                    'END { print NR-1 }'
            )
    echo "$OUTPUT"
}

function gender_func {
	if [[ $WIDTH == "default_width" ]]; then
		WIDTH=100000
	fi
    OUTPUT=$(echo "$FILTERED_INPUT" | \
                awk \
                -v width=$WIDTH \
                -v draw_histogram=$DRAW_HISTOGRAM \
                -F ',' ' \
                    BEGIN {
                        male_count = 0
                        female_count = 0
                        none_count = 0
                    }
                    {
                        if ($4 == "M") { male_count++ }
                        else if ($4 == "Z") { female_count++ }
                        else if ($4 == "") { none_count++ }
                        else { next }
                    }
                    END {
                        if (!draw_histogram) {
                            printf("M: %d\n", male_count)
                            printf("Z: %d\n", female_count)
                            if (none_count > 0) {
                                printf("None: %d", none_count)
                            }
                        }
                        else {
                            male_h = int(male_count / width)
                            printf("M: ")
                            for (i = 0; i < male_h; i++) {
                                printf("#")
                            }
                            printf("\n")

                            female_h = int(female_count / width)
                            printf("Z: ")
                            for (i = 0; i < female_h; i++) {
                                printf("#")
                            }
                            printf("\n")
                            if (none_count > 0) {
                                none_h = int(none_count / width)
                                printf("None: ")
                                for (i = 0; i < none_h; i++) {
                                    printf("#")
                                }
                            }
                        }
                    }'
            )
    echo "$OUTPUT"
}

function age_func {
	if [[ $WIDTH == "default_width" ]]; then
		WIDTH=10000
	fi
    OUTPUT=$(echo "$FILTERED_INPUT" | \
                awk \
                -v width=$WIDTH \
                -v draw_histogram=$DRAW_HISTOGRAM \
                -F ',' '\
                    BEGIN {
                        age_1 = 0
                        age_2 = 0
                        age_3 = 0
                        age_4 = 0
                        age_5 = 0
                        age_6 = 0
                        age_7 = 0
                        age_8 = 0
                        age_9 = 0
                        age_10 = 0
                        age_11 = 0
                        age_12 = 0
                        none = 0
                    }
                    {
                        if (NR > 1) {
                            if ($3 >= 0 && $3 <= 5)
                                age_1++
                            if ($3 >= 6 && $3 <= 15)
                                age_2++
                            if ($3 >= 16 && $3 <= 25)
                                age_3++
                            if ($3 >= 26 && $3 <= 35)
                                age_4++
                            if ($3 >= 36 && $3 <= 45)
                                age_5++
                            if ($3 >= 46 && $3 <= 55)
                                age_6++
                            if ($3 >= 56 && $3 <= 65)
                                age_7++
                            if ($3 >= 66 && $3 <= 75)
                                age_8++
                            if ($3 >= 76 && $3 <= 85)
                                age_9++
                            if ($3 >= 86 && $3 <= 95)
                                age_10++
                            if ($3 >= 96 && $3 <= 105)
                                age_11++
                            if ($3 > 105)
                                age_12++
                            if ($3 == "")
                                none++
                        }
                    }
                    END {
                        if (!draw_histogram) {
                            printf("0-5%4c %d\n", ":", age_1)
                            printf("6-15%3c %d\n", ":", age_2)
                            printf("16-25%2c %d\n", ":", age_3)
                            printf("26-35%2c %d\n", ":", age_4)
                            printf("36-45%2c %d\n", ":", age_5)
                            printf("46-55%2c %d\n", ":", age_6)
                            printf("56-65%2c %d\n", ":", age_7)
                            printf("66-75%2c %d\n", ":", age_8)
                            printf("76-85%2c %d\n", ":", age_9)
                            printf("86-95%2c %d\n", ":", age_10)
                            printf("96-105%c %d\n", ":", age_11)
                            printf(">105%3c %d\n", ":", age_12)
                            printf("None%3c %d", ":", none)
                        }
                        else {
                            age_1_h = int(age_1 / width)
                            printf("0-5%4c ", ":")
                            for (i = 0; i < age_1_h; i++) {
                                printf("#")
                            }
                            printf("\n")

                            age_2_h = int(age_2 / width)
                            printf("6-15%3c ", ":")
                            for (i = 0; i < age_2_h; i++) {
                                printf("#")
                            }
                            printf("\n")

                            age_3_h = int(age_3 / width)
                            printf("16-25%2c ", ":")
                            for (i = 0; i < age_3_h; i++) {
                                printf("#")
                            }
                            printf("\n")

                            age_4_h = int(age_4 / width)
                            printf("26-35%2c ", ":")
                            for (i = 0; i < age_4_h; i++) {
                                printf("#")
                            }
                            printf("\n")

                            age_5_h = int(age_5 / width)
                            printf("36-45%2c ", ":")
                            for (i = 0; i < age_5_h; i++) {
                                printf("#")
                            }
                            printf("\n")

                            age_6_h = int(age_6 / width)
                            printf("46-55%2c ", ":")
                            for (i = 0; i < age_6_h; i++) {
                                printf("#")
                            }
                            printf("\n")

                            age_7_h = int(age_7 / width)
                            printf("56-65%2c ", ":")
                            for (i = 0; i < age_7_h; i++) {
                                printf("#")
                            }
                            printf("\n")

                            age_8_h = int(age_8 / width)
                            printf("66-75%2c ", ":")
                            for (i = 0; i < age_8_h; i++) {
                                printf("#")
                            }
                            printf("\n")

                            age_9_h = int(age_9 / width)
                            printf("76-85%2c ", ":")
                            for (i = 0; i < age_9_h; i++) {
                                printf("#")
                            }
                            printf("\n")

                            age_10_h = int(age_10 / width)
                            printf("86-95%2c ", ":")
                            for (i = 0; i < age_10_h; i++) {
                                printf("#")
                            }
                            printf("\n")

                            age_11_h = int(age_11 / width)
                            printf("96-105%c ", ":")
                            for (i = 0; i < age_11_h; i++) {
                                printf("#")
                            }
                            printf("\n")

                            age_12_h = int(age_12 / width)
                            printf(">105%3c ", ":")
                            for (i = 0; i < age_12_h; i++) {
                                printf("#")
                            }
                            printf("\n")

                            none_h = int(none / width)
                            printf("None%3c ", ":")
                            for (i = 0; i < none_h; i++) {
                                printf("#")
                            }
                        }
                    }'
            )
    echo "$OUTPUT"
}

function proccess_date {
    case $1 in
        "daily")
            SHIFT=0
            DEFAULT_WIDTH=500
            ;;
        "monthly")
            SHIFT=3
            DEFAULT_WIDTH=10000
            ;;
        "yearly")
            SHIFT=6
            DEFAULT_WIDTH=100000
            ;;
    esac

	if [[ $WIDTH == "default_width" ]]; then
		WIDTH=$DEFAULT_WIDTH
	fi

	OUTPUT=$(echo "$FILTERED_INPUT" | \
				awk \
				-v shift=$SHIFT \
				-F ',' ' \
					{
						if (NR > 1) {
							print(substr($2, 1, length($2)-shift))
						}
					}' | \
					sort | \
					uniq -c | \
					awk \
					-v width=$WIDTH \
                	-v draw_histogram=$DRAW_HISTOGRAM \
					-F ' ' ' \
						{
							if (!draw_histogram) {
								printf("%s: %s", $2, $1)
								printf("\n")
							}
							else {
								date_h = int($1 / width)
								printf("%s: ", $2)
								for (i = 0; i < date_h; i++) {
									printf("#")
								}
								printf("\n")
							}
						}'
			)
	echo "$OUTPUT"
}

function procces_location {
    case $1 in
        "countries")
            DEFAULT_WIDTH=100
            DISPLAY_NULL=0
            ;;
        "districts")
            DEFAULT_WIDTH=1000
            DISPLAY_NULL=1
            ;;
        "regions")
            DEFAULT_WIDTH=10000
            DISPLAY_NULL=1
            ;;
    esac

    COL=$2

    if [[ $WIDTH == "default_width" ]]; then
		WIDTH=$DEFAULT_WIDTH
	fi
	OUTPUT=$(echo "$FILTERED_INPUT" | \
                awk \
                -v col=$COL \
                -F ',' ' \
                    {
                        if (NR > 1) {
                            print($col)
                        }
                    }' | \
                    sort | \
                    uniq -c | \
                    awk \
                    -v draw_histogram=$DRAW_HISTOGRAM \
                    -v width=$WIDTH \
                    -v display_null=$DISPLAY_NULL \
                    -F ' ' ' \
                        {
                            if (NR == 1 && display_null == 1) {
                                none = $1
                                next
                            }
                            if (NR > 1) {
                                if (!draw_histogram) {
                                    printf("%s: %s\n", $2, $1)
                                }
                                else {
                                    location_h = int($1 / width)
                                    printf("%s: ", $2)
                                    for (i = 0; i < location_h; i++) {
                                        printf("#")
                                    }
                                    printf("\n")
                                }
                            }
                        }
                        END {   
                            if (display_null) {
                                if (!draw_histogram) {
                                    printf("None: %s", none)
                                }
                                else {
                                    none_h = int(none / width)
                                    printf("None: ")
                                    for (i = 0; i < none_h; i++) {
                                        printf("#")
                                    }
                                    printf("\n")
                                } 
                            }
                        }'
            )
    echo "$OUTPUT"
}

function daily_func {
	proccess_date "daily"
}

function monthly_func {
	proccess_date "monthly"
}

function yearly_func {
	proccess_date "yearly"
}

function countries_func {
	procces_location "countries" 8
}

function districts_func {
	procces_location "districts" 6
}

function regions_func {
	procces_location "regions" 5
}

function procces_commands {
    case $COMMAND in
        infected)
            print_infected
            break
            ;;
	merge)
	    break
	    echo "$FILTERED_INPUT"
	    ;;
        gender)
            gender_func
            break
            ;;
        age)
            age_func
            break
            ;;
        daily)
            daily_func
            break
            ;;
        monthly)
            monthly_func
            break
            ;;
        yearly)
            yearly_func
            break
            ;;
        countries)
            countries_func
            break
            ;;
        districts)
            districts_func
            break
            ;;
        regions)
            regions_func
            break
            ;;
    esac

    if [[ $VALIDATE != "" ]]; then	
    	echo "$VALIDATE" | awk -F ',' '{ print$0 }' 1>&2
    fi
}

main $@