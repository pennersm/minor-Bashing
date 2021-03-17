#!/bin/bash
#----------------------------------------------------------------------------------
MYNAME="$(basename $0)"
TSTAMP=$(date +%Y%m%d-%H%M%S)
: ${OCF_SUCCESS:=0}
: ${OCF_ERR_GENERIC:=1}
: ${OCF_ERR_ARGS:=2}
: ${OCF_ERR_UNIMPLEMENTED:=3}
: ${OCF_ERR_PERM:=4}
: ${OCF_ERR_INSTALLED:=5}
: ${OCF_ERR_CONFIGURED:=6}
: ${OCF_NOT_RUNNING:=7}
rc=$OCF_ERR_GENERIC
#----------------------------------------------------------------------------------
RESOLVERCONF="/etc/resolv.conf"
NICCONF="/etc/network/interfaces" 
MYNICS=( $(ip link show|grep "eth[0-9]:"|cut -d: -f2) )

bold=$(tput bold)
normal=$(tput sgr0)

usage() {
	echo
	printf "\t ${MYNAME} [preset]"
	printf "\n ${bold}USAGE:${normal}\n"
	printf "\t stop networking completely or bring into desired preset\n" 
	printf " Presets:\n"
	printf "\t stop-network\tto stop the networking completely, including IPv6 in kernel, iptables etc ...\n"
	printf "\t start-whonix\tstops all other networking and only enables transparent proxying through whonix GW\n"
	printf "\t start-normal\tregular networking without whonix/tor or other VPN\n\n"
	exit ${rc}
}
#----------------------------------------------------------------------------------

#----------------------------------------------------------------------------------
if [ "`whoami`" != "root" ]
then
        logger -p user.info -t ${TAG} "attempt to run \"${MYSELF}\" as \"`whoami`\" was rejected"
        echo "only root is allowed to execute \"${MYSELF}\""
        exit ${OCF_ERR_PERM}
fi
#----------------------------------------------------------------------------------
shf_debug_break () {
        shf_cont () { : ; } ;
        echo "---------------- enter \"shf_cont\" to resume ------------------"
        unset line
        DBP="#-DEBUG-#"
        while [ "$line" != "shf_cont" ]
        do
                echo -n $DBP
                read line
                eval $line
        done
}
#----------------------------------------------------------------------------------
#----------------------------------------------------------------------------------
#========================================================================================
#========================================================================================
empty_config() {

	NMSTAT=( $(/bin/systemctl status NetworkManager) )
	[ "${NMSTAT[8]}" = "enabled;" ] &&  /bin/systemctl disable NetworkManager &>/dev/null
	[ "${NMSTAT[13]}" = "inactive" ] || /bin/systemctl stop NetworkManager &>/dev/null	
	NMSTAT=( $(/bin/systemctl status NetworkManager) ); rc=$?
	[ "${rc}" = "3" ] || echo "Network Manager: ${NMSTAT[8]} ${NMSTAT[13]}"
	
	chmod -x /etc/network/interfaces.d/* &>/dev/null
	
	
	for NIC in ${MYNICS[@]}
	do
		CURIP=( $(ip addr show ${NIC} |grep inet |sed 's/^ *//g') )
		if [ ! -z "$(echo ${CURIP[@]})" ] ; then
			if [ "$(ip addr del ${CURIP[1]} dev ${CURIP[4]} &>/dev/null )$?" != "0" ] ; then
				echo "problem removing IP ${CURIP[1]} from ${CURIP[4]} - exiting here with ${OCF_ERR_GENERIC}"
				exit ${OCF_ERR_GENERIC}
                	fi
			if [ "$(ip link set ${NIC} down)$?" != "0" ] ; then
				echo "problem stopping ${NIC} - exiting here with ${OCF_ERR_GENERIC}"
				exit ${OCF_ERR_GENERIC}
			fi
		fi
	done

	rm -f ${NICCONF}
	cat <<-EOI >> ${NICCONF}
		# This file describes the network interfaces available on your system"
		# and how to activate them. For more information, see interfaces(5).
		
		source /etc/network/interfaces.d/*
		
		# The loopback network interface
		auto lo
		iface lo inet loopback
	EOI

	rm -f ${RESOLVERCONF}

	iptables --flush
	sleep 3
	sysctl net.ipv6.conf.lo.disable_ipv6=1 &>/dev/null
	sysctl net.ipv6.conf.default.disable_ipv6=1 &>/dev/null
	sysctl net.ipv6.conf.all.disable_ipv6=1 &>/dev/null
	
	systemctl restart networking &>/dev/null
}
unset_loop() {
        unset NET_NIC
        unset NET_IP
        unset NET_GW
        unset NET_NETS
        unset NET_DNS
        unset NET_FWR
        unset ONLY_EXIT_ALLOWED
        unset NET_CMD_PRE[@]
        unset NET_CMD_POS[@]
}

set_hostonly() {
	# ------------- host only --------------------
	NET_NIC="eth1"
	NET_IP="172.16.0.10/24"
	NET_GW="172.16.0.1" 
	NET_NET=""
	NET_DNS=""
	NET_FWR="/etc/network/iptables.hostonly.rules"
	ONLY_EXIT_ALLOWED="0"
}
set_bridged() {
	# ---------- normal-bridge -------------------
	NET_NIC="eth0"
	NET_IP="192.168.4.10/24"
	NET_GW="192.168.4.1"
	NET_NET="default"
	NET_DNS="208.67.222.222 208.67.202.202 8.8.8.8"
	NET_FWR="/etc/network/iptables.normalbridged.rules"
	ONLY_EXIT_ALLOWED="0"
}
set_whonix() {
	# ------------- whonix --------------------
	NET_NIC="eth2"
	NET_IP="10.152.152.12/24" 
	NET_GW="10.152.152.10"
	NET_NET="default" 
	NET_DNS="10.152.152.10"
	NET_FWR="/etc/network/iptables.whonix.rules"
	ONLY_EXIT_ALLOWED="1"
	NET_CMD_PRE[0]="systctl net.ipv4.tcp_timestamps=0"
}
set_dns() {

	DNS=( $(echo ${NET_DNS}) )
	if [ ! -z "${NET_DNS}" ] ; then
		rm -f ${RESOLVERCONF}
        	touch ${RESOLVERCONF}; chown root:root ${RESOLVERCONF}; chmod 744 ${RESOLVERCONF}
                for SERVER in ${DNS[@]}
                do
                        echo "nameserver ${SERVER}" >> ${RESOLVERCONF} && :
                done
        fi
}
status() {

	GW="$(ip route show|grep default)"; rc=$?
	if [ "${ACTION}" = "show-status" ] ; then
		printf "\n\n"
		ip address show
		printf "${bold}=====================================================================================${normal}\n"
		netstat -rn
		printf "${bold}=====================================================================================${normal}\n"
		cat ${RESOLVERCONF}
		printf "\n\n"
	fi

	if [ "${rc}" = "0" ] && [ "${GW}X" != "X" ] || [ "${ACTION}" = "show-status" ] ; then
        	PUBIP="$(curl https://api.ipify.org)" &&
        	rc=$?
        	if [ "${rc}" = "0" ] ; then  printf "\t${bold} Public IP : ${PUBIP}${normal}\n\n" ;
               	else echo " ... something seems to be wrong. Check you network cables!"
	               	exit $rc
        	fi
	elif [ ${ACTION} = "stop-network" ] ; then
        	exit $rc
	else
        	echo " ... something seems to be wrong. Check your network!"
        	exit ${OCF_ERR_GENERIC}
	fi
}


#===========================================================================================================

[ "$#" = "1" ] || usage; while [ $# != 0 ]
do
	ACTION="$1"
	case $1 in

	show-status|status|stat)

		ACTION="show-status"
		status
		exit 0
	;;

	start-whonix)
		
		unset_loop	
		empty_config
		set_whonix

		if [ "${ONLY_EXIT_ALLOWED}" != "1" ] ; then	
			echo "whonix mode will only be effective if you disable all other NICs. check the configuration."
			exit ${OCF_ERR_CONFIGURED}

		elif [ ! -z "${NET_NIC}" ] ; then  

			ip route flush table main && sleep 1
			ip link set ${NET_NIC} up && sleep 1
			ip addr add ${NET_IP} dev ${NET_NIC}
			ip route add ${NET_NET} via ${NET_GW} dev ${NET_NIC}
			
			set_dns set_whonix

		else echo " No NICs found! Exiting ..." ; exit ${OCF_ERR_INSTALLED}	
		fi
		echo "Waiting a moment to see if whonix GW connection succeeds ..."
		ping -nq -c 3 -i 3 ${NET_GW} 
	;;

	stop-network)
		
		empty_config
		ip route flush table main
	;;

	start-normal)
	
		empty_config
		ip route flush table main && sleep 1
		chmod +x /etc/network/interfaces.d/* &>/dev/null
	
		for config_interf in set_hostonly set_bridged
		do
			unset_loop
			eval ${config_interf}
			ip link set ${NET_NIC} up && sleep 1
			ip addr add ${NET_IP} dev ${NET_NIC}
			[ -z "${NET_NET}" ] || ip route add ${NET_NET} via ${NET_GW} dev ${NET_NIC}
			[ -z "${NET_DNS}" ] || set_dns ${NET_DNS} 
		done
	;;
	*)
		usage; rc=$?
	;;
esac ; shift ; done
status
