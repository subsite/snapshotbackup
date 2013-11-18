#!/bin/bash
#
# Snapshot backup script by Fredrik Welander 2013. More info in README.md
# 
# DISCLAIMER: This program may not work as espected and it may destroy your data.
# It may stop working unexpectedly or create useless backups. It may be a security risk.
# Read and understand the code, test in a safe environment, check your backups from time to time.
# USE AT YOUR OWN RISK.
#
# Syntax:
# snapshotbackup.bash [--snapshots NUMBER] SOURCE_PATH [SOURCE_PATH ...] DESTINATION_PATH
#
# ------- CONF SECTION --------
#
# Default number of snapshots kept when run without --snapshots argument.
#
SNAPSHOT_COUNT=10

# Email address for errors, assign directly or read from file. Comment out either, or both if you don't want any mails.
# Depends on mailutils 'mail'
# 
# ERROR_MAIL='john.doe@mail.com'
ERROR_MAIL=`cat /etc/scriptmail.txt`

MAILCOMMAND='/usr/bin/mail -s' 
ERROR_SUBJECT="Error in snapshotbackup"

# Name of small info file created in DEST_PATH after completed backup
#
INFO_FILE="backup_info.txt"

# Arguments to rsync 
# -a equals -rlptgoD. 
#
RSYNC_ARGS="-a"

# Backup permissions to separate file, "yes" or "no". This should not be needed on most systems.
# This file may be large and will take up space in each snapshot. 
# This will only work if source is locally mounted.
#
BACKUP_PERMISSIONS="no"

# Logfile, make sure it's writable by the user running the script
LOGFILE="/var/log/snapshotbackup.log"

#
# ------ END OF CONF SECTION ------



## Main code section
#
started=`date "+%Y-%m-%d %H:%M:%S"`
echo `date "+%Y-%m-%d %H:%M:%S"` "LAUNCH" >> $LOGFILE
# Check arguments
if [ -n "$1" ]
then
	# Check arguments for --snapshots NUMBER
	first_patharg=1
	if [ "$1" = "--snapshots" ]
	then
		SNAPSHOT_COUNT=$2
		first_patharg=3
	fi

	# Get source paths from arguments
	SOURCE_PATHS=""
	for current_dir in "${@:first_patharg:$# - first_patharg}"
	do
		current_dir=${current_dir%/} # Strip tailing slash
		current_dir=${current_dir// /'\ '} # Escape spaces in path
		if [ -d "$current_dir" ]
		then
			SOURCE_PATHS="$SOURCE_PATHS $current_dir"
		elif [[ "$current_dir" == *\:* ]]
		then
			SOURCE_PATHS="$SOURCE_PATHS $current_dir"
			echo "Source \"$current_dir\" is remote."
		else
			echo "WARNING: Source directory \"$current_dir\" not found, directory ignored."
		fi
	done

	# Get destination from last argument
	DEST_PATH=${@:$#}
	# Strip tailing slash if there
	DEST_PATH=${DEST_PATH%/}
fi

# Make sure destination path exists
if [ ! -d "$DEST_PATH" ]
then
	echo "ERROR: Destination path $DEST_PATH not found."
	exit
fi

RUNFILE="SNAPSHOTBACKUP_IS_RUNNING"


if [ -f "$DEST_PATH/$RUNFILE" ];
then
	errormessage="ERROR: Backup is currently running, start time $(cat $DEST_PATH/$RUNFILE)"
	echo `date "+%Y-%m-%d %H:%M:%S"` "$errormessage $DEST_PATH"
	if [ -n "$ERROR_MAIL" ]
	then
		echo "$errormessage" | $MAILCOMMAND "$ERROR_SUBJECT" "$ERROR_MAIL"
	fi
	exit
else
	echo `date "+%Y-%m-%d %H:%M:%S"` > $DEST_PATH/$RUNFILE
fi

## Get source size (1.2 doesn't work with pull)
#source_size=`du -sch $SOURCE_PATHS`

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
echo `date "+%Y-%m-%d %H:%M:%S"` "Backup STARTED SOURCES:$SOURCE_PATHS DESTINATION:$DEST_PATH $SNAPSHOT_COUNT versions kept" >> $LOGFILE
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
echo "rsync $RSYNC_ARGS --delete --link-dest=../snapshot.1 $SOURCE_PATHS  $DEST_PATH/snapshot.0/"
echo `date "+%Y-%m-%d %H:%M:%S"` "rsync $RSYNC_ARGS --delete --link-dest=../snapshot.1 $SOURCE_PATHS  $DEST_PATH/snapshot.0/"
eval rsync $RSYNC_ARGS --delete --link-dest=../snapshot.1 $SOURCE_PATHS  $DEST_PATH/snapshot.0/


# Write info
echo "Backup started at $started" > $DEST_PATH/snapshot.0/$INFO_FILE
echo "Backup completed at " `date "+%Y-%m-%d %H:%M:%S"` >> $DEST_PATH/snapshot.0/$INFO_FILE
echo "Backup Sources: $SOURCE_PATHS" >> $DEST_PATH/snapshot.0/$INFO_FILE
#echo "Size of source dirs:" >> $DEST_PATH/snapshot.0/$INFO_FILE
#echo $source_size >> $DEST_PATH/snapshot.0/$INFO_FILE

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
echo `date "+%Y-%m-%d %H:%M:%S"` "Backup to $DEST_PATH COMPLETED" >> $LOGFILE
