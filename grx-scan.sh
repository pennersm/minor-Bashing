#!/bin/bash
NOW="$(date +%y%m%d-%H%M%S)"
MYNAME="$(basename $0)"
LOGDIR="/home/penners"
#------------------------------------
bold=$(tput bold)
normal=$(tput sgr0)

usage() {
	echo
	printf "\t ${bold}${MYNAME} [operation] [file]${normal}\n\n"
	printf "\t execute different predefined scan operations over an IP list in a file\n" 
	printf "\n ${bold}[operation]${normal}\n\n"
	printf "\t upscan   : to nmap -sn -s sweep if the hosts in [file] are up.\n"
	printf "\t portscan : to scan a predefined list of UDP and TCP ports (hardcoded)\n"
	printf "\t sctp     : look if there are any SCTP ports replying\n"
	printf "\t windows  : look if it replies to windows specific vulns like double-pulsar (hardcoded)\n"
	printf "\t whois    : trying to add whois information\n"
	printf "\n\n\t\t ${bold}USE ONE OPERATION A TIME ! ${normal}\n\n\n"
	exit ${rc}
}
#-------------------------------------
IP_up() {
	IP=$1
	SUFFIX=$(echo ${IP}|cut -d. -f4)
	PREFIX=$(echo ${IP}|cut -d. -f1-3)
	[ "${SUFFIX}" = "0" ] && IP=${PREFIX}".0-255"
	nmap -n -sn ${IP} -oG ${IP} | awk '/Up$/{print $2}'
}    
#--------------------------------------  
Port_up() {
	IP=$1
	SUFFIX=$(echo ${IP}|cut -d. -f4)
	PREFIX=$(echo ${IP}|cut -d. -f1-3)
	[ "${SUFFIX}" = "0" ] && IP=${PREFIX}".0-255"
	UDP="2123,2152,3386,161,162,137,138,514,123,179,500,995,110,53,49,66,67,68,111,465,130,131,132"
	TCP="443,80,22,23,3389,25,110,995,137,514,179,138,139,445,53,49,66,67,68,111,130,131,132,465"
	masscan -n -pT:${TCP},U:${UDP} ${IP} 2>&1|grep open
}
#--------------------------------------  
SCTP_up () {
	IP=$1
	SUFFIX=$(echo ${IP}|cut -d. -f4)
	PREFIX=$(echo ${IP}|cut -d. -f1-3)
	[ "${SUFFIX}" = "0" ] && IP=${PREFIX}".0-255"
	nmap -sZ -n -p1-65535 -oG ${IP} | awk '/Up$/{print $2}'
}
#--------------------------------------
whois_up () {
	declare -a IPLIST=("${!1}")
	echo;echo "Found ${#IPLIST[@]} /24 networks to look up in whois ..." 
	OLD="0"
	for IP in "${IPLIST[@]}" ; do
		mapfile WHOIS < <(whois $IP.0 2> /dev/null |tr -d '*`$' )
		for((i=0;i<${#WHOIS[@]};i++)) ; do
			CLEANED="$(echo ${WHOIS[$i]}|tr -dc '[:alnum:] :-_ \n\r' | tr -s ' ')"
			ELEMENT="$(echo ${CLEANED}|cut -d: -f1| tr '[:upper:]' '[:lower:]')"
		#-----------------------------------------
			case ${ELEMENT} in
	
				inetnum)
					V_inetnum="$(echo ${WHOIS[$i]}|cut -d: -f2-)"
					found_inetnum="yes"
				;;

				netrange|cidr|inetrev)
					OTHER_inetnum="$(echo ${WHOIS[$i]}|cut -d: -f2-|tr ',' ' '|tr -s ' ' )"
				;;

				country)
					V_country="$(echo ${WHOIS[$i]}|cut -d: -f2-|tr -d ' '|tr '[:lower:]' '[:upper:]'|cut -c -3)"
				;;
				org-name|owner|orgname)
					V_owner="$(echo ${WHOIS[$i]}|cut -d: -f2-|cut -c -30|tr ',' ' '|tr -s ' ' )"
					found_org="yes"
				;;
				descr)
					if [ "${found_descr}" != "yes" ] ; then
						V_descr="$(echo ${WHOIS[$i]}|cut -d: -f2-|cut -c -30|tr ',' ' '|tr -s ' ' )"
						found_descr="yes"
					fi
				;;
				addr)
					if [ "${found_addr}" != "yes" ] ; then
						V_addr="$(echo ${WHOIS[$i]}|cut -d: -f2-|tr ',' ' '|tr -s ' ' )"
						found_addr="yes"
					fi
				;;
				netname)
					V_netname="$(echo ${WHOIS[$i]}|cut -d: -f2-)"
				;;
			esac
			
		done

		[ "${found_inetnum}" = "yes" ] || V_inetnum="${OTHER_inetnum}"
		LOGLINE="${V_inetnum}, ${V_country}, ${V_owner} ${V_descr} ${V_addr} ${V_netname}"
		SAME=$(echo ${LOGLINE[@]}| md5sum)
		if [ "${OLD}" != "${SAME}" ] ; then
			OLD=${SAME}
			echo "${IP}, ${LOGLINE[@]}"
		fi
		unset LOGLINE V_inetnum OTHER_inetnum V_country V_descr V_addr V_owner V_netname found_descr found_inetnum found_org found_addr

done	 

}
#--------------------------------------
#
[ "$#" = "2" ] || usage; 
[ -f "${2}" ]  || ( scan called but no input file !)
LISTFILE=$2

while [ $# != 1 ]
do
	case $1 in

	upscan) 
		
 		LOGF=${LOGDIR}/grxscan--upscan-${NOW}.log

		while read ADDR; do IP_up ${ADDR} 2>&1|tee -a ${LOGF}
		done < ${LISTFILE}
	;;
	portscan)

		LOGF=${LOGDIR}/grxscan--portscan-${NOW}.log

                while read ADDR; do Port_up ${ADDR} 2>&1|tee -a ${LOGF}
                done < ${LISTFILE}

	;;
	sctp)
		LOGF=${LOGDIR}/grxscan--sctp-${NOW}.log
		
		while read ADDR; do SCTP_up ${ADDR} 2>&1|tee -a ${LOGF}
		done < ${LISTFILE}

	;;	
	whois)
		LOGF=${LOGDIR}/grxscan--whois-${NOW}.log

		unset FIX; unset ALLNETS[@]
	       	while read ADDR; do 
			SUFIX="$(echo ${ADDR}|cut -d. -f1-3)"
			if [ "${FIX}" != "${SUFIX}" ] ; then
				ALLNETS=("${ALLNETS[@]}" "${SUFIX}")
				FIX="${SUFIX}"
			fi
		done < ${LISTFILE}
		whois_up ALLNETS[@] 2>&1|tee -a ${LOGF}
	;;	
		
   	*)
		usage; rc=$?
	;;
esac ; shift ; done

