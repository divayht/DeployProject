Param(
	#=== svn ===
	[String] $SVNRepository,
	[Switch] $NoCheckout,
	
	#Compile
	[ValidateScript({Test-Path $_ -PathType 'Container'})]
	[String] $LocalPath,
	
	#Publish
	[Switch] $Publish,
	[String] $PublishPath = "$LocalPath\Build\Package",

	#Deploy	
	[Switch] $FTPDeploy,
	[String] $FTPUri,
	[String] $FTPUser = "Anonymous",
	[String] $FTPPassword = "anonymous@playtem.com",
	[String] $FTPFolderName, #Name of folder you want to create
	
	#Additional config
	[String] $Log = "C:\temp\ps\deploy.log",
	[String] $AppOffline = "D:\Work\_Playtem\Files\Code\app_offline.htm"
)

#
# Config
#
[System.IO.FileInfo] $LogFile = New-Object System.IO.FileInfo($Log)
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
		
		#[ValidateScript({Test-Path $_ -PathType 'Container'})]
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
	
    MSBuild /verbosity:normal /p:Configuration="Debug" /p:Platform="Any CPU" /p:OutDir="$Debug"\\ $SolutionFile 
	
	if ($Publish -eq $true)
	{
		if ((Test-Path $OutputDirectory) -eq $false) {
		    new-item $OutputDirectory -type directory -force
		}

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
		[String] $FTPServer,
				
		[String] $FTPUser = "Anonymous",
		[String] $FTPPassword = "anonymous@playtem.com"
	)
	
    try
	{
		$FTPRequest = [System.Net.WebRequest]::Create($FTPServer)
		$FTPRequest.Method = [System.Net.WebRequestMethods+FTP]::MakeDirectory
        [Void] $FTPRequest.GetResponse()
    }
	catch [Exception]
	{}
}

Function Send-FTPItem
{
	param(
		[Parameter(Mandatory=$true)]
		[String] $FTPServer,
		
		[Parameter(Mandatory=$true)]
		[String] $File
	)
	
    $Webclient = New-Object System.Net.WebClient

	try
	{
		$Webclient.UploadFile($FTPServer, $File)
	}
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

    $Method = [System.Net.WebRequestMethods+Ftp]::ListDirectoryDetails
	
	$Credentials = New-Object System.Net.NetworkCredential($FTPUser, $FTPPassword)
	
    $FTPRequest = [System.Net.WebRequest]::Create($FTPServer)
	$FTPRequest.Credentials = $Credentials
    $FTPRequest.Method = $Method
	
	try
	{
		$FTPResponse = $FTPRequest.GetResponse()
		$reader = $FTPResponse.GetResponseStream()

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
	catch [Exception]
	{
		"$($_.Exception.ToString()). $($_.InvocationInfo.PositionMessage)" >> $LogFile
	}
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
if ($NoCheckout -eq $false)
{
    Checkout-SVN -RemoteRepositoryUrl $SVNRepository -LocalPath $LocalPath
}

Build-Project -ProjectPath $LocalPath -OutputDirectory $PublishPath -ExcludeConfigurationFiles -Publish $Publish

if ($FTPDeploy -eq $true)
{
	

	if ($FTPFolderName -eq "" ) 
	{
	    $FTPFolderName = (dir $PublishPath | Select-Object -First 1).Name
	}

	[bool] $DirectoryExists = (Get-FTPItem $FtpUri -DirectoriesOnly) -contains $FTPFolderName

	$FtpUri += "/" + $FTPFolderName + "/"

	if ($DirectoryExists -eq $true)
	{
		Send-FTPItem -FTPServer $($FtpUri + $AppOfflineFile.Name) -File $AppOfflineFile.FullName
	}
	else
	{
		New-FTPItem $FtpUri
	}
	
	$testfullname = (dir $PublishPath | Select-Object -First 1).Fullname
	Send-FTPFolder -FTPServer $FtpUri -LocalFolder $testfullname
	
	if ($DirectoryExists -eq $true)
	{
		Remove-FTPItem -FTPServer $($FtpUri + $AppOfflineFile.Name)
	}
}