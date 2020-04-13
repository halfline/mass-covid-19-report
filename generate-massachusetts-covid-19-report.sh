NUM_DAYS=7
POPULATION=6892503
####
PREROLL=1

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
        echo -ne "no change from prior day"
        return
    fi

    echo -ne "up ${DELTA} ${object}, $(print_percentage ${old} ${new} 'only-show-difference') from prior day"
}

get_date()
{
    days_ago="$1"; shift

    date -d "$days_ago days ago" +%B-%e-%Y | tr 'A-Z' 'a-z' | tr -d ' '
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

OLD_TOTAL_POSITIVE=
OLD_TOTAL_TESTS=
OLD_TOTAL_DEATHS=
for i in $(seq ${SEQ_START} ${SEQ_END}); do
    DAY=$((${SEQ_END} - ${i} + ${SEQ_START}))
    DATE=$(get_date ${DAY})
    TXT_FILE=${DATE}.txt

    if [ ! -e ${TXT_FILE} ]; then
        echo "WARNING: data for ${DATE} is missing" 1>&2
        continue
    fi

    NEW_TOTAL_POSITIVE=$(cat ${TXT_FILE} |grep Confirmed | sed 's/[^0-9]*//g');
    NEW_TOTAL_TESTS=$(cat ${TXT_FILE} |grep "^ *Total Patients Tested" | awk '{ print $5 }')
    NEW_TOTAL_DEATHS=$(cat ${TXT_FILE} |grep "^ *Attributed to COVID-19" | awk '{ print $4 }')

    [ -z $NEW_TOTAL_POSITIVE ] && continue;

    # if this is the first time through the loop, we're just trying to get base line stats, not
    # print anything.
    if [ "$i" -lt $((SEQ_START + PREROLL)) ]; then
        OLD_TOTAL_POSITIVE=${NEW_TOTAL_POSITIVE}
        OLD_TOTAL_TESTS=${NEW_TOTAL_TESTS}
        OLD_TOTAL_DEATHS=${NEW_TOTAL_DEATHS}
        continue;
    fi

    echo -ne "$(date -d ${DATE} +'%d %B' ): ${NEW_TOTAL_POSITIVE} people infected"
    if [ -n "${OLD_TOTAL_POSITIVE}" ]; then
        echo -ne " ($(print_change 'cases' ${OLD_TOTAL_POSITIVE} ${NEW_TOTAL_POSITIVE}))"
    fi

    if [ -n "${NEW_TOTAL_TESTS}" ]; then

        echo -ne ",  ${NEW_TOTAL_TESTS} people tested"

        if [ -n "${OLD_TOTAL_TESTS}" ]; then
            echo -ne " ($(print_change 'tests' ${OLD_TOTAL_TESTS} ${NEW_TOTAL_TESTS}))"
        fi

        echo -ne ","

        PREVALENCE=$(print_percentage ${NEW_TOTAL_TESTS} ${NEW_TOTAL_POSITIVE})
        POPULATION_PERCENTAGE=$(print_percentage ${POPULATION} ${NEW_TOTAL_TESTS})
        echo -ne " ${PREVALENCE} tested were infected,"
        echo -ne " sampled ${POPULATION_PERCENTAGE} of the population"
    fi

    if [ -n "${NEW_TOTAL_DEATHS}" ]; then

        echo -ne ", ${NEW_TOTAL_DEATHS} people died"

        if [ -n "${OLD_TOTAL_DEATHS}" ]; then
            echo -ne " ($(print_change 'fatalities' ${OLD_TOTAL_DEATHS} ${NEW_TOTAL_DEATHS}))"
        fi
    fi
    echo
    echo

    OLD_TOTAL_POSITIVE=${NEW_TOTAL_POSITIVE}
    OLD_TOTAL_TESTS=${NEW_TOTAL_TESTS}
    OLD_TOTAL_DEATHS=${NEW_TOTAL_DEATHS}
done


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
