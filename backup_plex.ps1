# Check if the script is running as an Administrator
If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "This script requires Administrator privileges. Please run it as an Administrator."
    Exit
}

# Define the serial numbers of your drives
$primary12TBSerial = "2E9AC6EE"
$primary14TBSerial = "F0D01657"
$backup12TBSerial = "98A1C76D"
$backup14TBSerial = "FEE05C9F"

# Initialize variables to hold the drive letters
$primary12TBLetter = $null
$primary14TBLetter = $null
$backup12TBLetter = $null
$backup14TBLetter = $null

# Function to get the drive letter from the volume serial number
Function Get-DriveLetterFromVolumeSerial($volumeSerial) {
    $drives = Get-WmiObject Win32_LogicalDisk -Filter "DriveType = 3"
    foreach ($drive in $drives) {
        # Get the volume serial number
        $volSerial = (Get-WmiObject Win32_Volume -Filter "DriveLetter = '$($drive.DeviceID)'").SerialNumber
        # Remove dashes and spaces from the serial number for comparison
        $formattedDecimalSerial = $volSerial -replace "[-\s]"

        # Convert to integer and then to hex
        $intSerial = [long]$formattedDecimalSerial
        $hexSerial = '{0:X}' -f $intSerial        # For debug, echo the drive letter and serial number
        if ($hexSerial -eq $volumeSerial) {
            return $drive.DeviceID
        }
    }
    return $null
}

# Assign drive letters based on volume serial numbers
$primary12TBLetter = Get-DriveLetterFromVolumeSerial $primary12TBSerial
$primary14TBLetter = Get-DriveLetterFromVolumeSerial $primary14TBSerial
$backup12TBLetter = Get-DriveLetterFromVolumeSerial $backup12TBSerial
$backup14TBLetter = Get-DriveLetterFromVolumeSerial $backup14TBSerial

# Verify if all required drive letters are detected
$missingDrives = @()
if (-not $primary12TBLetter) { $missingDrives += "Primary 12TB" }
if (-not $primary14TBLetter) { $missingDrives += "Primary 14TB" }
if (-not $backup12TBLetter) { $missingDrives += "Backup 12TB" }
if (-not $backup14TBLetter) { $missingDrives += "Backup 14TB" }

if ($missingDrives.Count -gt 0) {
    Write-Host "Error: The following drives are missing: $($missingDrives -join ', ')"
    Exit
}

# Echo the detected drive letters
Write-Host "Primary 12TB Drive Letter is ${primary12TBLetter}"
Write-Host "Primary 14TB Drive Letter is ${primary14TBLetter}"
Write-Host "Backup 12TB Drive Letter is ${backup12TBLetter}"
Write-Host "Backup 14TB Drive Letter is ${backup14TBLetter}"

# Function to perform robocopy and return the number of new files copied
Function DoRobocopyAndGetNewFileCount($sourcePath, $destinationPath) {
    $robocopyOut = robocopy $sourcePath $destinationPath /E /ZB /SEC /COPYALL /V /DCOPY:T | Tee-Object -Variable "robocopyOut"
    $newFilesCopied = ($robocopyOut -join "`r`n" | Select-String "New File" | Measure-Object).Count
    return $newFilesCopied
}

Write-Host ""

Write-Host "Backing up Primary 12TB to Backup 12TB..."
$12TbDirsToBackup = @(
    "More Movies",
    "More Movies2",
    "More Movies3",
    "Movies From 4TBPLEX",
    "More TV",
    "Winx Youtube",
    "4k Movies",
    "Personal Picture and Videos",
    "Backups and Old Documents"
)

$12TbCopySummary = @{}

# Loop over the array and perform the backup for each directory
foreach ($dir in $12TbDirsToBackup) {
    $sourcePath = "${primary12TBLetter}$dir"
    $destinationPath = "${backup12TBLetter}$dir"
    $newFilesCopied = DoRobocopyAndGetNewFileCount $sourcePath $destinationPath
    $12TbCopySummary[$dir] = $newFilesCopied
}

Write-Host ""

Write-Host "Backing up Primary 14TB to Backup 14TB..."
$14TbDirsToBackup = @(
    "4k-14TB",
    "Movies-14TB",
    "PlexSettings",
    "prerolls",
    "TV-14TB",
    "Youtube_2"
)

$14TbCopySummary = @{}

# Loop over the array and perform the backup for each directory
foreach ($dir in $14TbDirsToBackup) {
    $sourcePath = "${primary14TBLetter}$dir"
    $destinationPath = "${backup14TBLetter}$dir"
    $newFilesCopied = DoRobocopyAndGetNewFileCount $sourcePath $destinationPath
    $14TbCopySummary[$dir] = $newFilesCopied
}

# Display the summaries of the backup operations
Write-Host ""

Write-Host "12TB Backup Summary:"
Write-Host "---------------------"
foreach ($summary in $12TbCopySummary.GetEnumerator()) {
    Write-Host "$($summary.Key) - $($summary.Value) new files copied"
}

Write-Host ""

Write-Host "14TB Backup Summary:"
Write-Host "---------------------"
foreach ($summary in $14TbCopySummary.GetEnumerator()) {
    Write-Host "$($summary.Key) - $($summary.Value) new files copied"
}


# Function to run chkdsk in read-only mode and return PASS or FAIL
Function DoChkDskReadOnly($driveLetter) {
    $chkdskOutput = chkdsk $driveLetter | Out-String
    if ($chkdskOutput -match "Windows has scanned the file system and found no problems") {
        return "PASS"
    } else {
        return "FAIL"
    }
}
$checkResults = @{}

Write-Host ""
Write-Host "Performing Health Check on Drives..."

# Perform a quick health check on each drive
$checkResults["Primary 12TB ($($primary12TBLetter))"] = DoChkDskReadOnly $primary12TBLetter
$checkResults["Primary 14TB ($($primary14TBLetter))"] = DoChkDskReadOnly $primary14TBLetter
$checkResults["Backup 12TB ($($backup12TBLetter))"] = DoChkDskReadOnly $backup12TBLetter
$checkResults["Backup 14TB ($($backup14TBLetter))"] = DoChkDskReadOnly $backup14TBLetter

# Report the health check results
Write-Host ""

Write-Host "Drive Health Check Results:"
Write-Host "----------------------------"
foreach ($result in $checkResults.GetEnumerator()) {
    Write-Host "$($result.Key) - $($result.Value)"
}

# Function to update the last backup file
Function Update-LastBackupFile($driveLetter) {
    # Define the path for the new last backup file
    $dateString = (Get-Date).ToString("yyyy-MM-dd")
    $newBackupFilePath = "${driveLetter}LastBackup$dateString.txt"

    # Delete old last backup files
    Get-ChildItem -Path "${driveLetter}LastBackup*.txt" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

    # Create new last backup file
    New-Item -Path $newBackupFilePath -ItemType "file" -ErrorAction SilentlyContinue | Out-Null
}

# Update last backup file for each drive
Update-LastBackupFile $primary12TBLetter
Update-LastBackupFile $primary14TBLetter
Update-LastBackupFile $backup12TBLetter
Update-LastBackupFile $backup14TBLetter

Write-Host ""
Write-Host "Backup Complete! LastBackup Filenames Updated on all Drives."
