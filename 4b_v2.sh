#!/bin/bash

# СONSTANTS:
find_mask='*.conf'
mega_config="mega_config.conf"
backup_tar_file="backup.tar.gz"
error_msg="Bad folder of destination. Its content may harm backup process. Please set the another one and rerun 4b_v2.sh"
usage_msg="4_backup_v2 help: default run will backup your configs from /etc into /tmp/backup.\nYou can add 2 arguments /source /destination for changing default paths. Absolute paths only supported"
much_arg_error_msg="Error: too much arguments, -h or --help for help"
single_arg_error_msg="Error: argument in single quantity, -h or --help for help"
unknown_error_msg="Unknown arguments error, -h or --help for help"
email="sysadmin@email.com"

# GATEWAY FOR SCRIPT BODY:
# help menu argument handler
if [[ "$1" = "-h" || "$1" = "--help" ]]; then
    echo -e $usage_msg
    exit 0
# more than 2 argument handler
elif [[ "$#" -gt 2 ]]; then
    echo "$much_arg_error_msg"
    exit 11
# single argument handler
elif [[ "$#" = 1 ]]; then
    echo "$single_arg_error_msg"
    exit 12
# default run argument handler
elif [[ "$#" = 0 ]]; then
    source="/etc/"
    destination="/tmp/backup"
# customized run argument handler
elif [[ -d "$1" ]] && [[ $2 =~ ^\/ ]]; then
    source="$1"
    destination="$2"
# non-existing source path handler
elif ! [[ -d "$1" ]] && [[ "$#" -eq 2 ]]; then
    echo "Error: $1 does not exist"
    exit 13
# some cases stupid human has missed
else
    echo "$unknown_error_msg"
    # its better to escape unpredictable runs
    exit 1
fi

# wrapper for dangerous procedures to avoid hard coding
safe() {
    "$@" 2>>"$tmp_error_file" || exit_if_error
}

# we will receive notifications with cron run only as we don't need to take harassments from every crooked manually run
notify() {
    if [[ -t 0 ]]; then
        cat "$tmp_error_file" | mail -s "unsuccessful run" "$email"
    fi
}

# protection run checker
exit_if_error() {
    if [[ -s "$tmp_error_file" ]]; then
        notify
        cat "$tmp_error_file"
        rm -rf "$tmp_error_file"
        rm -rf "$protected_dir"
        exit 1
    fi
}

# The main idea is to avoid taking neighbour files in the future clean up procedure.
# protection_folder will be located one level deeper than the destination folder thus, we have guaranteed isolated dir
# All the future manipulation will take place into the protection folder
protected_dir="$destination/protection_folder"
tmp_error_file="$destination/ERRORS_OF_4bv2" # its better for tmp file to exist within allocated space

# Temporary error file should not be further archived and should not be created if its already existed in the
# destination argument. Thus we are handling case when "ERRORS_OF_4bv2" file have already exiisted before the run
secure_touch() {
    if ! [[ -f $1 ]]; then
        touch $1
    else
        echo "$error_msg"
        rmdir "$protected_dir"
        exit 20
    fi
}
# handling case when destination argument had a subfolder "protected_dir" before the run
secure_mkdir() {
    if ! [[ -d $1 ]]; then
        mkdir -p $1
    else
        echo "$error_msg"
        exit 20
    fi
}
secure_mkdir "$protected_dir"
secure_touch "$tmp_error_file"

# gathering info about input parameters
source_weight=$(du -d0 "$source" | awk '{ print $1 }')
space_recommended=$(($source_weight*7/10*2)) # best practices
space_needed=$((space_recommended*2)) # considering megaconfig existence 
destination_free=$(df "$destination" | awk '{ print $4 }' | tail -1)

# checking if we have enough space for a backup procedure
if [[ "$space_needed" -gt "$destination_free" ]]; then
    # this that's the real point not relating entry arguments, so we start to track it
    echo "not enough space for backup in: $destination" | tee -a "$tmp_error_file"
    notify
    exit 15
fi

# copying configs to a protected dir
safe rsync -amq --no-links --include="$find_mask" --include='*/' --exclude='*' "$source" "$protected_dir"
# adding backup_ prefix
(find "$protected_dir" -type f | sed 'p;s/\(.*\)\//\1\/backup_/' | xargs -n2 mv) 2>>"$tmp_error_file"
exit_if_error

# building mega config
safe grep -R -Pv '^$|^\s*#' "$protected_dir" > "$destination/$mega_config"
# building archive
safe tar -czpf "$destination/$backup_tar_file" "$protected_dir"

# we dont afraid to clean up
safe rm -rf "$protected_dir" && safe rm -f "$tmp_error_file"
