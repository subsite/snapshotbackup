Snapshot backup script by Fredrik Welander 2013.
--------
http://www.subsite.fi/pages/in-english/subsite.php

This script uses hardlinks to create time freezed incremental backups. It is a reliable solution for automatically 
backing up multiple sources with maximum diskspace and bandwidth efficiency. Run with cron for best result.


**DISCLAIMER:**
This program may not work as espected and it may destroy your data. It may stop working unexpectedly or create useless backups. It may be a security risk.
Read and understand the code, test in a safe environment, check your backups from time to time. USE AT YOUR OWN RISK.

Syntax: 
    **snapshotbackup.bash [--snapshots NUMBER] SOURCE_PATH [SOURCE_PATH ...] DEST_PATH**

Example 1, make snapshots of three directories keeping the default number of copies (SNAPSHOT_COUNT in conf section):
    snapshotbackup.bash backup@client:/etc backup@client:/home/user /mnt/backup_drive

Example 2, make snapshots of /var/www keeping 30 copies:
    snapshotbackup.bash --snapshots 30 /var/www /var/www_backup

Example 3, sample pull backup in /etc/cron.d
    30 1 * * * root /usr/local/sbin/snapshotbackup.bash --snapshots 14 backup@client:/etc backup@client:/home/user /mnt/backup_drive/client/daily

Notes:
- Run as root (with caution) to preserve file ownership and avoid permission errors, but protect your backup drive.
- Use double quotes around source dirs with spaces. Destination path cannot contain spaces.
- Destination path must be local (or locally mounted), source paths can be remote (user@client:/dir/dir) or local
- Backup destination must be a Linux type filesystem, forget FAT/NTFS drives.
- Pull backup with a dedicated backup-user is recommended for security
- Thanks to: http://www.mikerubel.org/computers/rsync_snapshots/

Pull backup setup example:
- Create a dedicated backup user or set a password for user 'backup' if it already exists
- Make sure the backup user can log in using ssh key authentication (do ssh-keygen, ssh-copy-id backup@client, etc)
- You might need to ssh-keygen for root@server and copy to backup@client as well
- Set up the backup command to run in cron (as root)

Tip: Check out my diskspace script on https://github.com/fredrikwelander/misc-scripts and run it on the backup server to get an email if the server is about to run out of space


