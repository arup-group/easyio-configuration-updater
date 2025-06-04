#!/bin/bash
#
# VERSION: 0.1
#
# Configuration report for EasyIO devices.
# This script operates on a project folder of backup files previously created
# using EMS or BatchWorker tools.
#
#

script_name=$(basename "$0")

# Check that commandline arguments are provided
if [[ $# -ne 1 ]]; then
    echo "Usage: $script_name [backup_project_directory]"
    exit 1
fi

# Now, check that the provided directory path exists
backup_directory="$1"
if [[ ! -d $backup_directory ]]; then
    echo "$backup_directory does not exist, quitting."
    exit 1
fi

identify_device_name () {
    # parameter, path to expanded archive
    parameter_file="$1/cpt/plugins/DataServiceConfig/data_mapping.json"
    # find key:value pairs with device_id as key, then filter for the
    # first one (which is the controller name)
    device_name=$(grep -oE '"device_id":"[^"]+"' "$parameter_file" \
        | head -n 1 \
        | sed -E 's/"device_id":"(.*)"/\1/')
}

identify_proxy_device_names () {
    # parameter, path to expanded archive
    parameter_file="$1/cpt/plugins/DataServiceConfig/data_mapping.json"
    # find key:value pairs with name as key, then filter for suitable
    # BDNS type values
    proxy_device_names=$(grep -oE '"device_id":"[^"]+"' "$parameter_file" \
        | tail -n +2 \
        | sed -E 's/"device_id":"([A-Z]+\-[0-9]+)"/\1/' \
        | xargs)
}

identify_kit_names () {
    # parameter, path to expanded archive
    # function converts the front of the file into hexadecimal text representation,
    # removes newlines from the conversion, snips the leading and trailing bytes around
    # the portion of interest, then snips it into sections representing the kit name and
    # checksum for each kit. Run a reverse transformation from hex on the filename
    # portion and concatenate with the hex checksum, sort into alphanumeric order and
    # reformat into a space separated string.
    sedona_app_file="$1/app.sab"
    kit_names=$(head -c 500 "$sedona_app_file" \
        | xxd -p \
        | tr -d '\n' \
        | sed -E 's/.{18}//;s/.{12}61707000.*//;s/00(.{8})/_\1\n/g' \
        | sed -E 's/([^_]+)(.*)/xxd -p -r <<< "\1"; echo \2/e' \
        | sort \
        | xargs)
}



# Iterate through the list of device directories, which are expected in the form of IPv4 addresses, one per device
echo "Processing EasyIO backup files in $backup_directory..."
echo \"ip_address\",\"device_name\",\"proxy_device_names\",\"sedona_kits\"

# Loop through all the device directories in turn and process the backups:
for device_directory in $backup_directory/*; do
    # find just the final part of the path 
    device_directory=$(basename "$device_directory")
    # continue to the next device if there is no device backup directory
    # or it is in the wrong format
    [[ -d "$backup_directory/$device_directory" && \
        "$device_directory" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    # This shell syntax creates a bash parameter array of all the files that match the pattern
    set -- $backup_directory/$device_directory/*.tgz
    # and we collect the name of just the final file in the list, the ! allows indirect variable
    # expansion on the final parameter in the array, whose number is #. The upshot is that we
    # should have selected at this point the most recent backup file if they are named in datetime
    # order.
    latest_backup=$(basename "${!#}") 
    # confirm that the selected file is a regular file, not a link, directory or wildcard
    if [[ -f "$backup_directory/$device_directory/$latest_backup" ]]; then

        # Expand the backup
        tar -xz -C "$backup_directory/$device_directory" \
            -f "$backup_directory/$device_directory/$latest_backup"

        # Find the name of the root directory of the expanded backup
        for file in $backup_directory/$device_directory/*; do 
            # It just grabs the name of the first directory it can find
            [[ -d "$file" ]] && expanded_root_dir=$(basename "$file") && break
        done

        # Show IP address
        echo -n \"$device_directory\",

        # Show device name
        identify_device_name "$backup_directory/$device_directory/$expanded_root_dir"
        echo -n \"$device_name\",

        # Show proxy device names
        identify_proxy_device_names "$backup_directory/$device_directory/$expanded_root_dir"
        echo -n \"$proxy_device_names\",

        # Show kit names and checksums
        identify_kit_names "$backup_directory/$device_directory/$expanded_root_dir"
        echo \"$kit_names\"

        # Delete the expansion
        #    rm -r "$backup_directory/$device_directory/$expanded_root_dir"

    else
        echo "WARNING no backup file found for $backup_directory/$device_directory, skipping!" 1>&2 
    fi     
done


echo "Finished."

