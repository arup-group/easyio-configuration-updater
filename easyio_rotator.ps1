# VERSION: 0.11 FOR TESTING!
#
# Key and config rotator for EasyIO devices
# This script loops over a directory of backup files and puts modified backup files
# into an output directory
#
# Example invocation:
# .\easyio_rotator.ps1 -InputDirectory backups -OutputDirectory outputs -KeysDirectory new_keys

param (
    [string]$InputDirectory,
    [string]$OutputDirectory,
    [string]$KeysDirectory
)

# Check that commandline arguments are provided
if (-not $InputDirectory -or -not $OutputDirectory -or -not $KeysDirectory) {
    Write-Host "Usage: easyio_rotator.ps1 -InputDirectory [input_directory] -OutputDirectory [output_directory] -KeysDirectory [keys_directory]"
    exit 1
}

# Now, check that the provided directory paths all exist
foreach ($dir in $InputDirectory, $OutputDirectory, $KeysDirectory) {
    if (-not (Test-Path -Path $dir -PathType Container)) {
        Write-Host "$dir does not exist, quitting."
        exit 1
    }
}

# NB In the keys_directory, there should be rsa_public.pem, rsa_private.pem and 'CA File.pem'. We use the same keys for all devices.
$backupDirectory = $InputDirectory
$outputDirectory = $OutputDirectory
$keysDirectory = $KeysDirectory

Write-Host "Processing EasyIO backup files in $backupDirectory..."

Get-ChildItem -Path "$backupDirectory\*tgz" | ForEach-Object {
    $backupPath = $_.FullName

    # Unzip the backup
    tar -xf $backupPath

    # Get the root directory of the expanded archive
    $backupFile = $_.Name
    if ($backupFile -match '[FW|FS]-([0-9]+_backup)s*.tgz') {
        $expandedRootDir = $matches[1]
    }
    $keyDestination = "$expandedRootDir\cpt\plugins\DataServiceConfig\uploads\certs"
    $configDestination = "$expandedRootDir\cpt\plugins\DataServiceConfig"

    # Update the config file
    Move-Item -Path "$configDestination\data_mapping.json" -Destination "$configDestination\data_mapping.old.json"
    (Get-Content -Path "$configDestination\data_mapping.old.json") -replace '"essential-keep-197822"', '"bos-platform-prod"' -replace '"mqtt.googleapis.com"', '"mqtt.bos.goog"' -replace '"rsa_(private|public)[A-Z0-9]*\.pem"', '"rsa_$1.pem"' | Set-Content -Path "$configDestination\data_mapping.json"
    Remove-Item -Path "$configDestination\data_mapping.old.json"

    # Update the certificate, private key and CA file
    Remove-Item -Path "$keyDestination\*"
    Get-ChildItem -Path "$keysDirectory\*" | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $keyDestination
    }

    # Make a new tar file ready for restore, then get rid of working directory
    tar -cf "$outputDirectory\$backupFile" -C $expandedRootDir .
    Remove-Item -Recurse -Force -Path $expandedRootDir

    Write-Host "$backupPath --> $outputDirectory\$backupFile"
}

Write-Host "Finished."



