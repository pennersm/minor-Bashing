#!/bin/bash
#---------------------------------------------------------
MLOGDIR="/root"
NOW="$(date +%y%m%d-%H%M%S)"
PREFIX="$(hostname)-${NOW}"
CMDLOGF="${MLOGDIR}/cmdlog.log"
TARFILE="${MLOGDIR}/${PREFIX}.tar"
#---------------------------------------------------------
run_command() {
	local CMD=$*
	local RUN="$(echo ${CMD}|sed 's/^[ \t]*//; s/#[^#]*$//; /#/d')"
	if [ ! -z "${RUN}" ] ; then
		echo "===================================================================================================="
		echo "running $(date +%y%m%d-%H%M%S)  :  $*"
		echo "===================================================================================================="
		eval $* ; rc=$?
		echo ; echo ; echo "last exit status: ${rc}"
	fi
	return ${rc}
}
#---------------------------------------------------------
add_archive() {
	local FILES=$*
	[ -f "${TARFILE}" ] || touch ${TARFILE}

	for THISLOG in ${FILES[@]} ; do
		FILE=$(basename ${THISLOG})
		DIR=$(dirname ${THISLOG})

		tar -rf ${TARFILE} -C ${DIR} ${FILE}
	done
}
#---------------------------------------------------------
# COLLECTING LOGFILES
#
collect_syslogs() {
	LOG[0]="/var/log/messages"
	LOG[1]="/var/log/daemon.log"
	LOG[2]="/var/log/syslog"

	for LF in ${LOG[@]} ; do
		[ -f "${LF}" ] && add_archive ${LF}
	done
}
collect_analytlog() {
	ANALOGD="/var/log/nss"
	ANALTAR="${MLOGDIR}/${PREFIX}--ANALYTICS-var-log-nss.tar"

	if [ -d "${ANALOGD}" ] ; then 
		tar -cf ${ANALTAR} -C ${ANALOGD} .
		sleep 1 ; sync ; add_archive ${ANALTAR} 
		sleep 1 ; sync ; rm -f ${ANALTAR}
	fi
}
#---------------------------------------------------------
# COLLECTING TCPDUMP
#
collect_tcpdump() {
	PACKETS="1000"
	INTERFA="eno1"
	PCAPFIL="${PREFIX}-${INTERFA}.pcap"

	rc="$(tcpdump -i ${INTERFA} -nn -s0 -c ${PACKETS} -w ${MLOGDIR}/${PCAPFIL} &>/dev/null)"
	sleep 1 ; sync
	tar -rf ${TARFILE} -C ${MLOGDIR} ${PCAPFIL}
	sleep 1; sync
	rm -f ${PCAPFIL}
}
#---------------------------------------------------------
#---------------------------------------------------------
printf "\n\e[1:34m$(hostname) :\e[0m\n"
touch ${TARFILE}
collect_tcpdump
collect_analytlog
collect_syslogs
#---------------------------------------------------------
while read CMD; do run_command "${CMD}" 2>&1|tee -a ${CMDLOGF}; done <<EOC
# ADD MORE COMMANDS TO LIST IF NEEDED HERE - DONT REMOVE THE EOC: 
#-------------------------------------------------------------------------- go through list:
pmstat
vmstat 5 6
sar -u
df -kh
sar -d
ip route
netstat -i
ip addr show
EOC

add_archive ${CMDLOGF}
sleep 1
#---------------------------------------------------------
gzip ${TARFILE}
sleep 1
echo "exiting and generated tarfile :${TARFILE}.gz"

