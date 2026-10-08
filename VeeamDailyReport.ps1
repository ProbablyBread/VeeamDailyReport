<#
.SYNOPSIS
    Generates a Veeam daily backup report. 

.DESCRIPTION
    Generates a Veeam daily backup report for a specified backup window. Mainly to be used for daily checks and record keeping only.
    Outputs a CSV file counting the number of successful or failed tasks per backup job as well as the current status on the command line. 
    
.PARAMETER StartDate
    The start date to start generating reports from. 

    Default: The previous day

.PARAMETER EndDate
    The end date (inclusive) to generate reports until.
    If this parameter is not specified together with -StartDate, the report will only be run for the day specified by the -StartDate parameter. 

    Default: The previous day

.PARAMETER StartWindowHour
    The start hour of the backup window, e.g. 21 = 9pm, 22 = 10pm, 1 = 1am.
    Only accepts integers between 0 and 23.

    Default: 18

.PARAMETER EndWindowHour
    The end hour of the backup window, e.g. 21 = 9pm, 22 = 10pm, 1 = 1am.
    Only accepts integers between 0 and 23.

    Default: 6

.PARAMETER ReplaceOutputFile
    If set to true, replaces the CSV file with the records of only the current run at the specified -OutputDirectory. 
    If set to false, appends the results of the current run to the existing CSV file.

    Default: False

.PARAMETER PrintErrors
    If set to true, prints the Veeam error messages on the console.
    If set to false, suppresses the Veeam error messages on the console.

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
    Generates the report for yesterday between 6pm to 6am, saved to C:\Temp\Veeam Daily Reports\YYYY\MM\yyyyMMdd.csv

.EXAMPLE
    .\VeeamDailyReport.ps1 -StartDate "21 Sep 2026" 
    Generates the report for backups on 21st September 2026 between 6pm and 6am, saved to C:\Temp\Veeam Daily Reports\YYYY\MM\yyyyMMdd.csv

.EXAMPLE
    .\VeeamDailyReport.ps1 -StartDate "21 Sep 2026" -StartWindowHour 10 -EndWindowHour 18
    Generates the report for backups on 21st September 2026 between 10am and 6pm, saved to C:\Temp\Veeam Daily Reports\YYYY\MM\yyyyMMdd.csv

.EXAMPLE
    .\VeeamDailyReport.ps1 -StartWindowHour 10 -EndWindowHour 12 -OutputDirectory "C:\Users\Administrator\Desktop"
    Generates the report for the previous day between 10am and 12pm, saved to C:\Users\Administrator\Desktop\YYYY\MM\yyyyMMdd.csv

.EXAMPLE
    .\VeeamDailyReport.ps1 -StartDate "21 Sep 2026" -EndDate "30 Sep 2026" -StartWindowHour 10 -EndWindowHour 18
    Generates all reports for backups between 21st September 2026 and 30th September 2026 between 10am and 6pm, saved to C:\Temp\Veeam Daily Reports\YYYY\MM\yyyyMMdd.csv
#>

param(
    # default values are defined in the main section for custom error messages 
    [DateTime]$StartDate,
    [DateTime]$EndDate,

    # collect from 6pm to 6am by default 
    [Int]$StartWindowHour = 18,
    [Int]$EndWindowHour = 6,

    [Bool]$ReplaceOutputFile = $false,
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
        ExpectedTasks   = (Get-VBRJobObject -Job $Job).Count # just naively count the number of objects to be backed up
        Session         = $Session # the entire session object
        SessionType     = "None"
        SessionMessages = ""
    }
}

function Get-BackupDetails ([DateTime]$TargetStartDate, [DateTime]$TargetEndDate) {
    $jobDetails = @() # array to hold the return value for this function

    # collect VM and baremetal backup jobs
    # ignore deprecation warning for baremetal jobs for now on Veeam 12
    # TODO: detect and separate this between Veeam 12 and 13
    $jobs = Get-VBRJob -WarningAction SilentlyContinue
    #$baremetalJobs = Get-VBRComputerBackupJob

    # loop through VM jobs and get all sessions in the target window
    foreach ($job in $jobs) {
        if ($job.IsScheduleEnabled -eq $true) {
            # get the latest session only within the specified backup window
            $vmSessions = Get-VBRBackupSession | Where-Object { $_.CreationTime -ge $TargetStartDate -and $_.CreationTime -le $TargetEndDate -and $_.JobId -eq $job.Id }
            $baremetalSessions = Get-VBRComputerBackupJobSession | Where-Object { $_.CreationTime -ge $TargetStartDate -and $_.CreationTime -le $TargetEndDate -and $_.JobId -eq $job.Id }

            if ($vmSessions.Length -gt 0) {
                $latestSession = ($vmSessions | Sort-Object CreationTime -Descending)[0]
                $jobDetails += New-BackupDetailObject -Job $job -Session $latestSession
            }
            elseif ($baremetalSessions.Length -gt 0) {
                $latestSession = ($baremetalSessions | Sort-Object CreationTime -Descending)[0]
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

function Parse-BackupDetails ($BackupDetails) {
    foreach ($backup in $BackupDetails) {
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

    return $BackupDetails
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
                            StartDateTime   = Get-Date $row.StartDateTime -Format "dd MMM yyyy HH:mm:ss" 
                            EndDateTime     = Get-Date $row.EndDateTime -Format "dd MMM yyyy HH:mm:ss"
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
            Select-Object -Property @{Name = "StartDateTime"; Expression = { Get-Date $_.StartDateTime -Format "dd MMM yyyy HH:mm:ss" } }, 
            @{Name = "EndDateTime"; Expression = { Get-Date $_.EndDateTime -Format "dd MMM yyyy HH:mm:ss" } }, 
            JobId, JobName, ExpectedTasks, SuccessTasks, FailedTasks, SessionType, SessionMessages |
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
# terminate on window hours being below 0 or above 23
if ($StartWindowHour -lt 0 -or $StartWindowHour -gt 23) {
    Write-Error "The -StartWindowHour parameter must be greater than 0 and less than 23."
    exit(1)
}
elseif ($EndWindowHour -lt 0 -or $EndWindowHour -gt 23) {
    Write-Error "The -EndWindowHour parameter must be greater than 0 and less than 23."
    exit(1)
}

# terminate if end date is provided without the start date
if ($PSBoundParameters.ContainsKey("EndDate") -and -not $PSBoundParameters.ContainsKey("StartDate")) {
    Write-Error "The -StartDate parameter must be present if the -EndDate parameter is specified."
    exit(1)
}

# if start date is provided 
if ($PSBoundParameters.ContainsKey("StartDate")) {
    try {
        $StartDate = (Get-Date $StartDate).Date.AddHours($StartWindowHour)
    }
    catch [System.Management.Automation.ParameterBindingException] {
        Write-Error "Unable to parse the input string for the -StartDate parameter (valid formats are e.g. 01 Sep 2026 or 2026/09/01)."
        exit(1)
    }
}
# if start date is not provided, default to the previous day
else {
    $StartDate = (Get-Date).Date.AddDays(-1).AddHours($StartWindowHour)
}

# if end date is provided
if ($PSBoundParameters.ContainsKey("EndDate")) {
    try {
        $EndDate = (Get-Date $EndDate).Date.AddHours($EndWindowHour)
    }
    catch [System.Management.Automation.ParameterBindingException] {
        Write-Error "Unable to parse the input string for the -StartDate parameter (valid formats are e.g. 01 Sep 2026 or 2026/09/01)."
        exit(1)
    }
}
# if end date is not provided
else {
    $window = $EndWindowHour - $StartWindowHour

    if ($window -lt 0) {
        $EndDate = $StartDate.Date.AddDays(1).AddHours($EndWindowHour) # rollover to next day
    }
    elseif ($window -gt 0) {
        $EndDate = $StartDate.AddHours($window) # just add the amount of hours
    }
    else {
        $EndDate = $StartDate.AddDays(1) # add 24 hours 
    }
}

$dateDiff = $EndDate - $StartDate

# terminate if end date is earlier than start date
if ($dateDiff.TotalHours -le 0) {
    Write-Error "The -EndDate parameter should be greater than the -StartDate parameter."
    exit(1)
}

# if it's within a 24 hour period
if ($dateDiff.Days -le 1) {
    # just use the params as is
    Write-Host "Processing backups between $($StartDate.ToString('dd MMM yyyy HH:mm:ss')) and $($EndDate.ToString('dd MMM yyyy HH:mm:ss'))..."

    $Jobs = Get-BackupDetails -TargetStartDate $StartDate -TargetEndDate $EndDate
    $BackupDetails = Parse-BackupDetails -BackupDetails $Jobs
    Write-BackupDetailsToFile -BackupDetails $backupDetails -Date $StartDate -Directory $OutputDirectory
}
# if it's more than a single day
else {
    $TargetStartDate = $StartDate # start date always stays the same
    $window = $EndWindowHour - $StartWindowHour

    # if window needs rollover (i.e. passing 12am)
    if ($window -lt 0) {
        $TargetEndDate = $StartDate.Date.AddDays(1).AddHours($EndWindowHour) # rollover to next day
        $EndDate = $EndDate.AddDays(1) # include processing for rollover day
    }
    # if window doesn't need rollover (i.e. within 12am and 11:59pm)
    elseif ($window -gt 0) {
        $TargetEndDate = $StartDate.AddHours($window) # just add the amount of hours
    }
    # if window is exactly 24 hours (e.g. 3pm to 3pm)
    else {
        $TargetEndDate = $StartDate.AddDays(1) # add 24 hours 
    }

    # loop through all days
    while ($TargetStartDate -le $EndDate) {
        Write-Host "Processing backups between $($TargetStartDate.ToString('dd MMM yyyy HH:mm:ss')) and $($TargetEndDate.ToString('dd MMM yyyy HH:mm:ss'))..."

        $Jobs = Get-BackupDetails -TargetStartDate $TargetStartDate -TargetEndDate $TargetEndDate
        $BackupDetails = Parse-BackupDetails -BackupDetails $Jobs
        Write-BackupDetailsToFile -BackupDetails $backupDetails -Date $TargetStartDate -Directory $OutputDirectory

        # use same window, increment days
        $TargetStartDate = $TargetStartDate.AddDays(1)
        $TargetEndDate = $TargetEndDate.AddDays(1)

        Write-Host "`r`n"
    }
}
### MAIN
