#!/bin/bash
###########################################################################
# NOKIA SQC LAT
#Script default name   :move_rsresult.sh
#Configure version     : 0.1
#Media set             : n.a.
#File generated        : 28.07.2014 MPe
###########################################################################
#
#
# MAke your settings below before running in free world
UNCONFED=TRUE
#PRTARDIR="/home/nsncc/NQA"
#RSEXPDIR="/var/opt/nokia/oss/global/shared/content3/scheduler/export"
CUSTNAME="OSS_Argentina_Personal_rc1"
#
not_possible () {
	case $1 in
	0) 
		echo "Not Configured : Set UNCONFED != TRUE and define directories" ;exit 2
	;;
	1)
		echo "Can not find zip program, exiting" ;exit 1
	;;
	2)
		echo "Can not find directory for reading : ${RSEXPDIR}"; exit 1
	;;
	3)
		echo "Can not write into directory : ${PRTARDIR}"; exit 1
	;;
	4)
		echo "Can not find 2 files matching pattern : ${CUSTNAME}"; exit 1
	;;
	esac
}
[ "${UNCONFED}" != "TRUE" ] || not_possible 0
ZIP="$(which zip &>/dev/null)$?" ; [ "${ZIP}" = "0" ] || not_possible 1
[ -d ${RSEXPDIR} ] || not_possible 2
[ -w ${PRTARDIR} ] || not_possible 3
#
# 
# 
# We do namings according to this convention:
# RS#OSS_[country]_[operator]_[cluster]_[anythingelse]_[ ... ]#_[REPORT]
# REPORT is one of : RSRAN000, RSRAN001, RSRAN073, RSRAN079, RSRAN067,
#                    RSRAN131, RSRAN087, RSRAN069, RSRAN068, RSRAN094
#
# CUSTNAME is the string between #OSS_ ... and ... #_[REPORT]
# NetAct RS adds the following behind those names automatically
# [AGGREGATION]_[DATE]_[TIME]
# e.g. PLMNRNC_20140723_1307 
#
#
MYDIR=$( pwd ); cd $RSEXPDIR
ARCNAME="RS#${CUSTNAME}#_"
FILES=( $(find . -maxdepth 1 -name "RS#${CUSTNAME}*") )
let i=0; let n=${#FILES[@]}; unset TOZIP
if [ $n -ge 2 ] ; then while [ $i -le $n ]
do
	read RS CUSTN REPFIL <<<$(IFS="#";echo ${FILES[$i]})
	SUFFIX=${REPFIL:(-4)}; REPFIL=${REPFIL:0:-4}
	read REPORT AGREG DAY TIM <<<$(IFS="_"; echo ${REPFIL})
	ARCNAME="RS#${CUSTNAME}_${DAY}_${TIM}#_${REPORT}_${AGREG}"
	echo "${FILES[$i]} ---> ${PRTARDIR}/${ARCNAME}.${SUFFIX}"
	TOZIP[$i]="${PRTARDIR}/${ARCNAME}.${SUFFIX}"
	cp ${FILES[$i]} ${TOZIP[$i]}
	let i=$i+1
done; else not_possible 4; fi
NOW="$(date +%Y%m%d-%H%M)"
cd ${PRTARDIR}
zip ${PRTARDIR}/RS#${CUSTNAME}#_${NOW}.zip ${TOZIP[@]}
ls -lart ${PRTARDIR}/RS#${CUSTNAME}#_${NOW}.zip
cd $MYDIR; exit 0

