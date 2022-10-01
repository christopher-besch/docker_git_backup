#!/bin/bash

##############################################
# to be run every time a backup gets created #
##############################################
set -euo pipefail
IFS=$' \n\t'
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

GIT_BACKUP_DIR="/var/lib/git_backup"
TEMP_DIR="/origin"
BORG_REPO="$GIT_BACKUP_DIR/repo"
CONFIGS_DIR="$GIT_BACKUP_DIR/configs"
# used to clone repos into ->
# makes time where the actual repo target dir is present but not properly cloned yet as short as possible ->
# crashes don't create zombie dirs that can't be git pulled or cloned
CLONE_TARGET="$TEMP_DIR/clone_target"
LOG="$TEMP_DIR/git_backup.log"

clone_repo() {
    echo "cloning $1"
    rm -rf $CLONE_TARGET

    if git clone "https://$1" $CLONE_TARGET --recurse; then
        REPO_DIR="$TEMP_DIR/$1"
        mkdir -p $REPO_DIR
        mv -T $CLONE_TARGET $REPO_DIR
        echo "cloned $1" >> $LOG
    else
        echo "Error: failed to clone $1"
        echo "error cloning $1" >> $LOG
    fi
}
pull_repo() {
    echo "pulling $1 if required"
    pushd "$TEMP_DIR/$1" >/dev/null

    if ! git remote update; then
        echo "error fetching upstream of $1" >> $LOG
    fi
    # check if pull is actually necessary -> cleaner logs
    if git status -uno | grep -P '^Your branch is behind '; then
        echo "pulling $1"
        if git pull --all; then
            echo "pulled $1" >> $LOG
        else
            echo "Error: failed to pull $1"
            echo "error pulling $1" >> $LOG
        fi
    else
        echo "pull not required"
    fi

    popd >/dev/null
}
backup_repo() {
    if [ -d "$TEMP_DIR/$1" ]; then
        pull_repo $1
    else
        clone_repo $1
    fi
}

# write all to be backed up repos to file in $TEMP_DIR
get_all_repos() {
    # cleanup
    echo '' > $TEMP_DIR/all_repos.conf
    # only load other repos when other_repos.conf exists
    if [ -f $GIT_BACKUP_DIR/other_repos.conf ]; then
        cat $GIT_BACKUP_DIR/other_repos.conf >> $TEMP_DIR/all_repos.conf
    fi
    # only load all repos when GITHUB_USERNAME given
    if [ ! -z ${GITHUB_USERNAME+x} ]; then
        python3 $GIT_BACKUP_DIR/get_repos.py >> $TEMP_DIR/all_repos.conf
    fi
}

backup_all_repos() {
    echo "starting backup at $(date)" >> $LOG

    get_all_repos
    while IFS="" read -r CUR_DIR || [ -n "$CUR_DIR" ]; do
        # only lines with content
        if [ -n "$CUR_DIR" ]; then
            backup_repo $CUR_DIR
        fi
    done < $TEMP_DIR/all_repos.conf
    echo "backup complete at $(date)" >> $LOG
}

create_borg_backup() {
    echo checking
    borg -r $BORG_REPO check
    echo "checking done"

    export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes
    if ! borg -r $BORG_REPO check; then
        echo "borg backup repo invalid" >> $LOG
        return
    fi
    echo >> $LOG

    echo "creating borg backup"
    borg -r $BORG_REPO create --compression $BORG_COMPRESSION "git_backup_{now}" $TEMP_DIR

    if [ ! -z ${PRUNE_CFG+x} ]; then
        echo "running: borg -r $BORG_REPO prune $PRUNE_CFG"
        borg -r $BORG_REPO prune $PRUNE_CFG
    else
        echo "PRUNE_CFG not defined"
    fi

    echo "compacting borg repo"
    borg -r $BORG_REPO compact
}

echo "running git_backup.sh"

backup_all_repos
create_borg_backup

echo "all done"
echo

