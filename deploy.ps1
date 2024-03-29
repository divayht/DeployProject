Param(
	[parameter(Mandatory=$true)]
	[String] $SVNRepository,
	
	[parameter(Mandatory=$true)]
	[ValidateScript({Test-Path $_ -PathType 'Container'})]
	[String] $LocalPath,
	
	[Switch] $Publish,
	
	[ValidateScript({Test-Path $_ -PathType 'Container'})]
	[String] $PublishPath = "$LocalPath\Build\Package",
	
	[Switch] $FTPDeploy,
	[String] $FTPUri,
	[String] $FTPUser = "Anonymous",
	[String] $FTPPassword = "anonymous@playtem.com",
	#[int] $FTPPort = 21,
	[String] $FTPFolder,
	
	
	[String] $LogFile = "C:\temp\ps\deploy.log",
	[String] $AppOffline = "D:\Work\_Playtem\Files\Code\app_offline.htm"
)

#
# Config
#
[System.IO.FileInfo] $AppOfflineFile = New-Object System.IO.FileInfo($AppOffline)
#
#Functions
#

#SVN

Function Checkout-SVN
{
	Param(
		[parameter(Mandatory=$true)]
		[String] $RemoteRepositoryUrl,
		[parameter(Mandatory=$true)]
		[ValidateScript({Test-Path $_ -PathType 'Container'})]
		[String] $LocalPath,
		[int] $revisionNumber = 0
	)
	
	try
	{
		if($revisionNumber -ne 0)
	    {
	        svn checkout $RemoteRepositoryUrl $LocalPath --revision $revisionNumber  
	    }
	    else
	    {
	        svn checkout $RemoteRepositoryUrl $LocalPath
	    }
	}
	catch [Exception]
	{
		"$($_.Exception.ToString()). $($_.InvocationInfo.PositionMessage)" >> $LogFile
	}

}

#Compilation

Function Build-Project
{
	Param(
		[parameter(Mandatory=$true)]
		[ValidateScript({Test-Path $_ -PathType 'Container'})]
		[String] $ProjectPath,
		
		[ValidateScript({Test-Path $_ -PathType 'Container'})]
		[String] $OutputDirectory = "$ProjectPath\Build\Package",
		
		[Switch] $ExcludeConfigurationFiles,
		[bool] $Publish
	)

    $SolutionFile = (dir $ProjectPath -Recurse -Filter *.sln).FullName
	if( $SolutionFile -eq $null)
	{
		"function Build-Project: solution file couldn't be found. Exit." >> $LogFile
		break
	}

    $Build = "$ProjectPath\Build"
    $Debug = "$Build\Debug"
    $PublishPath = "$debug\_PublishedWebsites"
	
	$BlackList = @() #Excluded files
	$BlackListFolder = @() #Excluded folders
	
	if ($ExcludeConfigurationFiles -eq $true)
	{
		$BlackList = @( "*.config" )
		$BlackListFolder = @( "App_Data" )
	}
	
	$MSBuildLogger = "/logger:FileLogger,Microsoft.Build.Engine;logfile=$LogFile"
    MSBuild /verbosity:normal $MSBuildLogger /p:Configuration="Debug" /p:Platform="Any CPU" /p:OutDir="$Debug"\\ $SolutionFile 
	
	if ($Publish -eq $true)
	{
		Robocopy $PublishPath $OutputDirectory /XD $BlackListFolder /XF $BlackList /S /LOG:$LogFile
	}
}

#FTP

Function Send-FTPFolder
{
	param(
		[Parameter(Mandatory=$true)]
		[String] $FTPServer,
		
		[Parameter(Mandatory=$true)]
		[String] $LocalFolder
	)

    $Webclient = New-Object System.Net.WebClient
	if( $FTPServer.Endswith("/") -eq $false)
	{
		$FTPServer += "/"
	}

    foreach($item in Get-ChildItem -recurse $LocalFolder)
	{
		$currentFolderLength = [system.io.path]::GetFullPath($LocalFolder).Length + 1
		
        $itemRelativePath = [system.io.path]::GetFullPath($item.FullName).SubString($currentFolderLength)
		
		$FullPath = $FTPServer + $itemRelativePath
		
        if ($item.Attributes -eq "Directory")
		{
            New-FTPItem $FullPath
			continue
        }
		
		Send-FTPItem $FullPath $item.FullName
    }
}

Function New-FTPItem
{
	param(
		[Parameter(Mandatory=$true)]
		[String] $FTPServer
	)
	
    try
	{
        $newDirectory = [System.Net.WebRequest]::Create($FTPServer)
        $newDirectory.Method = [System.Net.WebRequestMethods+FTP]::MakeDirectory
        $newDirectory.GetResponse()
    
    }
	catch [Net.WebException]
	{}
	catch [Exception]
	{
		"$($_.Exception.ToString()). $($_.InvocationInfo.PositionMessage)" >> $LogFile
	}
}

Function Send-FTPItem
{
	param(
		[Parameter(Mandatory=$true)]
		[String] $FTPServer,
		
		[Parameter(Mandatory=$true)]
		[String] $File
	)
	
    $webclient = New-Object System.Net.WebClient

	try
	{
		$webclient.UploadFile($FTPServer, $File)
	}
	catch [Net.WebException]
	{}
	catch [Exception]
	{
		"$($_.Exception.ToString()). $($_.InvocationInfo.PositionMessage)" >> $LogFile
	}
}

Function Remove-FTPItem
{
	param(
		[Parameter(Mandatory=$true)]
		[String] $FTPServer,
		
		[String] $FTPUser = "Anonymous",
		[String] $FTPPassword = "anonymous@playtem.com"
	)
	
    $operation = [System.Net.WebRequestMethods+Ftp]::DeleteFile
        
    Get-FTPConnection $FTPServer $FTPUser $FTPPassword $Operation
}

Function Get-FTPItem
{
	param(
		[Parameter(Mandatory=$true)]
		[String] $FTPServer,
		
		[String] $FTPUser = "Anonymous",
		[String] $FTPPassword = "anonymous@playtem.com",
		
		[Switch] $DirectoriesOnly
	)

    $Operation = [System.Net.WebRequestMethods+Ftp]::ListDirectoryDetails
	
    $Reader = Get-FTPConnection $FTPServer $FTPUser $FTPPassword $Operation

	while (($line = $reader.ReadLine()) -ne $null)
	{
		if ($DirectoriesOnly -eq $true)
		{
			if ($line.Contains("<DIR>"))
			{
				$line.split(" ", [StringSplitOptions]::RemoveEmptyEntries) | Select-Object -Last 1
			}
		}
		else
		{
			$line.split(" ", [StringSplitOptions]::RemoveEmptyEntries) | Select-Object -Last 1
		}
	}
    
    $reader.Dispose()
}

Function Get-FTPConnection
{
	param(
		[Parameter(Mandatory=$true)]
		[String] $FTPServer,
		
		[Parameter(Mandatory=$true)]
		[String] $FTPUser,
		
		[Parameter(Mandatory=$true)]
		[String] $FTPPassword,
		#[int] $FTPPort = 21,
		
		[String]$Method = $([System.Net.WebRequestMethods+Ftp]::ListDirectoryDetails)
	)
	
	$Credentials = New-Object System.Net.NetworkCredential($FTPUser, $FTPPassword)
	
    $FTPRequest = [System.Net.WebRequest]::Create($FTPServer)
	$FTPRequest.Credentials = $Credentials
    $FTPRequest.Method = $Method
	
	try
	{
		$FTPResponse = $FTPRequest.GetResponse()
		New-Object IO.StreamReader $FTPResponse.GetResponseStream()
	}
	catch [Exception]
	{
		"$($_.Exception.ToString()). $($_.InvocationInfo.PositionMessage)" >> $LogFile
	}
}

# Begin

Checkout-SVN -RemoteRepositoryUrl $SVNRepository -LocalPath $LocalPath
Build-Project -ProjectPath $LocalPath -OutputDirectory $PublishPath -ExcludeConfigurationFiles -Publish $Publish

if ($FTPDeploy -eq $true)
{
	$Project = (dir $PublishPath | Select-Object -First 1).Name
	$FTPTempUri = ""

	if ((Get-FTPItem $FtpUri -DirectoriesOnly) -contains $Project)
	{
		$FTPTempUri = $FtpUri + $Project + "\" + $AppOfflineFile.Name
		
		Send-FTPItem -FTPServer $FTPTempUri -File $AppOfflineFile.FullName
	}
	
	Send-FTPFolder -FTPServer $FtpUri -LocalFolder $PublishPath
	
	if ($FTPTempUri -ne "")
	{
		Remove-FTPItem -FTPServer $FTPTempUri
	}
}