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
```
