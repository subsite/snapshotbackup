#!/bin/bash
#
# SnapshotBackup 
# GPL v3. Copyright Fredrik Welander 2013. 
#
#    This program is free software: you can redistribute it and/or modify
#  	 it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# DISCLAIMER: This program may not work as espected and it may destroy your data.
# It may stop working unexpectedly or create useless backups. It may be a security risk.
# Read and understand the code, test in a safe environment, check your backups from time to time.
# USE AT YOUR OWN RISK.
#
# More info in README.md
#
# Syntax:
# snapshotbackup.bash [OPTIONS] SOURCE_PATH [SOURCE_PATH ...] DESTINATION_PATH
#
# Options:
#
# -s, --snapshots NUMBER
#	Number of snapshots to keep
# -r, --rsync-args ARGUMENTS
#	Arguments to rsync (without dash prefix!) e.g. -r rlptD
# -m, --mail-on-complete
#	Send an email on backup completion
# -p, --permissions
#	Backup permissions separately with getfacl
#
# ------- CONF SECTION --------
#
# Default number of snapshots kept when run  
# Override with --snapshots NUMBER (-s NUMBER) argument
#
SNAPSHOT_COUNT=10

# Email address for errors, assign directly or read from file. Comment out either, or both if you don't want any mails.
# Sends the following errors: "Missing destination", "Backup currently running" and "Diskspace warning".
# Depends on mailutils 'mail'
# 
# ERROR_MAIL='john.doe@mail.com'
ERROR_MAIL=`cat /etc/scriptmail.txt`

MAILCOMMAND='/usr/bin/mail -s' 

ERROR_SUBJECT="Error in snapshotbackup"

# Send email when backup completes "yes" or "no"
# Override (set to yes) with --mail-on-complete (-m) argument
#
MAIL_ON_COMPLETE="no"

# Name of small info file created in DEST_PATH after completed backup
#
INFO_FILE="backup_info.txt"

# Include a list of the directories which contain changed files since the last snapshot
#
SHOW_CHANGED_DIRS="yes"

# Arguments to rsync 
# -a equals -rlptgoD. 
# Override with --rsync-args ARGS (-r ARGS) argument (arguments without dash here, eg. --rsync-args rlptD
#
RSYNC_ARGS="-a"

# Backup permissions to separate file, "yes" or "no". This should not be needed on most systems.
# This file may be large and will take up space in each snapshot. 
# This will only work if source is locally mounted and getfacl is installed
#
BACKUP_PERMISSIONS="no"

# Logfile, make sure it's writable by the user running the script
LOGFILE="/var/log/snapshotbackup.log"

# Set error level for less free space on destination than total source size
# "ERROR" aborts the script, "WARNING" only writes log and sends mail
# Note that the backup might still complete if there is enough space for the current snapshot. 
#
SPACE_ERRORLEVEL="WARNING"

#
# ------ END OF CONF SECTION ------



## Main code section
#

# function to write log
function writelog () {
	# usage: writelog "logmessage" [notime]
	if [ "$2" = "notime" ]
	then
		echo "                    $1" >> $LOGFILE
	else
		echo `date "+%Y-%m-%d %H:%M:%S"` "$1" >> $LOGFILE
	fi
}

# function to send email
function mailer () {
	# usage: mailer "mailsubject" "mailmessage"
    if [ -n "$ERROR_MAIL" ]
    then
		HOST=`hostname -f`
		echo "$2" | $MAILCOMMAND "$1 $HOST" "$ERROR_MAIL"
    fi
}

# function to exit on error
function errorexit () {
	# usage: errorexit "errormessage" [mail]
	echo "ERROR $errormessage"
	if [ "$2" = "mail" ]
	then
		mailer "$ERROR_SUBJECT" "$errormessage"
	fi
	writelog "Backup ABORTED with ERROR $errormessage" 
	exit
		
}

# Check basic syntax
if [ $# -lt 2 ]
then
	echo "USAGE: snapshotbackup.bash [OPTIONS] SOURCE_PATH [SOURCE_PATH ...] DESTINATION_PATH"
	exit
fi

started=`date "+%Y-%m-%d %H:%M:%S"`
writelog "LAUNCH" 

# Check and shift arguments
for arg in $@
do
	if [ "${arg:0:1}" = "-" ] ; then
		if [ "$1" = "--snapshots" ] || [ "$1" = "-s" ]; then
			SNAPSHOT_COUNT=$2
			shift
			shift
		elif [ "$1" = "--rsync-args" ] || [ "$1" = "-r" ]; then
			RSYNC_ARGS="-$2"
			shift
			shift
		elif [ "$1" = "--mail-on-complete" ] || [ "$1" = "-m" ]; then
			MAIL_ON_COMPLETE="yes" 
			shift
                elif [ "$1" = "--permissions" ] || [ "$1" = "-p" ]; then
                        BACKUP_PERMISSIONS="yes"
                        shift
		fi
	fi
done


# Get source paths from the arguments that are left
SOURCE_PATHS=""
SOURCE_SIZE="0"
for current_dir in "${@:1:$# - 1}"
do
	remote_prefix=""
	current_dir=${current_dir%/} # Strip tailing slash
	current_dir=${current_dir// /'\ '} # Escape spaces in path
	if [ -d "$current_dir" ]
	then
		# calculate current source size
		cur_size=`du -sk "$current_dir" 2>/dev/null |awk '{print $1}'`
		SOURCE_PATHS="$SOURCE_PATHS $current_dir"
	elif [[ "$current_dir" == *\:* ]]
	then
		SOURCE_PATHS="$SOURCE_PATHS $current_dir"
		remote_host=${current_dir%:*}
		current_path=${current_dir#*:}
		# calculate current source size
		cur_size=`ssh $remote_host du -sk "$current_path" 2>/dev/null |awk '{print $1}'`
		echo "Source \"$current_dir\" is remote"
	else
		echo "WARNING: Source directory \"$current_dir\" not found, directory ignored."
	fi
	
	# calculate total source size
	SOURCE_SIZE=`echo $SOURCE_SIZE + $cur_size | bc`		
done

# make total source size human readable
SOURCE_HUMANSIZE="${SOURCE_SIZE}K"
if [ "$SOURCE_SIZE" -gt 1048576 ]
then
	SOURCE_HUMANSIZE="`echo $SOURCE_SIZE / 1048576 | bc`G"
elif [ "$SOURCE_SIZE" -gt 1024 ]
then
	SOURCE_HUMANSIZE="`echo $SOURCE_SIZE / 1024 | bc`M"
fi
echo "Total size of sources: $SOURCE_HUMANSIZE"

# Get destination from last argument
DEST_PATH=${@:$#}

# Strip tailing slash if there
DEST_PATH=${DEST_PATH%/}

# Make sure destination path exists
if [ ! -d "$DEST_PATH" ]
then
	errormessage="Destination path $DEST_PATH not found. Is it mounted?"
	errorexit "$errormessage" mail
fi

# Make sure destination has enough space
DEST_FREE=`df -kP "$DEST_PATH" |grep "/" |awk '{print $4}'`
DEST_FREE_H=`df -kPh "$DEST_PATH" |grep "/" |awk '{print $4}'`
if [ "$DEST_FREE" -lt "$SOURCE_SIZE" ]
then
	errormessage="Free space on $DEST_PATH is $DEST_FREE_H. Total source size $SOURCE_HUMANSIZE."
	if [ "$SPACE_ERRORLEVEL" = "ERROR" ]
	then
		errorexit "$errormessage" mail
	else
		mailer "WARNING: Insufficient diskspace for snapshotbackup" "$errormessage"
	fi
fi

RUNFILE="SNAPSHOTBACKUP_IS_RUNNING"

if [ -f "$DEST_PATH/$RUNFILE" ];
then
	errormessage="Backup is currently running, start time $(cat $DEST_PATH/$RUNFILE). Runfile is $DEST_PATH/$RUNFILE"
	errorexit "$errormessage" mail
else
	echo `date "+%Y-%m-%d %H:%M:%S"` > $DEST_PATH/$RUNFILE
fi

let backup_zerocount=SNAPSHOT_COUNT-1

# Count current snapshot dirs 
backup_dircount=`ls -1 $DEST_PATH | grep "snapshot." | wc -l`

# Create snapshot dirs if needed
if [ $backup_dircount -lt $backup_zerocount ]
then
	for ((i=0;i<=backup_zerocount;i++)) 
	do
		if [ ! -d "$DEST_PATH/snapshot.$i" ]
		then
			mkdir "$DEST_PATH/snapshot.$i"
		fi
	done
elif [ $backup_dircount -gt $SNAPSHOT_COUNT ]
then
	echo "WARNING: Counted more backup dirs than set number of snapshots. Exceeding dirs left untouched."
fi

# Dir check done, start main tasks
echo -e "Backup started\nSOURCES:$SOURCE_PATHS\nDESTINATION:$DEST_PATH\n$SNAPSHOT_COUNT versions kept"
writelog "Backup STARTED to $DEST_PATH keeping $SNAPSHOT_COUNT snapshots" 
writelog "Sources: $SOURCE_PATHS" notime
writelog "Total source size: $SOURCE_HUMANSIZE, Space on destination: $DEST_FREE_H" notime
if [ "$BACKUP_PERMISSIONS" = "yes" ]
then
	echo "Permissions will be saved to backup_permissions.acl"
fi

# Delete oldest copy
rm -rf $DEST_PATH/snapshot.$backup_zerocount

# Renumber snapshots
for ((  i = backup_zerocount;  i >=1;  i--  ))
do
	let PREV=i-1
	mv $DEST_PATH/snapshot.$PREV $DEST_PATH/snapshot.$i
done

# Rsync source to snapshot.0, creating hardlinks 
#echo "rsync $RSYNC_ARGS --delete --link-dest=../snapshot.1 $SOURCE_PATHS  $DEST_PATH/snapshot.0/"
#
eval rsync $RSYNC_ARGS --delete --link-dest=../snapshot.1 $SOURCE_PATHS  $DEST_PATH/snapshot.0/ 


# Count updated files
FILE_COUNT=`find "$DEST_PATH"/snapshot.0/* -type f -newer "$DEST_PATH"/snapshot.1 -exec ls {} \; | wc -l`
# Write info
echo "Backup started at $started
Backup completed at $(date "+%Y-%m-%d %H:%M:%S")
Backup sources: $SOURCE_PATHS
Total size of sources: $SOURCE_HUMANSIZE, space on destination: $DEST_FREE_H
$FILE_COUNT files updated since last snapshot" > $DEST_PATH/snapshot.0/$INFO_FILE

if [ "$SHOW_CHANGED_DIRS" = "yes" ]
then
	CHANGED_DIRS=`find "$DEST_PATH"/snapshot.0/* -type d -newer "$DEST_PATH"/snapshot.1 -exec ls -d1 {} \;`
	echo -e "\nUpdated files found in the following directories:\n\n$CHANGED_DIRS" >> $DEST_PATH/snapshot.0/$INFO_FILE
fi

# Delete runfile
rm $DEST_PATH/$RUNFILE

# Get and set correct timestamps from $INFO_FILE. 
for ((i=0;i<=backup_zerocount;i++)) 
do
	if [ -e "$DEST_PATH/snapshot.$i/$INFO_FILE" ]
	then
		touch -r "$DEST_PATH/snapshot.$i/$INFO_FILE" "$DEST_PATH/snapshot.$i"
	fi
done

# Save permissions to separate file if SAVE_PERMISSIONS is enabled
#
if [ "$BACKUP_PERMISSIONS" = "yes" ]
then
	# Write permissions to backup_permissions.acl
	eval getfacl -R $SOURCE_PATHS > $DEST_PATH/snapshot.0/backup_permissions.acl
fi

echo "Backup completed."
writelog "Backup to $DEST_PATH COMPLETED $FILE_COUNT files updated."

if [ "$MAIL_ON_COMPLETE" = "yes" ]
then
	completed_info=`cat $DEST_PATH/snapshot.0/$INFO_FILE`
	mailer "SnapshotBackup to $DEST_PATH completed on" "$completed_info"
fi



