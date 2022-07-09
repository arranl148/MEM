<#
.SYNOPSIS
    Download and Install the Microsoft ConfigMgr 2012 Toolkit R2

.DESCRIPTION
    This script will download and install the Microsoft ConfigMgr 2012 Toolkit R2. 
    The intention was to use the scrtipt for Intune managed devices to easily read log files in the absence of the ConfigMgr client and C:\Windows\CCM\CMTrace.exe

.EXAMPLE
    .\Install-CMTrace.exe

.NOTES
    FileName:    Install-CMTrace.ps1
    Author:      Ben Whitmore
    Date:        9th July 2022
    
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$URL = "https://download.microsoft.com/download/5/0/8/508918E1-3627-4383-B7D8-AA07B3490D21/ConfigMgrTools.msi",
    [Parameter(Mandatory = $false)]
    [string]$DownloadDir = $env:temp,
    [Parameter(Mandatory = $false)]
    [string]$DownloadFileName = "ConfigMgrTools.msi",
    [Parameter(Mandatory = $false)]
    [string]$InstallDest = "C:\Program Files (x86)\ConfigMgr 2012 Toolkit R2\ClientTools\CMTrace.exe"
)

##Set Verbose Level##
$VerbosePreference = "Continue"
#$VerbosePreference = "SilentlyContinue"

Function Get-URLHashInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$URLPath
    )
    $WebClient = [System.Net.WebClient]::new()
    $URLHash = Get-FileHash -Algorithm MD5 -InputStream ($WebClient.OpenRead($URLPath))
    return $URLHash
}

Function Get-FileHashInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )
    $FileHash = Get-FileHash -Algorithm MD5 -Path $FilePath
    return $FileHash
}

Function Test-IsRunningAsAdministrator {
    [CmdletBinding()]param()
    $CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $IsUserAdmin = (New-Object Security.Principal.WindowsPrincipal $CurrentUser).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    Write-Verbose "Current User Is Admin = $IsUserAdmin"
    return $IsUserAdmin
}

Function Get-FileFromInternet {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ $_.StartsWith("https://") })]
        [String]$URL,
        [Parameter(Mandatory = $true)]
        [String]$Destination
    )

    Try {
        $URLRequest = Invoke-WebRequest -UseBasicParsing -URI $URL -ErrorAction SilentlyContinue
        $StatusCode = $URLRequest.StatusCode
    }
    Catch {
        Write-Verbose "It looks like the URL is invalid. Please try again"
        $StatusCode = $_.Exception.Response.StatusCode.value__
    }

    If ($StatusCode -eq 200) {
        Try {
            Invoke-WebRequest -UseBasicParsing -Uri $URL -OutFile $Destination -ErrorAction SilentlyContinue

            If (Test-Path $Destination) {
                Write-Verbose "File download Successfull. File saved to $Destination"
            }
            else {
                Write-Verbose "The download was interrupted or an error occured moving the file to the destination you specified"
                break
            }
        }
        Catch {
            Write-Verbose "Error downloading file: $URL"
            $_
            break
        }
    }
    else {
        Write-Verbose "URL Does not exists or the website is down. Status Code: $($StatusCode)"
        break
    }
}

If (!(Test-IsRunningAsAdministrator)) {
    Write-Verbose "The current User is not an administrator, please run this scrip with administrator credentials"
}
else {

    If (-not(Test-Path -Path $InstallDest)) {

        $FilePath = (Join-Path -Path $DownloadDir -ChildPath $DownloadFileName)

        Get-FileFromInternet -URL $URL -Destination $FilePath

        If (-not (Test-Path -Path $FilePath)) {
            Write-Verbose "There was an error downloading the file to the file system. $($FilePath) does not exist."
            break
        }
        else {
            
            $URLHash = (Get-URLHashInfo -URLPath $URL).hash
            $FileHash = (Get-FileHashInfo -FilePath $FilePath).hash
            Write-Verbose "Checking Hash.."

            If (($URLHash -ne $FileHash) -or ([string]::IsNullOrWhitespace($URLHash)) -or ([string]::IsNullOrWhitespace($FileHash))) {
                Write-Verbose "URL Hash = $($URLHash)"
                Write-Verbose "File Hash = $($FileHash)"
                Write-Verbose "There was an error checking the hash value of the downloaded file. The file hash for ""$($FilePath)"" does not match the hash at ""$($URL)"". Aborting installation"
                break
            }
            else {
                Write-Verbose "Hash match confirmed. Continue installation.."
                Try {
                    $MSIArgs = @(
                        "/i"
                        $FilePath
                        "ADDLOCAL=ClientTools"
                        "/qn"
                    )
                    Start-Process "$env:SystemRoot\System32\msiexec.exe" -args $MSIArgs -Wait -NoNewWindow
                    If (Test-Path -Path $InstallDest) {
                        Write-Verbose "CMTrace installed succesfully at $($InstallDest) "
                    }
                }
                Catch {
                    Write-Verbose "There was an error installing the CMTrace"
                    $_
                }
            }
        }
    }
    else {
        Write-Verbose "CMTrace is already installed at $($InstallDest). Installation will not continue."
    }
}