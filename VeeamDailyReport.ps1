<#
.SYNOPSIS
    Generates a Veeam daily backup report. 

.DESCRIPTION
    Generates a Veeam daily backup report for a specified backup window. Mainly to be used for daily checks and record keeping only.
    Outputs a CSV file counting the number of successful or failed tasks per backup job as well as the current status on the command line. 
    
.PARAMETER DaysAgo
    Number of days before to generate the report for, e.g. 0 = today, 1 = yesterday, 2 = 2 days ago.
    Only accepts integers >= 0.

    Default: 1

.PARAMETER StartWindowHour
    The start hour of the backup window, e.g. 21 = 9pm, 22 = 10pm, 1 = 1am.
    Only accepts integers > 0.

    Default: 21

.PARAMETER BackupWindowHours
    The number of hours starting from -StartWindowHour, determines the timeframe to look for backup sessions, e.g. 9 = 9 hours from StartWindowHour
    Only accepts integers > 0.

    Default: 9

.PARAMETER ReplaceOutputFile
    If set to true, replaces the CSV file at the specified -OutputDirectory. Otherwise, appends the reuslts of the current run to the existing CSV file.

    Default: False

.PARAMETER PrintErrors
    If set to true, prints the error messages on the console.

    Default: False

.PARAMETER RunEachDay
    If set to true, runs the report for each day during the specified -StartWindowHour and -BackupWindowHours starting from the specified -DaysAgo parameter.

    Default: False

.PARAMETER OutputDirectory
    The output directory of the CSV file. Subdirectories for year and month will automatically be created under this directory as necessary. 
    CSV files are stored in with the naming convention of yyyyMMdd.csv.
    
    e.g. -OutputDirectory "C:\Veeam"
    
    Resulting directory structure and output file for 21 September 2026 would be:
    C:\Veeam\2026\09\20260921.csv

    Default: "C:\Temp\Veeam Daily Reports"

.EXAMPLE
    .\VeeamDailyReport.ps1
    Generates the report for yesterday between 9pm to 6am, saved to C:\Temp\Veeam Daily Reports\YYYY\MM\yyyyMMdd.csv

.EXAMPLE
    .\VeeamDailyReport.ps1 -DaysAgo 2
    Generates the report for backups 2 days ago between 9pm to 6am, saved to C:\Temp\Veeam Daily Reports\YYYY\MM\yyyyMMdd.csv

.EXAMPLE
    .\VeeamDailyReport.ps1 -DaysAgo 0 -StartWindowHour 10 -BackupWindowHours 4
    Generates the report for backups today between 10am to 2pm, saved to C:\Temp\Veeam Daily Reports\YYYY\MM\yyyyMMdd.csv

.EXAMPLE
    .\VeeamDailyReport.ps1 -StartWindowHour 10 -BackupWindowHours 2 -OutputDirectory "C:\Users\Administrator\Desktop"
    Generates the report for yesterday between 10am to 12pm, saved to C:\Users\Administrator\Desktop\YYYY\MM\yyyyMMdd.csv

.EXAMPLE
    .\VeeamDailyReport.ps1 -DaysAgo 0 -StartWindowHour 10 -BackupWindowHours 4 -ReplaceOutputFile
    Generates the report for backups today between 10am to 2pm, saved to C:\Temp\Veeam Daily Reports\YYYY\MM\yyyyMMdd.csv
    Replaces C:\Temp\Veeam Daily Reports\YYYY\MM\yyyyMMdd.csv if it exists.
#>

param(
    [Int]$DaysAgo = 1, 

    [Int]$StartWindowHour = 21, 

    [Int]$BackupWindowHours = 9, 

    [Bool]$ReplaceOutputFile = $false,

    [Bool]$RunEachDay = $false, 

    [Bool]$PrintErrors = $false,

    [String]$OutputDirectory = "C:\Temp\Veeam Daily Reports" 
)

function New-BackupDetailObject ($Job, $Session) {
    # creates a new struct storing job details
    return [PSCustomObject]@{
        StartDateTime   = $Session.CreationTime
        EndDateTime     = $Session.EndTime
        JobId           = $Job.Id # Job GUID
        JobName         = $Job.Name # Job name
        SuccessTasks    = 0
        FailedTasks     = 0
        ExpectedTasks   = ($Job | Get-VBRJobObject).Count # just naively count the number of objects to be backed up
        Session         = $Session # the entire session object
        SessionType     = "None"
        SessionMessages = ""
    }
}
    
function Get-BackupDetails ([DateTime]$TargetStartDate, [DateTime]$TargetEndDate) {
    $jobDetails = @() # array to hold the return value for this function

    # collect VM and baremetal backup jobs
    $vmJobs = Get-VBRJob -WarningAction SilentlyContinue 

    # loop through VM jobs and get all sessions in the target window
    foreach ($job in $vmJobs) {
        if ($job.IsScheduleEnabled -eq $true) {
            # get the latest session only within the specified backup window
            $hvSessions = Get-VBRBackupSession | Where-Object { $_.CreationTime -ge $TargetStartDate -and $_.CreationTime -le $TargetEndDate -and $_.JobId -eq $job.Id }
            $agentSessions = Get-VBRComputerBackupJobSession | Where-Object { $_.CreationTime -ge $TargetStartDate -and $_.CreationTime -le $TargetEndDate -and $_.JobId -eq $job.Id } 

            if ($hvSessions.Length -gt 0) {
                $latestSession = ($hvSessions | Sort-Object CreationTime -Descending)[0]
                $jobDetails += New-BackupDetailObject -Job $job -Session $latestSession
            }
            elseif ($agentSessions.Length -gt 0) {
                $latestSession = ($agentSessions | Sort-Object CreationTime -Descending)[0]
                $jobDetails += New-BackupDetailObject -Job $job -Session $latestSession
            }
        }
    }

    return $jobDetails
}

function Get-SessionMessages ($Tasks) {
    $messages = @()

    foreach ($task in $Tasks) {
        if ($task.Status -eq "Warning" -or $task.Status -eq "Failed") {
            $message = "[" + $task.Status.ToString().ToUpper() + "] " + $task.Name + ": " + $task.GetDetails()
            $message = $message -replace "<br />", "; " # replace any html line breaks with ; 
            $message = $message -join " " # join broken messages 
            $messages += $message # add to overall messages array
        }
    }

    return $messages -join "`r`n"
}

function Get-SessionType ([String]$Type) {
    switch ($Type) {
        "Increment" {
            return "Incremental"
        }
        # NOTE: this is an actual misspelling from Veeam, DO NOT CORRECT
        "SynteticFull" {
            return "SyntheticFull"
        }
        "Full" {
            return "ActiveFull"
        }
        default {
            return "Unknown"
        }
    }
}

function Parse-BackupDetails {
    $backupDetails = Get-BackupDetails -TargetStartDate $TargetStartDate -TargetEndDate $TargetEndDate

    foreach ($backup in $backupDetails) {
        if ($backup.Session.Length -gt 0) {
            $tasks = Get-VBRTaskSession -Session $backup.Session.Id # get tasks for latest session
            $backup.SessionType = Get-SessionType -Type $tasks[0].JobSess.SessionInfo.SessionAlgorithm # get session type based on one task 

            switch ($backup.Session.Result.ToString()) {
                "Failed" {
                    Write-Host "$($backup.JobName): FAILED" -BackgroundColor Red -ForegroundColor White
                    $backup.FailedTasks = ($tasks | Where-Object { $_.Status -eq "Failed" }).Length
                    $backup.SuccessTasks = $backup.ExpectedTasks - $backup.FailedTasks
                    $backup.SessionMessages = Get-SessionMessages $tasks
                    
                    if ($PrintErrors -eq $true) {
                        Write-Host "$($backup.SessionMessages)"
                    }

                    break
                }
                "Warning" {
                    Write-Host "$($backup.JobName): WARNING" -BackgroundColor Yellow -ForegroundColor Black
                    $backup.SuccessTasks = $backup.ExpectedTasks
                    $backup.SessionMessages = Get-SessionMessages $tasks

                    if ($PrintErrors -eq $true) {
                        Write-Host "$($backup.SessionMessages)"
                    }

                    break
                }
                "Success" {
                    Write-Host "$($backup.JobName): SUCCESS" -BackgroundColor Green -ForegroundColor Black
                    $backup.SuccessTasks = $backup.ExpectedTasks
                    break
                }
                "None" {
                    Write-Host "$($backup.JobName): IN PROGRESS (Started: $($backup.Session.CreationTime))" -BackgroundColor Yellow -ForegroundColor Black
                    break
                }
                default {
                    Write-Error "Unhandled exception - you shouldn't be here. If you see this message, this script needs to be modified."
                    exit(1)
                }
            } 
        }
        # failsafe for jobs that did not run at all
        # this shouldn't really happen 
        else {
            Write-Host "$($backup.JobName): NO RUNS BETWEEN $TargetStartDate AND $TargetEndDate" -BackgroundColor Red -ForegroundColor White
        }
    }

    return $backupDetails
}

function Write-BackupDetailsToFile ($BackupDetails, $Date, $Directory) {
    $outputDate = Get-Date $Date -Format "yyyyMMdd"
    $outputDir = "$Directory\$($Date.Year)\$("{0:D2}" -f $Date.Month)"
    $outputFile = "$outputDir\$outputDate.csv"
    $missingFlag = $false

    # failsafe, these generally shouldn't happen
    if ($BackupDetails -eq $null) {
        $missingFlag = $true
    }
    elseif ($BackupDetails.GetType().BaseType.Name -eq "Array" -and $BackupDetails.Length -le 0) {
        $missingFlag = $true
    }
    elseif ($BackupDetails.GetType().BaseType.Name -eq "Object" -and $BackupDetails.Session -eq $null) {
        $missingFlag = $true
    }

    if ($missingFlag) {
        Write-Host "No backup sessions found for $outputDate." -BackgroundColor Red -ForegroundColor Black
    }
    else {
        # create destination folder if it doesn't exist
        if (-not(Get-Item "$outputDir" -ErrorAction SilentlyContinue)) {
            New-Item -ItemType Directory -Path "$outputDir" | Out-Null
        }
        
        # check if file already exists
        if (Get-Item "$outputFile" -ErrorAction SilentlyContinue) {
            # append lines if $ReplaceOutputFile param is not defined
            if (-not $ReplaceOutputFile) {
                $csv = Import-Csv "$outputFile"

                # loop through each item from existing CSV
                foreach ($row in $csv) {
                    # if item is not in the latest run
                    if ($row.JobId -notin $BackupDetails.JobId) {
                        # minimal struct to append to $BackupDetails
                        $BackupDetails += [PSCustomObject]@{
                            StartDateTime   = Get-Date $row.StartDateTime 
                            EndDateTime     = Get-Date $row.EndDateTime
                            JobId           = $row.JobId
                            JobName         = $row.JobName
                            ExpectedTasks   = $row.ExpectedTasks
                            SuccessTasks    = $row.SuccessTasks
                            FailedTasks     = $row.FailedTasks
                            SessionType     = $row.SessionType
                            SessionMessages = $row.SessionMessages
                        }
                    }
                }
            }

            # delete the existing file 
            Remove-Item -Force $outputFile -ErrorAction SilentlyContinue | Out-Null
        }

        try {
            $BackupDetails | 
            Select-Object -Property StartDateTime, EndDateTime, JobId, JobName, ExpectedTasks, SuccessTasks, FailedTasks, SessionType, SessionMessages |
            Export-Csv $outputFile -Force -NoTypeInformation

            Write-Host "Data written to $($outputFile)."
        } 
        catch {
            Write-Error "Unable to write to $($outputFile)."
            exit(1) 
        }
    }
}

### MAIN
if ($DaysAgo -lt 0) {
    Write-Error "The -DaysAgo parameter must be greater than or equals to 0."
    exit(1)
}
elseif ($StartWindowHour -le 0) {
    Write-Error "The -StartWindowHour parameter must be greater than 0."
    exit(1)
}
elseif ($BackupWindowHours -le 0) {
    Write-Error "The -BackupWindowHours parameter must be greater than 0."
    exit(1)
}
else {
    $TargetStartDate = (Get-Date).Date.AddDays(-$DaysAgo).AddHours($StartWindowHour)
    $TargetEndDate = $TargetStartDate.AddHours($BackupWindowHours)
}

if ($RunEachDay -eq $true) {
    # loop through all dates up till yesterday
    while ($TargetStartDate.Date -lt $(Get-Date).Date) {
        Write-Host "Processing backups between $TargetStartDate and $TargetEndDate..."
        $backupDetails = Parse-BackupDetails
        Write-BackupDetailsToFile -BackupDetails $backupDetails -Date $TargetStartDate -Directory $OutputDirectory

        # update start and end dates, reuse same window
        $TargetStartDate = $TargetStartDate.AddDays(1)
        $TargetEndDate = $TargetEndDate.AddDays(1)

        Write-Host "`r`n" # formatting
    }
}
else {
    Write-Host "Processing backups between $TargetStartDate and $TargetEndDate..."
    $backupDetails = Parse-BackupDetails
    Write-BackupDetailsToFile -BackupDetails $backupDetails -Date $TargetStartDate -Directory $OutputDirectory
}
### MAIN
