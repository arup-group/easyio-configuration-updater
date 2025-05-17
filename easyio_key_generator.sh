#!/bin/bash
#
# VERSION: 0.1
#
# Key generator for EasyIO devices
# This script loops over a directory of backup files and generates keys that are
# named according to the cloud name for the publishing device
#


script_name=$(basename "$0")

# Check that commandline arguments are provided
if [[ $# -ne 2 ]]; then
    echo "Usage: $script_name [backup_project_directory] [keys_directory]"
    exit 1
fi

# Now, check that the provided directory paths all exist
for dir in "$@"; do
    if [[ ! -d $dir ]]; then
        echo "$dir does not exist, quitting."
        exit 1
    fi
done

backup_directory="$1"
keys_directory="$2"

# Check that the keys directory is empty, or only has a CA file in it. This
# is to avoid existing keys from being overwritten by accident.
for file in $keys_directory/*; do 
    if [[ -f $file ]] && ! [[ $file =~ CA.* ]]; then
        echo "STOP: keys directory already has keys in it." 1>&2
        exit 1
    fi
done

identify_device_name () {
    # parameter, path to expanded archive
    parameter_file="$1/cpt/plugins/DataServiceConfig/data_mapping.json"
    # find key:value pairs with device_id as key, then filter for the
    # first one (which is the controller name)
    device_name=$(grep -oE '"device_id":"[^"]+"' "$parameter_file" \
        | head -n 1 \
        | sed -E 's/"device_id":"(.*)"/\1/')
}


generate_key () {
    # parameters: path to keys directory, BOS name of controller device
    # function returns 0 on success
    keys_directory="$1"
    private_key="rsa_private$2.pem"
    public_key="rsa_public$2.pem"
    ssh-keygen -b 2048 -t rsa-sha2-256 -f newkey -q -N "" \
        && mv newkey "$keys_directory/$private_key" \
        && mv newkey.pub "$keys_directory/$public_key" \
        || echo "ERROR: Failed to generate new key for $1." 1>&2
}


# Iterate through the list of device directories, which are expected in the form of IPv4 addresses, one per device
echo "Processing EasyIO backup files in $backup_directory..."

# Loop through all the device directories in turn and process the backups:
# a corresponding device directory is created in the output directory with
# modified backup files
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

        # Identify the controller name and then make new key pair
        identify_device_name "$backup_directory/$device_directory/$expanded_root_dir" \
            && generate_key "$keys_directory" "$device_name" \
            || (echo "ERROR: Failed to generate key." && continue)

        # Delete the expansion
            rm -r "$backup_directory/$device_directory/$expanded_root_dir"

        echo "$backup_directory/$device_directory/$latest_backup  -> " \
             "$device_name key pair made."
    else
        echo "WARNING no backup file found for $backup_directory/$device_directory, skipping!" 1>&2 
    fi     
done


echo "Finished."

