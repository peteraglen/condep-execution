properties {
	$pwd = Split-Path $psake.build_script_file	
	$build_directory  = "$pwd\output\condep-execution"
	$configuration = "Release"
	$releaseNotes = ""
	$nunitPath = "$pwd\..\src\packages\NUnit.ConsoleRunner.3.4.1\tools"
	$nuget = "$pwd\..\tools\nuget.exe"
}
 
include .\..\tools\psake_ext.ps1

function GetNugetAssemblyVersion($assemblyPath) {
    
    if(Test-Path Env:\APPVEYOR_BUILD_VERSION)
    {
        $appVeyorBuildVersion = $env:APPVEYOR_BUILD_VERSION
     
		# Getting the version number. Without the beta part, if its a beta package   
        $version = $appVeyorBuildVersion.Split('.')
        $major = $version[0] 
        $minor = $version[1] 
        $patch = $version[2].Split('-') | Select-Object -First 1

        # Setting beta postfix, if beta build. The beta number must be 5 digits, therefor this operation.
        $betaString = ""
        if($appVeyorBuildVersion.Contains("beta"))
        {
        	$buildNumber = $appVeyorBuildVersion.Split('-') | Select-Object -Last 1 | % {$_.replace("beta","")}
        	switch ($buildNumber.length) 
        	{	 
            	1 {$buildNumber = $buildNumber.Insert(0, '0').Insert(0, '0').Insert(0, '0').Insert(0, '0')} 
            	2 {$buildNumber = $buildNumber.Insert(0, '0').Insert(0, '0').Insert(0, '0')} 
            	3 {$buildNumber = $buildNumber.Insert(0, '0').Insert(0, '0')}
            	4 {$buildNumber = $buildNumber.Insert(0, '0')}                
            	default {$buildNumber = $buildNumber}
        	}
        	$betaString = "-beta$buildNumber" 
        }	
        return "$major.$minor.$patch$betaString"
    }
    else
    {
		#When building on local machine, set versionnumber from assembly info.
        $versionInfo = Get-Item $assemblyPath | % versioninfo
        return "$($versionInfo.FileVersion)"
    }
}

task default -depends Build-All, Test-All, Pack-All
task ci -depends Build-All, Test-All, Pack-All

task Build-All -depends Clean, ResotreNugetPackages, Build, Check-VersionExists, Create-BuildSpec-ConDep-Execution
task Test-All -depends Test
task Pack-All -depends Pack-ConDep-Execution

task Check-VersionExists {
	$version = $(GetNugetAssemblyVersion $build_directory\ConDep.Execution\ConDep.Execution.dll)
	Exec { 
		$packages = & $nuget list "ConDep.Execution" -source "https://www.myget.org/F/condep/api/v3/index.json" -prerelease -allversions
		ForEach($package in $packages){
			$packageName = $package.Split(' ') | Select-Object -First 1
			if($packageName -eq "ConDep.Execution"){
				$packageVersionNumber = $package.Split(' ') | Select-Object -Last 1
				if($packageVersionNumber -eq $version){
					throw "ConDep.Execution $packageVersionNumber already exists on myget. Have you forgot to update version in appveyor.yml?"
				}
			}
		}
	}
}

task ResotreNugetPackages {
	Exec { & $nuget restore "$pwd\..\src\condep-execution.sln" }
}

task Build {
	Exec { msbuild "$pwd\..\src\condep-execution.sln" /t:Build /p:Configuration=$configuration /p:OutDir=$build_directory /p:GenerateProjectSpecificOutputFolder=true}
}

task Test {
    Exec { & $nunitPath\nunit3-console.exe $build_directory\ConDep.Execution.Tests\ConDep.Execution.Tests.dll --work=".\output" }
}

task Clean {
	Write-Host "Cleaning Build output"  -ForegroundColor Green
	Remove-Item $build_directory -Force -Recurse -ErrorAction SilentlyContinue
}

task Create-BuildSpec-ConDep-Execution {
	Generate-Nuspec-File `
		-file "$build_directory\condep.execution.nuspec" `
		-version $(GetNugetAssemblyVersion $build_directory\ConDep.Execution\ConDep.Execution.dll) `
		-id "ConDep.Execution" `
		-title "ConDep.Execution" `
		-licenseUrl "http://www.condep.io/license/" `
		-projectUrl "http://www.condep.io/" `
		-description "API for executing ConDep. ConDep is a highly extendable Domain Specific Language for Continuous Deployment, Continuous Delivery and Infrastructure as Code on Windows." `
		-iconUrl "https://raw.github.com/condep/ConDep/master/images/ConDepNugetLogo.png" `
		-releaseNotes "$releaseNotes" `
		-tags "Continuous Deployment Delivery Infrastructure WebDeploy Deploy msdeploy IIS automation powershell remote aws azure" `
		-dependencies @(
			@{ Name="ConDep.Dsl"; Version="[5.0.1,6)"},
			@{ Name="DotNetZip"; Version="[1.9.6,2)"},
			@{ Name="YamlDotNet"; Version="[3.7.0,4)"},
			@{ Name="WindowsAzure.ServiceBus"; Version="[2.7.6]"}
		) `
		-files @(
			@{ Path="ConDep.Execution\ConDep.Execution.dll"; Target="lib/net45"}, 
			@{ Path="ConDep.Execution\ConDep.Execution.xml"; Target="lib/net45"}
		)
}

task Pack-ConDep-Execution {
	Exec { & $nuget pack "$build_directory\condep.execution.nuspec" -OutputDirectory "$build_directory" }
}