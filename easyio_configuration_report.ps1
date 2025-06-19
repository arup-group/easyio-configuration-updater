# VERSION: 0.6
# Configuration report for EasyIO devices
# This script loops over a directory of backup files and generates a .CSV file with
# configuration information.
#

param(
    [string]$BackupProjectDirectory
)

# Check that required parameter is provided and it exists
if (-not $BackupProjectDirectory -or -not (Test-Path -Path $BackupProjectDirectory -PathType Container)) {
    Write-Error "Usage: $($MyInvocation.MyCommand.Name) [backup_project_directory]"
    exit 1
}

# Function to identify the device name
function Identify-DeviceName {
    param (
        [string]$ExpandedArchivePath
    )
    $ParameterFile = "$ExpandedArchivePath\cpt\plugins\DataServiceConfig\data_mapping.json"

    $DeviceName = Select-String -Path $ParameterFile -Pattern '"device_id":"([^"]+)"' | % {$_.matches.groups[1].value} | Select-Object -First 1
    return $DeviceName
}

# Function to identify the proxy device names
function Identify-ProxyDeviceNames {
    param (
        [string]$ExpandedArchivePath
    )
    $ParameterFile = "$ExpandedArchivePath\cpt\plugins\DataServiceConfig\data_mapping.json"

    $ProxyDeviceNames = Select-String -Path $ParameterFile -Pattern '"device_id":"([^"]+)"' -AllMatches | ForEach-Object {$_.matches.value | Select-String -Pattern '"device_id":"([^"]+)"' | % {$_.matches.groups[1].value}} | Select-Object -Skip 1 
    return $ProxyDeviceNames
}

function Identify-KitNames {
    # This rather large function is an expansion of a much more compact pipeline of commands
    # in the bash shell version of this script
    # File to analyse
    param(
        [string]$filename
    )

    # Step 1. Read the first 500 bytes from the file.
    # (If the file might be shorter than 500 bytes, this example uses the minimum.)
    $allBytes = [System.IO.File]::ReadAllBytes((Resolve-Path -Path "$filename"))
    $maxIndex = [Math]::Min(499, $allBytes.Length - 1)
    $bytes = $allBytes[0..$maxIndex]

    # Step 2. Convert these bytes to a plain (lowercase) hex string.
    # [BitConverter]::ToString produces hyphen-separated uppercase hex; we remove the hyphens and force lowercase.
    $hexString = ([BitConverter]::ToString($bytes) -replace '-', '').ToLower()

    # Step 3. Remove the first 18 characters (mimics: sed -E 's/.{18}//').
    if ($hexString.Length -ge 18) {
        $hexString = $hexString.Substring(18)
    } else {
        $hexString = ""
    }

    # Step 4. Remove everything from a pattern that starts with any 12 characters,
    # then literal "61707000" and the rest (mimics: sed -E 's/.{12}61707000.*//').
    $hexString = [regex]::Replace($hexString, ".{12}61707000.*", "")

    # Step 5. Replace every instance of "00" followed by exactly 8 characters
    # by an underscore, that 8-character group and a newline (mimics: sed -E 's/00(.{8})/_\1\n/g').
    $hexString = [regex]::Replace($hexString, "00(.{8})", {
        # $args[0] is the current Match object.
        "_" + $args[0].Groups[1].Value + "`n"
    })

    # Now $hexString is a (potentially multi-line) string.
    # Split it into lines (filtering out any empty ones).
    $lines = $hexString -split "`n" | Where-Object { $_ -ne "" }

    # Step 6. Process each line to “execute” the equivalent of:
    # sed -E 's/([^_]+)(.*)/xxd -p -r <<< "\1"; echo \2/e'
    #
    # In each line, we split into:
    #   • a hex part (all characters before the first underscore) and
    #   • the rest (after the underscore).
    #
    # Then we convert the hex part back to its binary (here, we assume ASCII text)
    # using .NET’s FromHexString and append the rest.
    $newLines = foreach ($line in $lines) {
        if ($line -match '^([^_]+)(.*)$') {
            $hexPart = $matches[1]
            $rest = $matches[2]

            try {
                # Convert the hex string to a byte array.
                # $binaryBytes = [Convert]::FromHexString($hexPart)
                $binaryBytes = [byte[]] -split ($hexPart -replace '..', '0x$& ')
                # Convert bytes to text (using ASCII encoding; adjust if needed).
                $convertedText = [System.Text.Encoding]::UTF8.GetString($binaryBytes)
            }
            catch {
                # If conversion fails, default to an empty string.
                $convertedText = ""
            }

            # Concatenate the converted text with the rest of the line.
            $convertedText + $rest
        }
        else {
            # If the line doesn't match the pattern, output it as-is.
            $line
        }
    }

    # Step 7. Sort the processed lines (mimics the pipe to "sort").
    $sortedLines = $newLines | Sort-Object

    # Step 8. Finally, emulate "xargs" (which, without a command, collects and prints the arguments).
    # Here we join the sorted items with a space.
    $result = $sortedLines -join " "

    return $sortedLines
}


Write-Output "Processing EasyIO backup files in $BackupProjectDirectory..."
# Clobber the output file, then append
Write-Host "`"ip_address`",`"device_name`",`"proxy_device_names`",`"sedona_kits`""
Write-Output "`"ip_address`",`"device_name`",`"proxy_device_names`",`"sedona_kits`"" | Out-File -Encoding ascii "$BackupProjectDirectory\audit.csv"

foreach ($DeviceDirectory in Get-ChildItem -Path $BackupProjectDirectory -Directory) {
    if ($DeviceDirectory.Name -match '^\d+\.\d+\.\d+\.\d+$') {

        # Save names of input directory and backup file name, as strings
        $InputDeviceDirectory = "$BackupProjectDirectory\$($DeviceDirectory.Name)"
        $LatestBackup = (Get-ChildItem "$BackupProjectDirectory\$($DeviceDirectory.Name)\*.tgz" | Sort-Object Name | Select-Object -Last 1).Name
        
        # If we've got a valid archive file, then process it
        if (Test-Path -Path "$InputDeviceDirectory\$LatestBackup" -PathType Leaf) {
  
            # Extract the backup
            tar -xz -C $InputDeviceDirectory -f "$InputDeviceDirectory\$LatestBackup"

            # Get the root directory
            $ExpandedRootDir = (Get-ChildItem -Path $InputDeviceDirectory -Directory | Select-Object -First 1).Name

            # Find the device name, proxy device names and kit names
            if ($ExpandedRootDir) {
                $DeviceName = Identify-DeviceName "$InputDeviceDirectory\$ExpandedRootDir"
                $ProxyDeviceNames = Identify-ProxyDeviceNames "$InputDeviceDirectory\$ExpandedRootDir"
                if (-not $DeviceName -or -not $ProxyDeviceNames) {
                    Write-Error "ERROR: Failed to identify device name(s)."
                }

                $KitNames = Identify-KitNames "$InputDeviceDirectory\$ExpandedRootDir\app.sab"
                if (-not $KitNames) {
                    Write-Error "ERROR: Failed to identify Sedona kit name(s)."
                }

                # Output information found for this backup file
                Write-Host "`"$($DeviceDirectory.Name)`",`"$DeviceName`",`"$ProxyDeviceNames`",`"$KitNames`""
                Write-Output "`"$($DeviceDirectory.Name)`",`"$DeviceName`",`"$ProxyDeviceNames`",`"$KitNames`"" | Out-File -Append -Encoding ascii "$BackupProjectDirectory\audit.csv"

                # Delete the expanded directory
                Remove-Item "$InputDeviceDirectory\$ExpandedRootDir" -Recurse -Force

            } else {
                Write-Error "ERROR: Failed to expand or find archive root directory."
            }

        } else {
            Write-Error "WARNING: No backup file found for $DeviceDir, skipping!"
        }
    }
}

Write-Output "Finished."

