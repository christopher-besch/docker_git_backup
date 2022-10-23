#!/bin/bash

###################################
# entry point of docker container #
###################################
set -euo pipefail
IFS=$' \n\t'
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

GIT_BACKUP_DIR="/var/lib/git_backup"
BORG_REPO="$GIT_BACKUP_DIR/repo"
LOG="/origin/git_backup.log"

echo "running git_backup_init.sh"

if [ -z "$(ls -A $BORG_REPO)" ]; then
   echo "$BORG_REPO is empty, creating borg repo"
   borg -r $BORG_REPO rcreate --encryption=none
else
    echo "$BORG_REPO is not empty"
fi

# TODO: allow other git servers
if [ ! -z ${GITHUB_USERNAME+x} ]; then
    cat <<EOF > /root/.git-credentials
https://${GITHUB_USERNAME}:${GITHUB_PASSWORD}@github.com
EOF
fi

echo "init at $(date)" >> $LOG
# call script when receiving SIGHUP
# set -e exits script after trap
set +e
trap 'bash "$GIT_BACKUP_DIR/git_backup.sh" || echo "git_backup.sh failed"' HUP

# await SIGHUP
while :; do
    sleep 10 & wait ${!}
done

