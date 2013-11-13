#!/bin/bash
#
# Snapshot backup script by Fredrik Welander 2013. 
# This script uses hardlinks to create time freezed incremental backups. It works in both 
# push and pull modes, but pull is faster and more secure and thus recommended.
# 
# Version 1.0 Jan 2013
# Version 1.1 Feb 2013 (runfile added)
# Version 1.2 Nov 2013 (pull backup)
#
#  DISCLAIMER! 
#    This program may not work as espected and it may destroy your data. 
#    It may destroy other users' data or system files too when run as root.
#    Read and understand the code, test in a safe environment and USE AT YOUR OWN RISK.
#
# Syntax:   snapshotbackup [--snapshots NUMBER] SOURCE_PATHS DEST_PATH
#
# Example 1, make snapshots of three directories keeping the default number of copies (see SNAPSHOT_COUNT below): 
#           snapshotbackup backup@client:/etc backup@client:/home/user /mnt/backup_drive
#
# Example 2, make snapshots of /var/www keeping 30 copies: 
#           snapshotbackup --snapshots 30 /var/www /var/www_backup
#
# Notes:
# - Run as root (with caution) to preserve file ownership and avoid permission errors. 
#    Remember that permission protected files might not be safe on the backup drive
# - Use double quotes around source dirs with spaces. Destination path cannot contain spaces.
# - Destination path must be local (or locally mounted), sorces local or ssh (user@client:/dir/dir)
# - Backup destination must be a Linux type filesystem, forget FAT/NTFS drives.
# - Dependencies: rsync, getfacl
# - Tested on Ubuntu 12.10 with rsync 3.0.9
# - Pull backup with a dedicated backup-user is recommended for security
# - Thanks to: http://www.mikerubel.org/computers/rsync_snapshots/
#
# Pull backup setup example: 
# - Do sudo passwd backup on client 
# - Add /var/backups/.ssh (chowned backup) on client and server
# - As 'backup' on server, do ssh-keygen, ssh-copy-id backup@client
# - Run pull backup as root, source dirs eg. backup@client:/var/www
# - Add backup server to hosts.allow if you get strange errors (denyhosts running?)
#
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
RSYNC_ARGS="-rRlptgoD"

# Backup permissions to separate file, "yes" or "no". This should not be needed on most systems.
# This file may be large and will take up space in each snapshot. 
# This will only work if source is locally mounted.
#
BACKUP_PERMISSIONS="no"

#
# ------ END OF CONF SECTION ------



## Main code section
started=`date "+%d.%m.%Y %H:%M:%S"`

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
   echo "$errormessage" >/dev/stderr		
   if [ -n "$ERROR_MAIL" ]
	echo "$errormessage" | "$MAILCOMMAND" "$ERROR_SUBJECT" "$ERROR_MAIL"
   fi
   exit
else
   echo `date "+%d.%m.%Y %H:%M:%S"` > $DEST_PATH/$RUNFILE
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
eval rsync $RSYNC_ARGS --delete --link-dest=../snapshot.1 $SOURCE_PATHS  $DEST_PATH/snapshot.0/


# Write info
echo "Backup started at $started" > $DEST_PATH/snapshot.0/$INFO_FILE
echo "Backup completed at " `date "+%d.%m.%Y %H:%M:%S"` >> $DEST_PATH/snapshot.0/$INFO_FILE
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
