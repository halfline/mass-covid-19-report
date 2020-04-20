DEFAULT_NUM_DAYS="7"
POPULATION=6892503
####
PREROLL=1
NUM_DAYS="${1:-$DEFAULT_NUM_DAYS}"

print_percentage()
{
    old="$1"; shift
    new="$1"; shift
    flags="$1"; shift

    if echo "$flags" | fgrep -wq "only-show-difference"; then
        ONLY_SHOW_DIFFERENCE=1
    else
        ONLY_SHOW_DIFFERENCE=0
    fi

    if [ "${ONLY_SHOW_DIFFERENCE}" != "0" ]; then
        DELTA=$((new - old))
        [ "${DELTA}" -gt 0 ] && echo -ne "+"

        echo -ne $(python3 -c "print('%.2f' % ((${DELTA} / ${old}) * 100.0))")
    else
        echo -ne $(python3 -c "print('%.2f' % ((${new} / ${old}) * 100))")
    fi

    echo -ne "%"
}

print_change()
{
    object="$1"; shift
    old="$1"; shift
    new="$1"; shift

    DELTA=$((new - old))

    if [ ${new} -eq ${old} ]; then
        echo -ne "no change from prior report"
        return
    fi

    echo -ne "up ${DELTA} ${object}, $(print_percentage ${old} ${new} 'only-show-difference') from prior report"
}

get_date()
{
    days_ago="$1"; shift

    date -d "$days_ago days ago" +%B-%e-%Y | tr 'A-Z' 'a-z' | tr -d ' '
}

record_name()
{
    field="$1"; shift
    iteration="$1"; shift

    echo "${field}-${iteration}"
}

FIELDS=(total-positive total-tests total-deaths death-range death-range-span)

generate_record_index()
{
    declare -n record="$1"; shift
    index_name="$1"; shift

    for FIELD in "${FIELDS[@]}"; do
        record[${FIELD}]="$(record_name ${FIELD} ${index_name})"
    done
}

SEQ_START=0
SEQ_END=$((NUM_DAYS - 1 + PREROLL))

for i in $(seq ${SEQ_START} ${SEQ_END}); do
    DATE=$(get_date ${i})
    PDF_FILE=${DATE}.pdf
    [ ! -e ${PDF_FILE} ] && curl -s https://www.mass.gov/doc/covid-19-cases-in-massachusetts-as-of-${DATE}/download > ${PDF_FILE}

    [ ! -e ${PDF_FILE} ] && curl -s https://www.mass.gov/doc/covid-19-cases-in-massachusetts-as-of-${DATA}-x-updated4pm/download > ${PDF_FILE}

    if ! grep -q /Root ${PDF_FILE}; then
        rm -f ${PDF_FILE}
        continue
    fi

    TXT_FILE=${DATE}.txt
    if [ ! -e ${TXT_FILE} ]; then
        pdftotext -layout ${PDF_FILE} ${TXT_FILE}

        [ ! -e ${TXT_FILE} ] && continue

        if [ "${TXT_FILE}" == "march-31-2020.txt" ]; then
            patch -N "${TXT_FILE}" <<- EOF
		--- march-31-2020.txt	2020-04-08 16:09:29.305292845 -0400
		+++ old/march-31-2020.txt	2020-04-08 16:10:56.569292714 -0400
		@@ -134,13 +134,10 @@
		 BioReference Laboratories
		 Other                                                       6
		                                                             21                       41
		-                                                                                      60
		-Boston  MedicalTested*
		-Total Patients  Center                                     125
		-                                                           6620                      416
		-                                                                                    46935
		+Boston  Medical Center                                      125                      416
		+Total Patients Tested*                                      6620                     46935
		 
		 Data are cumulative and current as of March 31, 2020 at 12:30PM.
		 *Other commercial and clinical laboratories continue to come on line. As laboratory testing results are
		 processed and the source verified, they will be integrated into this daily report.
		-
		\ No newline at end of file
		+
		EOF
        fi
    fi
done

declare -A DATA_STORE
declare -A RECORD PRIOR_RECORD START_RECORD END_RECORD

generate_record_index START_RECORD ${SEQ_START}

LAST_GOOD_DAY=-1
for i in $(seq ${SEQ_START} ${SEQ_END}); do
    generate_record_index RECORD "${i}"
    generate_record_index PRIOR_RECORD "$((i - 1))"

    DAY=$((${SEQ_END} - ${i} + ${SEQ_START}))
    DATE=$(get_date ${DAY})
    TXT_FILE=${DATE}.txt

    if [ ! -e ${TXT_FILE} ]; then
        if [ ${i} -ne ${SEQ_END} ]; then
            echo "WARNING: data for ${DATE} is missing" 1>&2
        fi
        continue
    fi

    DATA_STORE[${RECORD['total-positive']}]=$(cat ${TXT_FILE} |grep Confirmed | sed 's/[^0-9]*//g')
    DATA_STORE[${RECORD['total-tests']}]=$(cat ${TXT_FILE} |grep "^ *Total Patients Tested" | awk '{ print $5 }')
    DATA_STORE[${RECORD['total-deaths']}]=$(cat ${TXT_FILE} |grep "^ *Attributed to COVID-19" | awk '{ print $4 }')
    DATA_STORE[${RECORD['death-range']}]=$(cat ${TXT_FILE} | grep "Dates of Death" | awk -F: '{ print $2 }' | sed 's/)//')

    [ -z ${DATA_STORE[${RECORD['total-positive']}]} ] && continue;

    # if this is the first time through the loop, we're just trying to get base line stats, not
    # print anything.
    if [ "$i" -lt $((SEQ_START + PREROLL)) ]; then
        continue;
    fi

    echo -ne "$(date -d ${DATE} +'%d %B' ): ${DATA_STORE[${RECORD['total-positive']}]} people infected"

    if [ -n "${DATA_STORE[${PRIOR_RECORD['total-positive']}]}" ]; then
        echo -ne " ($(print_change 'cases' ${DATA_STORE[${PRIOR_RECORD['total-positive']}]} ${DATA_STORE[${RECORD['total-positive']}]}))"
    fi

    if [ -n "${DATA_STORE[${RECORD['total-positive']}]}" ]; then

        echo -ne ", ${DATA_STORE[${RECORD['total-tests']}]} people tested"

        if [ -n "${DATA_STORE[${PRIOR_RECORD['total-tests']}]}" ]; then
            echo -ne " ($(print_change 'tests' ${DATA_STORE[${PRIOR_RECORD['total-tests']}]} ${DATA_STORE[${RECORD['total-tests']}]})"
        fi

        echo -ne ","

        PREVALENCE=$(print_percentage ${DATA_STORE[${RECORD['total-tests']}]} ${DATA_STORE[${RECORD['total-positive']}]})
        POPULATION_PERCENTAGE=$(print_percentage ${POPULATION} ${DATA_STORE[${RECORD['total-tests']}]})
        echo -ne " ${PREVALENCE} tested were infected,"
        echo -ne " sampled ${POPULATION_PERCENTAGE} of the population"
    fi

    if [ -n "${DATA_STORE[${RECORD['total-deaths']}]}" ]; then
        unset NEW_DEATH_RANGE_DAYS
        if [ -n "${DATA_STORE[${RECORD['death-range']}]}" ]; then
            NEW_DEATH_RANGE_START=$(echo ${DATA_STORE[${RECORD['death-range']}]} | awk '{ print $1 }')
            NEW_DEATH_RANGE_END=$(echo ${DATA_STORE[${RECORD['death-range']}]} | awk '{ print $3 }')
            NEW_DEATH_RANGE_START_DATE=$(date -d $NEW_DEATH_RANGE_START +%s)
            NEW_DEATH_RANGE_END_DATE=$(date -d $NEW_DEATH_RANGE_END +%s)

            DATA_STORE[${RECORD['death-range-span']}]=$(((NEW_DEATH_RANGE_END_DATE - NEW_DEATH_RANGE_START_DATE) / (60 * 60 * 24)))
        fi

        echo -ne ", ${DATA_STORE[${RECORD['total-deaths']}]} people died"

        if [ -n "${DATA_STORE[${PRIOR_RECORD['total-deaths']}]}" ]; then
            echo -ne " ($(print_change 'fatalities' ${DATA_STORE[${PRIOR_RECORD['total-deaths']}]} ${DATA_STORE[${RECORD['total-deaths']}]}))"
        fi

        if [ -n "${DATA_STORE[${RECORD['death-range-span']}]}" ]; then
            DEATHS_PER_DAY=$(((${DATA_STORE[${RECORD['total-deaths']}]} - ${DATA_STORE[${PRIOR_RECORD['total-deaths']}]}) / ${DATA_STORE[${RECORD['death-range-span']}]}))
            echo -ne ", about $DEATHS_PER_DAY deaths per day over the last ${DATA_STORE[${RECORD['death-range-span']}]} days."
        fi
    fi
    echo
    echo

    LAST_GOOD_DAY=${i}
done

if [ $LAST_GOOD_DAY -ge $SEQ_START ]; then
    generate_record_index END_RECORD ${LAST_GOOD_DAY}
fi

if [ ${#END_RECORD[@]} -gt 0 ]; then
    DAYS_PROCESSED=$((LAST_GOOD_DAY - SEQ_START))
    CASES_PER_DAY=$(((${DATA_STORE[${END_RECORD['total-positive']}]} - ${DATA_STORE[${START_RECORD['total-positive']}]}) / DAYS_PROCESSED))
    TESTS_PER_DAY=$(((${DATA_STORE[${END_RECORD['total-tests']}]} - ${DATA_STORE[${START_RECORD['total-tests']}]}) / DAYS_PROCESSED))
    TESTS_PER_100K_PEOPLE=$(((TESTS_PER_DAY * 100000) / ${POPULATION}))
    DEATHS_PER_REPORT=$(((${DATA_STORE[${END_RECORD['total-deaths']}]} - ${DATA_STORE[${START_RECORD['total-deaths']}]}) / DAYS_PROCESSED))

    # FIXME: the deaths per day number here is just looking at the last report and not the $NUM_DAYS worth of reports
    if [ $DAYS_PROCESSED -ne $NUM_DAYS ]; then
        echo -ne "Over the ${DAYS_PROCESSED} days before today"
    else
        echo -ne "Over the last ${DAYS_PROCESSED} days (including today)"
    fi
    echo -ne " there have been an average of ${CASES_PER_DAY} cases per day, an average of ${TESTS_PER_DAY} tests per day (${TESTS_PER_100K_PEOPLE} tests for every 100,000 people, needs to be greater than 152 to be adequate), and an average of ${DEATHS_PER_REPORT} deaths per report (about $((DEATHS_PER_REPORT / DAYS_PROCESSED)) per day)"
fi

for day in $(seq 1 5); do
    DATE=$(date -d "$day days ago" +%Y-%m-%d)
    US_MOBILITY_REPORT=${DATE}_US_Mobility_Report_en.pdf
    MA_MOBILITY_REPORT=${DATE}_US_Massachusetts_Mobility_Report_en.pdf

    if [ ! -e ${US_MOBILITY_REPORT} ]; then
        wget --quiet https://www.gstatic.com/covid19/mobility/${US_MOBILITY_REPORT}
    fi

    if [ ! -e ${MA_MOBILITY_REPORT} ]; then
        wget --quiet https://www.gstatic.com/covid19/mobility/${MA_MOBILITY_REPORT}
    fi
done
