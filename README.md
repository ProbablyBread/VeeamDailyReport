# VeeamDailyReport
Generates a Veeam daily backup report for a specified backup window using the Veeam PowerShell cmdlets. 
Mainly to be used for daily checks and record keeping only.
Outputs a CSV file counting the number of successful or failed tasks per backup job as well as the current status on the command line.

**Only tested on Veeam 12.3.2.4465 and 12.3.2.4854.**

# Usage Guide
```powershell
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
    If set to true, replaces the CSV file at the specified -OutputDirectory. Otherwise, appends the results of the current run to the existing CSV file.

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
```
