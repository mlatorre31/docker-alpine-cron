# docker-alpine-cron

Dockerfile and scripts for creating image with Cron based on Alpine  
Installed packages: dcron wget rsync ca-certificates  

#### Environment variables:

CRON_STRINGS - strings with cron jobs. Use "\n" for newline (Default: undefined)   
CRON_TAIL - if defined cron log file will read to *stdout* by *tail* (Default: undefined)   
By default cron running in foreground  

#### Cron files
- /etc/cron.d - place to mount custom crontab files  

When image will run, files in */etc/cron.d* will copied to */var/spool/cron/crontabs*.
If *CRON_STRINGS* defined script creates file */var/spool/cron/crontabs/CRON_STRINGS*

A background sync runs immediately at startup and every 60 seconds. Adds and edits in
*/etc/cron.d* apply to the running dcron within about 2 minutes; deletions stop the
corresponding jobs within the same interval. The environment-generated *CRON_STRINGS*
job is preserved during these changes.

dcron ignores filenames containing a dot, so use only letters, digits, underscores and
hyphens for schedulable job names. Files whose names begin with a dot are never managed
by the sync loop. Other dotted names are copied but are not scheduled or sent to dcron
as reload notifications. Spool files must be owned by root (uid 0) or dcron silently
ignores them; the sync loop writes root-owned files with mode 0644.

The names *cron.update* and *CRON_STRINGS* are reserved. The sync loop never manages,
overwrites or deletes spool files with those names, regardless of files with the same
names in */etc/cron.d*.

#### Log files
Log file by default placed in /var/log/cron/cron.log 

#### Simple usage:
```
docker run --name="alpine-cron-sample" -d \
-v /path/to/app/conf/crontabs:/etc/cron.d \
-v /path/to/app/scripts:/scripts \
xordiv/docker-alpine-cron
```

#### With scripts and CRON_STRINGS
```
docker run --name="alpine-cron-sample" -d \
-e 'CRON_STRINGS=* * * * * /scripts/myapp-script.sh'
-v /path/to/app/scripts:/scripts \
xordiv/docker-alpine-cron
```

#### Get URL by cron every minute
```
docker run --name="alpine-cron-sample" -d \
-e 'CRON_STRINGS=* * * * * wget --spider https://sample.dockerhost/cron-jobs'
xordiv/docker-alpine-cron
```
