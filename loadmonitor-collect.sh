#!/bin/bash
for HOST in 162 163 164; do
	printf "\e[1:34m COLLECTING ON 10.159.159.${HOST} \e[0m";printf "\n"
	RESFILE="$(ssh -q root@10.159.159.${HOST} /root/loadmonitor.sh |grep 'exiting and generated tarfile :'|cut -d':' -f2)"
	echo " temporarily created ${RESFILE} on 10.159.159.${HOST} -> make sure it wont stay there forever if something crashes" 
	sleep 1 ; LOC=$(basename ${RESFILE})
	scp -q root@10.159.159.${HOST}:/${RESFILE} /root/${LOC}
	ssh -q root@10.159.159.${HOST} "rm -f ${RESFILE}" 
done 
