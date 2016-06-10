#!/bin/bash
# ---------------------------------------------------------------------------
# vh-diks-hal.sh

# Copyright 2016, DREAMgenics S.L.
# All rights reserved.

# Usage: bash vh-diks-hal.sh [-h|--help]

# Revision history:
# 2016-06-09 Created by Hal
# ---------------------------------------------------------------------------

PROGNAME=${0##*/}
VERSION="0.1"

clean_up() { # Perform pre-exit housekeeping
  return
}

error_exit() {
  echo -e "${PROGNAME}: ${1:-"Unknown Error"}" >&2
  clean_up
  exit 1
}

graceful_exit() {
  clean_up
  exit
}

signal_exit() { # Handle trapped signals
  case $1 in
    INT)
      error_exit "Program interrupted by user" ;;
    TERM)
      echo -e "\n$PROGNAME: Program terminated" >&2
      graceful_exit ;;
    *)
      error_exit "$PROGNAME: Terminating on unknown signal" ;;
  esac
}

usage() {
  echo -e "Usage: $PROGNAME [-h|--help]"
}

help_message() {
  cat <<- _EOF_
  $PROGNAME ver. $VERSION
  Formating new disks and creating raid 0

  $(usage)

  Options:
	-h, --help  Display this help message and exit.
	-b         base directory for mount points (default: /datadisks)
	-h         this help message
	-s         create a striped RAID array (no redundancy)

  NOTE: You must be the superuser to run this script.

_EOF_
  return
}

# Trap signals
trap "signal_exit TERM" TERM HUP
trap "signal_exit INT"  INT

# Check for root UID
if [[ $(id -u) != 0 ]]; then
  error_exit "You must be the superuser to run this script."
fi

# Parse command-line
while [[ -n $1 ]]; do
  case $1 in
    -h | --help)
      help_message; graceful_exit ;;
    -* | --*)
      usage
      error_exit "Unknown option $1" ;;
    *)
      echo "Argument $1 to process..." ;;
  esac
  shift
done



# Main logic
# Base path for data disk mount points
DATA_BASE="/datosraid"
#Partition and format data disks as raid set
RAID_CONFIGURATION=1


get_next_md_device() {
    shopt -s extglob
    LAST_DEVICE=$(ls -1 /dev/md+([0-9]) 2>/dev/null|sort -n|tail -n1)
    if [ -z "${LAST_DEVICE}" ]; then
        NEXT=/dev/md0
    else
        NUMBER=$((${LAST_DEVICE/\/dev\/md/}))
        NEXT=/dev/md${NUMBER}
    fi
    echo ${NEXT}
}

is_partitioned() {
    OUTPUT=$(partx -s ${1} 2>&1)
    egrep "partition table does not contains usable partitions|failed to read partition table" <<< "${OUTPUT}" >/dev/null 2>&1
    if [ ${?} -eq 0 ]; then
        return 1
    else
        return 0
    fi    
}
has_filesystem() {
    DEVICE=${1}
    OUTPUT=$(file -L -s ${DEVICE})
    grep filesystem <<< "${OUTPUT}" > /dev/null 2>&1
    return ${?}
}

scan_for_new_disks() {
    # Looks for unpartitioned disks
    declare -a RET
    DEVS=($(ls -1 /dev/sd*|egrep -v "[0-9]$"))
    for DEV in "${DEVS[@]}";
    do
        # The disk will be considered a candidate for partitioning
        # and formatting if it does not have a sd?1 entry or
        # if it does have an sd?1 entry and does not contain a filesystem
        is_partitioned "${DEV}"
        if [ ${?} -eq 0 ];
        then
            has_filesystem "${DEV}1"
            if [ ${?} -ne 0 ];
            then
                RET+=" ${DEV}"
            fi
        else
            RET+=" ${DEV}"
        fi
    done
    echo "${RET}"
}

get_next_mountpoint() {
#    DIRS=$(ls -1d ${DATA_BASE}/disk* 2>/dev/null| sort --version-sort)
#    MAX=$(echo "${DIRS}"|tail -n 1 | tr -d "[a-zA-Z/]")
#    if [ -z "${MAX}" ];
 #   then
 #       echo "${DATA_BASE}/disk1"
 #       return
 #   fi
 #   IDX=1
 #   while [ "${IDX}" -lt "${MAX}" ];
 #   do
 #       NEXT_DIR="${DATA_BASE}/disk${IDX}"
 #       if [ ! -d "${NEXT_DIR}" ];
 #       then
 #           echo "${NEXT_DIR}"
 #           return
 #       fi
 #       IDX=$(( ${IDX} + 1 ))
 #   done
 #   IDX=$(( ${MAX} + 1))
 #   echo "${DATA_BASE}/disk${IDX}"
 echo "${DATA_BASE}"
}

add_to_fstab() {
    UUID=${1}
    MOUNTPOINT=${2}
    grep "${UUID}" /etc/fstab >/dev/null 2>&1
    if [ ${?} -eq 0 ];
    then
        echo "Not adding ${UUID} to fstab again (it's already there!)"
    else
        LINE="UUID=\"${UUID}\"\t${MOUNTPOINT}\text4\tnoatime,nodiratime,nodev,noexec,nosuid\t1 2"
        echo -e "${LINE}" >> /etc/fstab
    fi
}

do_partition() {
# This function creates one (1) primary partition on the
# disk, using all available space
    _disk=${1}
    _type=${2}
    if [ -z "${_type}" ]; then
        # default to Linux partition type (ie, ext3/ext4/xfs)
        _type=83
    fi
    echo "n
p
1


t
${_type}
w"| fdisk "${_disk}"

#
# Use the bash-specific $PIPESTATUS to ensure we get the correct exit code
# from fdisk and not from echo
if [ ${PIPESTATUS[1]} -ne 0 ];
then
    echo "An error occurred partitioning ${_disk}" >&2
    echo "I cannot continue" >&2
    exit 2
fi
}
#end do_partition

scan_partition_format()
{
    log "Begin scanning and formatting data disks"

    DISKS=($(scan_for_new_disks))

	if [ "${#DISKS}" -eq 0 ];
	then
	    log "No unpartitioned disks without filesystems detected"
	    return
	fi
	echo "Disks are ${DISKS[@]}"
	for DISK in "${DISKS[@]}";
	do
	    echo "Working on ${DISK}"
	    is_partitioned ${DISK}
	    if [ ${?} -ne 0 ];
	    then
	        echo "${DISK} is not partitioned, partitioning"
	        do_partition ${DISK}
	    fi
	    PARTITION=$(fdisk -l ${DISK}|grep -A 1 Device|tail -n 1|awk '{print $1}')
	    has_filesystem ${PARTITION}
	    if [ ${?} -ne 0 ];
	    then
	        echo "Creating filesystem on ${PARTITION}."
	#        echo "Press Ctrl-C if you don't want to destroy all data on ${PARTITION}"
	#        sleep 10
	        mkfs -j -t ext4 ${PARTITION}
	    fi
	    MOUNTPOINT=$(get_next_mountpoint)
	    echo "Next mount point appears to be ${MOUNTPOINT}"
	    [ -d "${MOUNTPOINT}" ] || mkdir -p "${MOUNTPOINT}"
	    read UUID FS_TYPE < <(blkid -u filesystem ${PARTITION}|awk -F "[= ]" '{print $3" "$5}'|tr -d "\"")
	    add_to_fstab "${UUID}" "${MOUNTPOINT}"
	    echo "Mounting disk ${PARTITION} on ${MOUNTPOINT}"
	    mount "${MOUNTPOINT}"
	done
}
create_striped_volume()
{
    DISKS=(${@})

	if [ "${#DISKS[@]}" -eq 0 ];
	then
	    log "No unpartitioned disks without filesystems detected"
	    return
	fi

	echo "Disks are ${DISKS[@]}"

	declare -a PARTITIONS

	for DISK in "${DISKS[@]}";
	do
	    echo "Working on ${DISK}"
	    is_partitioned ${DISK}
	    if [ ${?} -ne 0 ];
	    then
	        echo "${DISK} is not partitioned, partitioning"
	        do_partition ${DISK} fd
	    fi

	    PARTITION=$(fdisk -l ${DISK}|grep -A 2 Device|tail -n 1|awk '{print $1}')
	    PARTITIONS+=("${PARTITION}")
	done

    MDDEVICE=$(get_next_md_device)    
	sudo udevadm control --stop-exec-queue
	mdadm --create ${MDDEVICE} --level 0 --raid-devices ${#PARTITIONS[@]} ${PARTITIONS[*]}
	sudo udevadm control --start-exec-queue
	
	MOUNTPOINT=$(get_next_mountpoint)
	echo "Next mount point appears to be ${MOUNTPOINT}"
	[ -d "${MOUNTPOINT}" ] || mkdir -p "${MOUNTPOINT}"

	#Make a file system on the new device
	STRIDE=128 #(512kB stripe size) / (4kB block size)
	PARTITIONSNUM=${#PARTITIONS[@]}
	STRIPEWIDTH=$((${STRIDE} * ${PARTITIONSNUM}))

	mkfs.ext4 -b 4096 -E stride=${STRIDE},stripe-width=${STRIPEWIDTH},nodiscard "${MDDEVICE}"

	read UUID FS_TYPE < <(blkid -u filesystem ${MDDEVICE}|awk -F "[= ]" '{print $3" "$5}'|tr -d "\"")

	add_to_fstab "${UUID}" "${MOUNTPOINT}"

	mount "${MOUNTPOINT}"
}

check_mdadm() {
    rpm -q mdadm >/dev/null 2>&1
    if [ ${?} -ne 0 ]; then
        (yum -y update || (sleep 15; yum -y update)) > /dev/null
    fi
}

# Create Partitions
DISKS=$(scan_for_new_disks)

if [ "$RAID_CONFIGURATION" -eq 1 ]; then
    check_mdadm
    create_striped_volume "${DISKS[@]}"
else
    scan_partition_format
fi
