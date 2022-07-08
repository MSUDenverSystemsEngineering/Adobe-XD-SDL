﻿<#
.SYNOPSIS
	This script performs the installation or uninstallation of an application(s).
	# LICENSE #
	PowerShell App Deployment Toolkit - Provides a set of functions to perform common application deployment tasks on Windows.
	Copyright (C) 2017 - Sean Lillis, Dan Cunningham, Muhammad Mashwani, Aman Motazedian.
	This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or any later version. This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
	You should have received a copy of the GNU Lesser General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.
.DESCRIPTION
	The script is provided as a template to perform an install or uninstall of an application(s).
	The script either performs an "Install" deployment type or an "Uninstall" deployment type.
	The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.
	The script dot-sources the AppDeployToolkitMain.ps1 script which contains the logic and functions required to install or uninstall an application.
.PARAMETER DeploymentType
	The type of deployment to perform. Default is: Install.
.PARAMETER DeployMode
	Specifies whether the installation should be run in Interactive, Silent, or NonInteractive mode. Default is: Interactive. Options: Interactive = Shows dialogs, Silent = No dialogs, NonInteractive = Very silent, i.e. no blocking apps. NonInteractive mode is automatically set if it is detected that the process is not user interactive.
.PARAMETER AllowRebootPassThru
	Allows the 3010 return code (requires restart) to be passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.
.PARAMETER TerminalServerMode
	Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Destkop Session Hosts/Citrix servers.
.PARAMETER DisableLogging
	Disables logging to file for the script. Default is: $false.
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeployMode 'Silent'; Exit $LastExitCode }"
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -AllowRebootPassThru; Exit $LastExitCode }"
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeploymentType 'Uninstall'; Exit $LastExitCode }"
.EXAMPLE
    Deploy-Application.exe -DeploymentType "Install" -DeployMode "Silent"
.NOTES
	Toolkit Exit Code Ranges:
	60000 - 68999: Reserved for built-in exit codes in Deploy-Application.ps1, Deploy-Application.exe, and AppDeployToolkitMain.ps1
	69000 - 69999: Recommended for user customized exit codes in Deploy-Application.ps1
	70000 - 79999: Recommended for user customized exit codes in AppDeployToolkitExtensions.ps1
.LINK
	http://psappdeploytoolkit.com
#>

## Suppress PSScriptAnalyzer errors for not using declared variables during AppVeyor build
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "", Justification="Suppress AppVeyor errors on unused variables below")]

[CmdletBinding()]
Param (
	[Parameter(Mandatory=$false)]
	[ValidateSet('Install','Uninstall','Repair')]
	[string]$DeploymentType = 'Install',
	[Parameter(Mandatory=$false)]
	[ValidateSet('Interactive','Silent','NonInteractive')]
	[string]$DeployMode = 'Interactive',
	[Parameter(Mandatory=$false)]
	[switch]$AllowRebootPassThru = $false,
	[Parameter(Mandatory=$false)]
	[switch]$TerminalServerMode = $false,
	[Parameter(Mandatory=$false)]
	[switch]$DisableLogging = $false
)

Try {
	## Set the script execution policy for this process
	Try { Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop' } Catch { Write-Error "Failed to set the execution policy to Bypass for this process." }

	##*===============================================
	##* VARIABLE DECLARATION
	##*===============================================
	## Variables: Application
	[string]$appVendor = 'Adobe'
	[string]$appName = 'XD'
	[string]$appVersion = '51.0.12'
	[string]$appArch = 'x64'
	[string]$appLang = 'EN'
	[string]$appRevision = '01'
	[string]$appScriptVersion = '1.0.0'
	[string]$appScriptDate = '07/06/2022'
	[string]$appScriptAuthor = 'Craig Myers'
	##*===============================================
	## Variables: Install Titles (Only set here to override defaults set by the toolkit)
	[string]$installName = ''
	[string]$installTitle = ''

	##* Do not modify section below
	#region DoNotModify

	## Variables: Exit Code
	[int32]$mainExitCode = 0

	## Variables: Script
	[string]$deployAppScriptFriendlyName = 'Deploy Application'
	[version]$deployAppScriptVersion = [version]'3.8.4'
	[string]$deployAppScriptDate = '26/01/2021'
	[hashtable]$deployAppScriptParameters = $psBoundParameters

	## Variables: Environment
	If (Test-Path -LiteralPath 'variable:HostInvocation') { $InvocationInfo = $HostInvocation } Else { $InvocationInfo = $MyInvocation }
	[string]$scriptDirectory = Split-Path -Path $InvocationInfo.MyCommand.Definition -Parent

	## Dot source the required App Deploy Toolkit Functions
	Try {
		[string]$moduleAppDeployToolkitMain = "$scriptDirectory\AppDeployToolkit\AppDeployToolkitMain.ps1"
		If (-not (Test-Path -LiteralPath $moduleAppDeployToolkitMain -PathType 'Leaf')) { Throw "Module does not exist at the specified location [$moduleAppDeployToolkitMain]." }
		If ($DisableLogging) { . $moduleAppDeployToolkitMain -DisableLogging } Else { . $moduleAppDeployToolkitMain }
	}
	Catch {
		If ($mainExitCode -eq 0){ [int32]$mainExitCode = 60008 }
		Write-Error -Message "Module [$moduleAppDeployToolkitMain] failed to load: `n$($_.Exception.Message)`n `n$($_.InvocationInfo.PositionMessage)" -ErrorAction 'Continue'
		## Exit the script, returning the exit code to SCCM
		If (Test-Path -LiteralPath 'variable:HostInvocation') { $script:ExitCode = $mainExitCode; Exit } Else { Exit $mainExitCode }
	}

	#endregion
	##* Do not modify section above
	##*===============================================
	##* END VARIABLE DECLARATION
	##*===============================================

	If ($deploymentType -ine 'Uninstall' -and $deploymentType -ine 'Repair') {
		##*===============================================
		##* PRE-INSTALLATION
		##*===============================================
		[string]$installPhase = 'Pre-Installation'

		## Show Welcome Message, close Internet Explorer if required, allow up to 3 deferrals, verify there is enough disk space to complete the install, and persist the prompt
		Show-InstallationWelcome -CloseApps 'acrobat,acrocef,acrodist,acrotray,adobe audition cc,adobe cef helper,adobe desktop service,adobe qt32 server,adobearm,adobecollabsync,adobegcclient,adobeipcbroker,adobeupdateservice,afterfx,agsservice,animate,armsvc,cclibrary,ccxprocess,cephtmlengine,coresync,creative cloud,dynamiclinkmanager,illustrator,indesign,node,pdapp,photoshop,firefox,chrome,excel,groove,iexplore,infopath,lync,onedrive,onenote,onenotem,outlook,mspub,powerpnt,winword,winproj,visio' -CheckDiskSpace -PersistPrompt

		## Show Progress Message (with the default message)
		Show-InstallationProgress

		## <Perform Pre-Installation tasks here>
		## This essentially replaces the functionality of Creative Cloud Packager. It even uses the same xml file as Creative Cloud Packager to perform the uninstall.
		$applicationList = 'XD','Creative Cloud'
		ForEach($installedApplication in $applicationList) {
			$installedApplicationList = Get-InstalledApplication -Name $installedApplication
			ForEach($application in $installedApplicationList) {
				$application
				if($application.UninstallString) {
					Write-Log -Message "Uninstall string: $($application.UninstallString)" -Source 'Pre-Installation' -LogType 'CMTrace'
					Write-Log -Message "Uninstall subkey: $($application.UninstallSubkey)" -Source 'Pre-Installation' -LogType 'CMTrace'
					## First, we want to check if the program was installed with a package. If it was, then we simply run the MSI uninstaller.
					if($application.UninstallString.contains("MsiExec.exe") -and ($application.UninstallSubkey)) {
						## You might get exit code 1603 if the packaged apps were uninstalled without using the MSI uninstaller.
						## The MSI uninstaller will try to run, see that there are no apps to uninstall, and fail with exit code 1603.
						## The only way to remove the package is to reinstall the package and then uninstall it with the MSI uninstaller.
						## You might also be able to do a manual cleanup of leftover files, directories, and or reg keys.
						Write-Log -Message "Attempting to run uninstaller..." -Source 'Pre-Installation' -LogType 'CMTrace'
						$exitCode = Execute-Process -Path "MsiExec.exe" -Parameters "/x$($application.UninstallSubkey) /q" -WindowStyle "Hidden"-IgnoreExitCodes '1603' -PassThru
						If (($exitCode.ExitCode -ne "0") -and ($mainExitCode -ne "3010")) { $mainExitCode = $exitCode.ExitCode }
					}
					## If the application wasn't installed with a package, we'll to check to see if it uses the standard Adobe uninstaller. If it does, we're in luck.
					## Unfortunately, we can't run it as is because the standard Adobe uninstaller requires user interaction. However, it does give us everything we need to do a silent uninstall.
					## The full uninstall string provided by Get-InstalledApplication will look something like this:
					## C:\Program Files (x86)\Common Files\Adobe\Adobe Desktop Common\HDBox\Uninstaller.exe" --uninstall=1 --sapCode=ILST --productVersion=26.3.1 --productPlatform=win64 --productAdobeCode={ILST-26.3.1-64-ADBEADBEADBEADBEADBEA} --productName="Illustrator" --mode=0
					## First, we separate out the options into individual strings using split and then remove everything except the value using trim.
					ElseIf($application.UninstallString.contains("${Env:ProgramFiles(x86)}\Common Files\Adobe\Adobe Desktop Common\HDBox\Uninstaller.exe")) {
						$substringArray = $application.UninstallString -split " --"
						ForEach($item in $substringArray) {
							if($item.contains("sapCode=")) {
								$sapCode = $item.trim("sapCode=")
							}
							elseif($item.contains("productVersion=")) {
								$productVersion = $item.trim("productVersion=")
								$pointValues = $productVersion.split('.')
								$baseVersion = $pointValues[0]
							}
							elseif($item.contains("productPlatform=")) {
								$productPlatform = $item.trim("productPlatform=")
							}
						}
						## This next part is a little messy. We can't just pass the $productVersion into the uninstaller below because the uninstaller is expecting the base version of the application so it knows what to uninstall.
						## To get around that, we have to compare the installed version against a list of base versions that Adobe provides as an xml file.
						## If you look above, you'll see that we take our $productVersion and pare it down to $baseVersion. In other words, 25.4.6 becomes 25.
						## Unfortunately, we can't pass that directly, because the base version could be 25.0 or even 25.0.0. So now, we compare our 25 to the product version contained in our xml file.
						## Conceivably, you could get 13.0.25 instead of 25.0.0, so we want to make sure that 25 shows up at the beginning of the version number. We perform a wildcard comparision  using * to see if 25 matches 25.0 in the XML file.
						[xml]$xmlAdobeCCUninstallerConfig = Get-Content -Path "$dirFiles\AdobeCCUninstallerConfig.xml"
						$xmlAdobeCCUninstallerConfig.CCPUninstallXML.UninstallInfo.RIBS.Products.Product | Where-Object {$_.SapCode -eq $sapCode -and $_.Version -like "$baseVersion*"} |  ForEach-Object {
							Write-Log -Message "$($_.SapCode), $($_.Version)" -Source 'Pre-Installation' -LogType 'CMTrace'
							If ( Test-Path "${Env:ProgramFiles(x86)}\Common Files\Adobe\Adobe Desktop Common\HDBox\Setup.exe") {
								$exitCode = Execute-Process -Path "${Env:ProgramFiles(x86)}\Common Files\Adobe\Adobe Desktop Common\HDBox\Setup.exe" -Parameters "--uninstall=1 --sapCode=$($_.SapCode) --baseVersion=$($_.Version) --platform=$($_.Platform) --deleteUserPreferences=false" -WindowStyle "Hidden" -IgnoreExitCodes '33,135' -PassThru
								If (($exitCode.ExitCode -ne "0") -and ($mainExitCode -ne "3010")) { $mainExitCode = $exitCode.ExitCode }
							}
						}
						$xmlAdobeCCUninstallerConfig.CCPUninstallXML.UninstallInfo.HD.Products.Product | Where-Object {$_.SapCode -eq $sapCode -and $_.BaseVersion -like "$baseVersion*"} |  ForEach-Object {
							Write-Log -Message "$($_.SapCode), $($_.BaseVersion)" -Source 'Pre-Installation' -LogType 'CMTrace'
							If ( Test-Path "${Env:ProgramFiles(x86)}\Common Files\Adobe\Adobe Desktop Common\HDBox\Setup.exe") {
								$exitCode = Execute-Process -Path "${Env:ProgramFiles(x86)}\Common Files\Adobe\Adobe Desktop Common\HDBox\Setup.exe" -Parameters "--uninstall=1 --sapCode=$($_.SapCode) --baseVersion=$($_.BaseVersion) --platform=$($_.Platform) --deleteUserPreferences=false" -WindowStyle "Hidden" -IgnoreExitCodes '33,135' -PassThru
								If (($exitCode.ExitCode -ne "0") -and ($mainExitCode -ne "3010")) { $mainExitCode = $exitCode.ExitCode }
							}
						}
					}
					ElseIf($application.UninstallString.contains("${Env:ProgramFiles(x86)}\Adobe\Adobe Creative Cloud\Utils\Creative Cloud Uninstaller.exe")) {
						Write-Log -Message "Attempting to run uninstaller..." -Source 'Pre-Installation' -LogType 'CMTrace'
						Write-Log -Message "Note: Creative Cloud can not be uninstalled if there are Creative Cloud applications installed that require it." -Source 'Pre-Installation' -LogType 'CMTrace'
						$exitCode = Execute-Process -Path "${Env:ProgramFiles(x86)}\Adobe\Adobe Creative Cloud\Utils\Creative Cloud Uninstaller.exe" -Parameters "-u" -WindowStyle "Hidden" -PassThru
						If (($exitCode.ExitCode -ne "0") -and ($mainExitCode -ne "3010")) { $mainExitCode = $exitCode.ExitCode }
					}
					Else {
						Write-Log -Message "The uninstall string returned was not expected." -Source 'Pre-Installation' -LogType 'CMTrace'
					}
				}
				Else {
					Write-Log -Message "A program was detected but a valid uninstall string and or subkey could not be found." -Source 'Pre-Installation' -LogType 'CMTrace'

				}
			}
		}

		## This is the old way of doing it. Adobe is no longer continuing development and maintenance of Creative Cloud Packager and
		## recommends that you do not continue using Creative Cloud Packager to uninstall Creative Cloud apps.
		<#
		Remove-File -Path "$envCommonProgramFilesX86\Adobe\OOBE\PDApp\*" -Recurse -ContinueOnError $true
		If (-not ($envOSVersion -like "10.0*")) {
			Install-MSUpdates -Directory "$dirSupportFiles\$envOSVersionMajor.$envOSVersionMinor"
		}
				$exitCode = Execute-Process -Path "$dirSupportFiles\Uninstall\AdobeCCUninstaller.exe" -WindowStyle "Hidden" -IgnoreExitCodes '33,135' -PassThru
				If (($exitCode.ExitCode -ne "0") -and ($mainExitCode -ne "3010")) { $mainExitCode = $exitCode.ExitCode }
		#>

		##*===============================================
		##* INSTALLATION
		##*===============================================
		[string]$installPhase = 'Installation'

		## Handle Zero-Config MSI Installations
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Install'; Path = $defaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat; If ($defaultMspFiles) { $defaultMspFiles | ForEach-Object { Execute-MSI -Action 'Patch' -Path $_ } }
		}

		## <Perform Installation tasks here>

		$exitCode = Execute-Process -Path "$dirFiles\Build\setup.exe" -Parameters "--silent --INSTALLLANGUAGE=en_US" -WindowStyle "Hidden" -PassThru
		If (($exitCode.ExitCode -ne "0") -and ($mainExitCode -ne "3010")) { $mainExitCode = $exitCode.ExitCode }


		##*===============================================
		##* POST-INSTALLATION
		##*===============================================
		[string]$installPhase = 'Post-Installation'

		## <Perform Post-Installation tasks here>

		#Fix Adobe's garbage installer if it kills explorer
        $ProcessActive = Get-Process explorer -ErrorAction SilentlyContinue
        if(!$ProcessActive){
            Execute-ProcessAsUser -Path "$envSystemRoot\explorer.exe"
            Write-Log "Restarting Explorer"
        }
        Else{
            Write-Log "No restart of explorer needed"
        }

		Execute-Process -Path "$envCommonProgramFilesX86\Adobe\OOBE_Enterprise\RemoteUpdateManager\RemoteUpdateManager.exe" -WindowStyle "Hidden" -PassThru -IgnoreExitCodes '1'
	  	Remove-File -Path "$envCommonDesktop\Adobe Creative Cloud.lnk" -ContinueOnError $true

		## Display a message at the end of the install
		If (-not $useDefaultMsi) { Show-InstallationPrompt -Message "$appName $appVersion has been successfully installed." -ButtonRightText 'OK' -Icon Information -NoWait }
	}
	ElseIf ($deploymentType -ieq 'Uninstall')
	{
		##*===============================================
		##* PRE-UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Pre-Uninstallation'

		## Show Welcome Message, close Internet Explorer with a 60 second countdown before automatically closing
		Show-InstallationWelcome -CloseApps 'acrobat,acrocef,acrodist,acrotray,adobe audition cc,adobe cef helper,adobe desktop service,adobe qt32 server,adobearm,adobecollabsync,adobegcclient,adobeipcbroker,adobeupdateservice,afterfx,agsservice,animate,armsvc,cclibrary,ccxprocess,cephtmlengine,coresync,creative cloud,dynamiclinkmanager,illustrator,indesign,node,pdapp,photoshop,firefox,chrome,excel,groove,iexplore,infopath,lync,onedrive,onenote,onenotem,outlook,mspub,powerpnt,winword,winproj,visio' -CloseAppsCountdown 60


		## Show Progress Message (with the default message)
		Show-InstallationProgress

		## <Perform Pre-Uninstallation tasks here>


		##*===============================================
		##* UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Uninstallation'

		## Handle Zero-Config MSI Uninstallations
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Uninstall'; Path = $defaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat
		}

		# <Perform Uninstallation tasks here>
		$exitCode = Execute-Process -Path "MsiExec.exe" -Parameters "/x{099190ec-0be6-4322-8afc-6af42fcdac73} /q" -WindowStyle "Hidden" -PassThru
		If (($exitCode.ExitCode -ne "0") -and ($mainExitCode -ne "3010")) { $mainExitCode = $exitCode.ExitCode }


		## Adobe is no longer continuing development and maintenance of Creative Cloud Packager and recommends that you do not continue using Creative Cloud Packager to uninstall Creative Cloud apps.
		<#
		$exitCode = Execute-Process -Path "$dirSupportFiles\Uninstall\AdobeCCUninstaller.exe" -WindowStyle "Hidden" -IgnoreExitCodes '33,135' -PassThru
		Start-Sleep -s 10
		If (($exitCode.ExitCode -ne "0") -and ($mainExitCode -ne "3010")) { $mainExitCode = $exitCode.ExitCode }
		#>

		##*===============================================
		##* POST-UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Post-Uninstallation'

		## <Perform Post-Uninstallation tasks here>

	}
	ElseIf ($deploymentType -ieq 'Repair')
	{
		##*===============================================
		##* PRE-REPAIR
		##*===============================================
		[string]$installPhase = 'Pre-Repair'

		## Show Progress Message (with the default message)
		Show-InstallationProgress

		## <Perform Pre-Repair tasks here>

		##*===============================================
		##* REPAIR
		##*===============================================
		[string]$installPhase = 'Repair'

		## Handle Zero-Config MSI Repairs
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Repair'; Path = $defaultMsiFile; }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat
		}
		# <Perform Repair tasks here>

		##*===============================================
		##* POST-REPAIR
		##*===============================================
		[string]$installPhase = 'Post-Repair'

		## <Perform Post-Repair tasks here>


    }
	##*===============================================
	##* END SCRIPT BODY
	##*===============================================

	## Call the Exit-Script function to perform final cleanup operations
	Exit-Script -ExitCode $mainExitCode
}
Catch {
	[int32]$mainExitCode = 60001
	[string]$mainErrorMessage = "$(Resolve-Error)"
	Write-Log -Message $mainErrorMessage -Severity 3 -Source $deployAppScriptFriendlyName
	Show-DialogBox -Text $mainErrorMessage -Icon 'Stop'
	Exit-Script -ExitCode $mainExitCode
}

# SIG # Begin signature block
# MIIU9wYJKoZIhvcNAQcCoIIU6DCCFOQCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUQuqEfQnTb46+mw0sKIpelMH5
# Hm+gghHXMIIFbzCCBFegAwIBAgIQSPyTtGBVlI02p8mKidaUFjANBgkqhkiG9w0B
# AQwFADB7MQswCQYDVQQGEwJHQjEbMBkGA1UECAwSR3JlYXRlciBNYW5jaGVzdGVy
# MRAwDgYDVQQHDAdTYWxmb3JkMRowGAYDVQQKDBFDb21vZG8gQ0EgTGltaXRlZDEh
# MB8GA1UEAwwYQUFBIENlcnRpZmljYXRlIFNlcnZpY2VzMB4XDTIxMDUyNTAwMDAw
# MFoXDTI4MTIzMTIzNTk1OVowVjELMAkGA1UEBhMCR0IxGDAWBgNVBAoTD1NlY3Rp
# Z28gTGltaXRlZDEtMCsGA1UEAxMkU2VjdGlnbyBQdWJsaWMgQ29kZSBTaWduaW5n
# IFJvb3QgUjQ2MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAjeeUEiIE
# JHQu/xYjApKKtq42haxH1CORKz7cfeIxoFFvrISR41KKteKW3tCHYySJiv/vEpM7
# fbu2ir29BX8nm2tl06UMabG8STma8W1uquSggyfamg0rUOlLW7O4ZDakfko9qXGr
# YbNzszwLDO/bM1flvjQ345cbXf0fEj2CA3bm+z9m0pQxafptszSswXp43JJQ8mTH
# qi0Eq8Nq6uAvp6fcbtfo/9ohq0C/ue4NnsbZnpnvxt4fqQx2sycgoda6/YDnAdLv
# 64IplXCN/7sVz/7RDzaiLk8ykHRGa0c1E3cFM09jLrgt4b9lpwRrGNhx+swI8m2J
# mRCxrds+LOSqGLDGBwF1Z95t6WNjHjZ/aYm+qkU+blpfj6Fby50whjDoA7NAxg0P
# OM1nqFOI+rgwZfpvx+cdsYN0aT6sxGg7seZnM5q2COCABUhA7vaCZEao9XOwBpXy
# bGWfv1VbHJxXGsd4RnxwqpQbghesh+m2yQ6BHEDWFhcp/FycGCvqRfXvvdVnTyhe
# Be6QTHrnxvTQ/PrNPjJGEyA2igTqt6oHRpwNkzoJZplYXCmjuQymMDg80EY2NXyc
# uu7D1fkKdvp+BRtAypI16dV60bV/AK6pkKrFfwGcELEW/MxuGNxvYv6mUKe4e7id
# FT/+IAx1yCJaE5UZkADpGtXChvHjjuxf9OUCAwEAAaOCARIwggEOMB8GA1UdIwQY
# MBaAFKARCiM+lvEH7OKvKe+CpX/QMKS0MB0GA1UdDgQWBBQy65Ka/zWWSC8oQEJw
# IDaRXBeF5jAOBgNVHQ8BAf8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zATBgNVHSUE
# DDAKBggrBgEFBQcDAzAbBgNVHSAEFDASMAYGBFUdIAAwCAYGZ4EMAQQBMEMGA1Ud
# HwQ8MDowOKA2oDSGMmh0dHA6Ly9jcmwuY29tb2RvY2EuY29tL0FBQUNlcnRpZmlj
# YXRlU2VydmljZXMuY3JsMDQGCCsGAQUFBwEBBCgwJjAkBggrBgEFBQcwAYYYaHR0
# cDovL29jc3AuY29tb2RvY2EuY29tMA0GCSqGSIb3DQEBDAUAA4IBAQASv6Hvi3Sa
# mES4aUa1qyQKDKSKZ7g6gb9Fin1SB6iNH04hhTmja14tIIa/ELiueTtTzbT72ES+
# BtlcY2fUQBaHRIZyKtYyFfUSg8L54V0RQGf2QidyxSPiAjgaTCDi2wH3zUZPJqJ8
# ZsBRNraJAlTH/Fj7bADu/pimLpWhDFMpH2/YGaZPnvesCepdgsaLr4CnvYFIUoQx
# 2jLsFeSmTD1sOXPUC4U5IOCFGmjhp0g4qdE2JXfBjRkWxYhMZn0vY86Y6GnfrDyo
# XZ3JHFuu2PMvdM+4fvbXg50RlmKarkUT2n/cR/vfw1Kf5gZV6Z2M8jpiUbzsJA8p
# 1FiAhORFe1rYMIIGGjCCBAKgAwIBAgIQYh1tDFIBnjuQeRUgiSEcCjANBgkqhkiG
# 9w0BAQwFADBWMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVk
# MS0wKwYDVQQDEyRTZWN0aWdvIFB1YmxpYyBDb2RlIFNpZ25pbmcgUm9vdCBSNDYw
# HhcNMjEwMzIyMDAwMDAwWhcNMzYwMzIxMjM1OTU5WjBUMQswCQYDVQQGEwJHQjEY
# MBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSswKQYDVQQDEyJTZWN0aWdvIFB1Ymxp
# YyBDb2RlIFNpZ25pbmcgQ0EgUjM2MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIB
# igKCAYEAmyudU/o1P45gBkNqwM/1f/bIU1MYyM7TbH78WAeVF3llMwsRHgBGRmxD
# eEDIArCS2VCoVk4Y/8j6stIkmYV5Gej4NgNjVQ4BYoDjGMwdjioXan1hlaGFt4Wk
# 9vT0k2oWJMJjL9G//N523hAm4jF4UjrW2pvv9+hdPX8tbbAfI3v0VdJiJPFy/7Xw
# iunD7mBxNtecM6ytIdUlh08T2z7mJEXZD9OWcJkZk5wDuf2q52PN43jc4T9OkoXZ
# 0arWZVeffvMr/iiIROSCzKoDmWABDRzV/UiQ5vqsaeFaqQdzFf4ed8peNWh1OaZX
# nYvZQgWx/SXiJDRSAolRzZEZquE6cbcH747FHncs/Kzcn0Ccv2jrOW+LPmnOyB+t
# AfiWu01TPhCr9VrkxsHC5qFNxaThTG5j4/Kc+ODD2dX/fmBECELcvzUHf9shoFvr
# n35XGf2RPaNTO2uSZ6n9otv7jElspkfK9qEATHZcodp+R4q2OIypxR//YEb3fkDn
# 3UayWW9bAgMBAAGjggFkMIIBYDAfBgNVHSMEGDAWgBQy65Ka/zWWSC8oQEJwIDaR
# XBeF5jAdBgNVHQ4EFgQUDyrLIIcouOxvSK4rVKYpqhekzQwwDgYDVR0PAQH/BAQD
# AgGGMBIGA1UdEwEB/wQIMAYBAf8CAQAwEwYDVR0lBAwwCgYIKwYBBQUHAwMwGwYD
# VR0gBBQwEjAGBgRVHSAAMAgGBmeBDAEEATBLBgNVHR8ERDBCMECgPqA8hjpodHRw
# Oi8vY3JsLnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNDb2RlU2lnbmluZ1Jvb3RS
# NDYuY3JsMHsGCCsGAQUFBwEBBG8wbTBGBggrBgEFBQcwAoY6aHR0cDovL2NydC5z
# ZWN0aWdvLmNvbS9TZWN0aWdvUHVibGljQ29kZVNpZ25pbmdSb290UjQ2LnA3YzAj
# BggrBgEFBQcwAYYXaHR0cDovL29jc3Auc2VjdGlnby5jb20wDQYJKoZIhvcNAQEM
# BQADggIBAAb/guF3YzZue6EVIJsT/wT+mHVEYcNWlXHRkT+FoetAQLHI1uBy/YXK
# ZDk8+Y1LoNqHrp22AKMGxQtgCivnDHFyAQ9GXTmlk7MjcgQbDCx6mn7yIawsppWk
# vfPkKaAQsiqaT9DnMWBHVNIabGqgQSGTrQWo43MOfsPynhbz2Hyxf5XWKZpRvr3d
# MapandPfYgoZ8iDL2OR3sYztgJrbG6VZ9DoTXFm1g0Rf97Aaen1l4c+w3DC+IkwF
# kvjFV3jS49ZSc4lShKK6BrPTJYs4NG1DGzmpToTnwoqZ8fAmi2XlZnuchC4NPSZa
# PATHvNIzt+z1PHo35D/f7j2pO1S8BCysQDHCbM5Mnomnq5aYcKCsdbh0czchOm8b
# kinLrYrKpii+Tk7pwL7TjRKLXkomm5D1Umds++pip8wH2cQpf93at3VDcOK4N7Ew
# oIJB0kak6pSzEu4I64U6gZs7tS/dGNSljf2OSSnRr7KWzq03zl8l75jy+hOds9TW
# SenLbjBQUGR96cFr6lEUfAIEHVC1L68Y1GGxx4/eRI82ut83axHMViw1+sVpbPxg
# 51Tbnio1lB93079WPFnYaOvfGAA0e0zcfF/M9gXr+korwQTh2Prqooq2bYNMvUoU
# KD85gnJ+t0smrWrb8dee2CvYZXD5laGtaAxOfy/VKNmwuWuAh9kcMIIGQjCCBKqg
# AwIBAgIRAKVN33D73PFMVIK48rFyyjEwDQYJKoZIhvcNAQEMBQAwVDELMAkGA1UE
# BhMCR0IxGDAWBgNVBAoTD1NlY3RpZ28gTGltaXRlZDErMCkGA1UEAxMiU2VjdGln
# byBQdWJsaWMgQ29kZSBTaWduaW5nIENBIFIzNjAeFw0yMTA2MDkwMDAwMDBaFw0y
# NDA2MDgyMzU5NTlaMIGVMQswCQYDVQQGEwJVUzERMA8GA1UECAwIQ29sb3JhZG8x
# DzANBgNVBAcMBkRlbnZlcjEwMC4GA1UECgwnTWV0cm9wb2xpdGFuIFN0YXRlIFVu
# aXZlcnNpdHkgb2YgRGVudmVyMTAwLgYDVQQDDCdNZXRyb3BvbGl0YW4gU3RhdGUg
# VW5pdmVyc2l0eSBvZiBEZW52ZXIwggGiMA0GCSqGSIb3DQEBAQUAA4IBjwAwggGK
# AoIBgQCm6Atd6yEc/W5UCNp/h5BikWqPKgINMSLcRjaIRilzk9VGu4Q1hufpdjAa
# XXW0EHzEjshU/gMorErUXxUW9U1NWkiPEMRydb5DquuAGSlyCrjcUxEL+9USsk4J
# 483biCOEKgYbCLK1+LzeT2hav8ioyaikrGEIxXo+CsdnzkVzBUR56mgBlu6gMCby
# nE1As1Z/9YavXYem908Tnd7dcdi9D2s/+GhfiQIZDThfRnNgfIXk6EZZU0DjklHT
# 898JFt8u7us3CTBIMXp54kz+35N+PIV5azwY8me6oswid8Fh/kEagakoXimTfzpc
# OmmHaiwJm5fS2d2dP670DJPwA0x7GOYwF8AEY8QJVPoJ8Y/+pMrEuiQxT/tB+wg9
# 30ZUgTlrHD24N9eM3hjMfHjizfNVlirv+/Ut1h1gH/OLsTZ6dg3Ff/GjbI16GsX3
# UFlyaerN1dcH+ScsL+58XGYLUufjCcx07/mHN4T1D+14y6WgIpx3/Pq2nusj+zle
# q9yWd/UCAwEAAaOCAcswggHHMB8GA1UdIwQYMBaAFA8qyyCHKLjsb0iuK1SmKaoX
# pM0MMB0GA1UdDgQWBBTLXarMi7SgsX53Cweg5K+AM/BXJTAOBgNVHQ8BAf8EBAMC
# B4AwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcDAzARBglghkgBhvhC
# AQEEBAMCBBAwSgYDVR0gBEMwQTA1BgwrBgEEAbIxAQIBAwIwJTAjBggrBgEFBQcC
# ARYXaHR0cHM6Ly9zZWN0aWdvLmNvbS9DUFMwCAYGZ4EMAQQBMEkGA1UdHwRCMEAw
# PqA8oDqGOGh0dHA6Ly9jcmwuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY0NvZGVT
# aWduaW5nQ0FSMzYuY3JsMHkGCCsGAQUFBwEBBG0wazBEBggrBgEFBQcwAoY4aHR0
# cDovL2NydC5zZWN0aWdvLmNvbS9TZWN0aWdvUHVibGljQ29kZVNpZ25pbmdDQVIz
# Ni5jcnQwIwYIKwYBBQUHMAGGF2h0dHA6Ly9vY3NwLnNlY3RpZ28uY29tMC0GA1Ud
# EQQmMCSBIml0c3N5c3RlbWVuZ2luZWVyaW5nQG1zdWRlbnZlci5lZHUwDQYJKoZI
# hvcNAQEMBQADggGBAH/FAFHuy+iH7Vk/LuZw8nkpQIBsQc4+A3d8YI0cJLIUh+x+
# U78k2nZGZQQaKEy9/dCBtV9bryx5jgtt6hiNGMrWCwnzXCqatSY6PFdCXPXtUcBx
# h/8+ud3CeE7AmGHRk4LcM9SdTmRx1XjMK9Kest4O7dBEUbgQpatb54sVESclkcIO
# 5pUowa4kab9gCmPMcEgdyTHAxffmLEWAkoYofoS3D6eGMoJGh45VYXOSv4irKEtY
# +wk+Km41ZdO+wplcrDvCjA0kwEzHzmmBZ4GsRbz3znKjcQrvJ9SDCBZzJ3aIlnv0
# rd7Q3cIEnUEKgcWduCmWRg6mvY/o5b3DuwL4k9ufPonL2Ym154FATNWk3j7zJ1vd
# bkyZcMpefCtVtgg511abPE2VDF0KvLg/WJ+FQNTAzZHzeZnhwVJpoiPGTBwa9ra8
# zPeFPxKUwlSvh7kpTgdKE1QtPbTKq3KCt1CVzXTXPo/iCh3pPnc1HMIuFYJiRvnY
# K4Elz1T3NrNPgL038zGCAoowggKGAgEBMGkwVDELMAkGA1UEBhMCR0IxGDAWBgNV
# BAoTD1NlY3RpZ28gTGltaXRlZDErMCkGA1UEAxMiU2VjdGlnbyBQdWJsaWMgQ29k
# ZSBTaWduaW5nIENBIFIzNgIRAKVN33D73PFMVIK48rFyyjEwCQYFKw4DAhoFAKB4
# MBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwGCisGAQQB
# gjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkE
# MRYEFD9WE72wF2CxwEV+LnfNexJTPZdvMA0GCSqGSIb3DQEBAQUABIIBgCx+7TvO
# d5OtqudBSYm/GphCYbXD9Yo9q13eHK8Rb95qfSrhVU77fyWqoCIlbeB1CSjxwH9I
# Gyi+g52CAPGG1FEW0mpBbziTQppaZhASYpFLxCXPYnIbLHBUDIoxB5evozjQ+wOb
# iYxa09eoLoWKahknPTJqiczt+yDXttDcm5JSd8dQ6ut5d3/PLTXFJYF0m3q0dgKi
# UZ1a37i26xeFOF/Z+9ZM1VkVKwuHrhRfwdTONNY+9MmSZBrkTjAKzijbtJyBTr6g
# 5/lLSQ1P2WEYO3fW6F3izuaPL/A54g5fZIQ04VXJFJGaHtlf8yuYHdKMVxIlQBWr
# b5DioC3Bt8hfGTdmkxg2HCOS7hGRz1tOYz/elRl67v7jifSB2q488X2Vvbwkbhwz
# sunEwdVNvW7eabsd7eyiASKVLwI7YxtzaYl2r3TxjVWrFlxkHcXOVEgGB0ae9o2z
# ZNi2SLuUlJYeQ6oJpXzEX86jTKd8Mngow/iOaWnYeJvAD+JKPPgiqmVWJA==
# SIG # End signature block
