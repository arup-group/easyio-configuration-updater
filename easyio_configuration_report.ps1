# Define the input file name.
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

# Output the final result.
Write-Output `"$result`"


