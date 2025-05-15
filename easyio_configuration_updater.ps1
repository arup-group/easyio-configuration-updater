# VERSION: 0.2
# Key and config rotator for EasyIO devices
# This script loops over a directory of backup files and puts modified backup files
# into an output directory
# TLS KEYS MUST BE GENERATED BEFORE RUNNING THIS SCRIPT

param(
    [string]$BackupProjectDirectory,
    [string]$OutputProjectDirectory,
    [string]$KeysDirectory
)

# Check that all required parameters are provided
if (-not $BackupProjectDirectory -or -not $OutputProjectDirectory -or -not $KeysDirectory) {
    Write-Host "Usage: $($MyInvocation.MyCommand.Name) [backup_project_directory] [output_project_directory] [keys_directory]"
    exit 1
}

# Check that the provided directories exist
foreach ($dir in $BackupProjectDirectory, $OutputProjectDirectory, $KeysDirectory) {
    if (-not (Test-Path -Path $dir -PathType Container)) {
        Write-Host "$dir does not exist, quitting."
        exit 1
    }
}

function Identify-DeviceName {
    param (
        [string]$ExpandedArchivePath
    )
    $ParameterFile = "$ExpandedArchivePath\cpt\plugins\DataServiceConfig\data_mapping.json"

    $DeviceName = (Select-String -Path $ParameterFile -Pattern '"device_id":"[^"]+"' | Select-Object -First 1).Line -replace '"device_id":"(.*)"', '$1'
    return $DeviceName
}

function Update-CloudSettings {
    param (
        [string]$ExpandedBackupRoot,
        [string]$DeviceName
    )

    $ConfigurationPath = "$ExpandedBackupRoot\cpt\plugins\DataServiceConfig"
    $OldFile = "$ConfigurationPath\data_mapping.json"
    $NewFile = "$ConfigurationPath\data_mapping.updated.json"

    (Get-Content $OldFile) -replace '"essential-keep-197822"', '"bos-platform-prod"' `
        -replace '"mqtt.googleapis.com"', '"mqtt.bos.goog"' `
        -replace '"rsa_private[A-Z0-9]*\.pem"', "`"rsa_private$DeviceName.pem`"" `
        -replace '"rsa_public[A-Z0-9]*\.pem"', "`"rsa_public$DeviceName.pem`"" | Set-Content $NewFile
    
    Rename-Item -Path $NewFile -NewName "data_mapping.json"
}

function Update-Keys {
    param (
        [string]$ExpandedBackupRoot,
        [string]$DeviceName
    )

    $KeysPath = "$ExpandedBackupRoot\cpt\plugins\DataServiceConfig\uploads\certs"
    $PrivateKey = "rsa_private$DeviceName.pem"
    $PublicKey = "rsa_public$DeviceName.pem"
    $CAFile = "CA File.pem"

    # Clear old keys
    Remove-Item "$KeysPath\*" -Force -ErrorAction SilentlyContinue

    # Copy new ones
    Copy-Item "$KeysDirectory\$PrivateKey" "$KeysPath\$PrivateKey"
    Copy-Item "$KeysDirectory\$PublicKey" "$KeysPath\$PublicKey"
    Copy-Item "$KeysDirectory\$CAFile" "$KeysPath\$CAFile"
}

Write-Host "Processing EasyIO backup files in $BackupProjectDirectory..."

foreach ($DeviceDirectory in Get-ChildItem -Path $BackupProjectDirectory) {
    if ($DeviceDirectory.PSIsContainer -and $DeviceDirectory.Name -match '^\d+\.\d+\.\d+\.\d+$') {
        $LatestBackup = (Get-ChildItem "$DeviceDirectory\*.tgz" | Sort-Object Name | Select-Object -Last 1).FullName

        if (Test-Path -Path $LatestBackup -PathType Leaf) {
            $OutputDeviceDirectory = "$OutputProjectDirectory\$($DeviceDirectory.Name)"

            if (-not (Test-Path -Path $OutputDeviceDirectory)) {
                New-Item -ItemType Directory -Path $OutputDeviceDirectory
            }

            Expand-Archive -Path $LatestBackup -DestinationPath $OutputDeviceDirectory

            $ExpandedRootDir = Get-ChildItem -Path $OutputDeviceDirectory | Where-Object { $_.PSIsContainer } | Select-Object -First 1

            if ($ExpandedRootDir) {
                $DeviceName = Identify-DeviceName $ExpandedRootDir.FullName
                Update-CloudSettings $ExpandedRootDir.FullName $DeviceName
                Update-Keys $ExpandedRootDir.FullName $DeviceName

                Compress-Archive -Path "$OutputDeviceDirectory\updated_backup" -DestinationPath "$OutputDeviceDirectory\updated_backup.tgz"
                Remove-Item "$OutputDeviceDirectory\updated_backup" -Recurse -Force

                Write-Host "$LatestBackup  ->  $OutputDeviceDirectory\updated_backup.tgz"
            }
        }
        else {
            Write-Host "WARNING: No backup file found for $($DeviceDirectory.Name), skipping!"
        }
    }
}

Write-Host "Finished."


