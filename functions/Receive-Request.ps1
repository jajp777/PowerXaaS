Function Receive-Request
{
  param (
    [Parameter(Mandatory=$true)]$RequestId,
    [Parameter(Mandatory=$true)]$Context
  )

  ### INITIALIZE ###
  $Request = $Context.Request
  $Response = $Context.Response
  $StreamData = $null
  $Body = $null
  $Authorized = $false
  $Malformed = $false

  ### PROCESS REQUEST ###
  Write-Log -Status "Information" -Context "Process $RequestId" -Description "Getting request details"
  Write-Log -Status "Information" -Context "Process $RequestId" -Description "Local path is $($Request.Url.LocalPath)"
  Write-Log -Status "Information" -Context "Process $RequestId" -Description "HTTP method is $($Request.HttpMethod)"
  Write-Log -Status "Information" -Context "Process $RequestId" -Description "Host name is $($Request.UserHostName)"
  Write-Log -Status "Information" -Context "Process $RequestId" -Description "User agent is $($Request.UserAgent)"
  foreach ($key in $Request.headers.AllKeys)
  {
    Write-Log -Status "Information" -Context "Process $RequestId" -Description "$key`: $($Request.headers.GetValues($key))"
  }

  #Read body
  $StreamReader = New-Object System.IO.StreamReader $request.InputStream
  $StreamData = $StreamReader.ReadToEnd()
  if ($StreamData)
  {
    try
    {
      $Body = $StreamData | ConvertFrom-Json
      Write-Log -Status "Information" -Context "Process $RequestId" -Description "Body is $($body -replace '(?<begin>[\;\{\s]password=)(?<pass>.*)(?<end>[\;\}])','${begin}********${end}')"
    }
    catch
    {
      #Prevent from malformed JSON files
      Write-Log -Status "Error" -Context "Process $RequestId" -Description "$StreamData is not a valid JSON file"
      $Malformed = $true
    }
  }
  if ($Malformed)
  {
    $Result = [PSCustomObject]@{
      ReturnCode = [Int][System.Net.HttpStatusCode]::BadRequest
      Content = "Provided body is not a valid JSON file"
    }
  }
  else
  {
    #Read config and get action
    Write-Log -Status "Information" -Context "Process $RequestId" -Description "Ready to process request"
    $Endpoint = ($Request.url.localpath.substring(1) -replace 'api/v\d*','')
    $Method = $Request.httpmethod
    Write-Log -Status "Information" -Context "Process $RequestId" -Description "Reading configuration file"
    $Config = Get-Content .\PowerXaaS.conf | ConvertFrom-Json
    $AllEndpoints = $Config.features | select -ExpandProperty endpoints -Property @{Label="feature";Expression={$_.Name}}, active | where {$_.Active -eq 'yes'}
    $Feature = ($AllEndpoints | where {($Method -eq $_.Method) -and ($Endpoint -match ("^$($_.url)$".replace("{","(?<").replace("}", ">.*)")).substring(1))} | Select-Object -First 1).feature
    $Parameters = ([PSCustomObject]$Matches)
      
    if ($Feature)
    {
      Write-Log -Status "Information" -Context "Process $RequestId" -Description "Matching feature: $feature"
      #Check authorization
      if ($Request.headers.GetValues("Authorization") -eq $null)
      {
        if ($Endpoint -eq '/connect')
        {
          $Authorized = "Granted"
        }
        else
        {
          $Authorized = "NotAuthenticated"
        }
      }
      else
      {
        $Token = $Request.headers.GetValues("Authorization").split(' ')[1]
        $Authorized = Request-Authorization -Token $Token -Feature $Feature -Endpoint $Endpoint -Method $Method
      }

      switch ($Authorized)
      {
        "Granted"
        {
          Write-Log -Status "Information" -Context "Process $RequestId" -Description "Authorization granted"
          $Folder = ".\$($Request.Url.Segments[1].substring(0,$Request.Url.Segments[1].length-1))\$($Request.Url.Segments[2].substring(0,$Request.Url.Segments[2].length-1))"
          $Script = "$Folder\$Feature.ps1"
          $Parameters.PSObject.Properties.Remove('0')
          $Inputs = [PSCustomObject]@{
            URL = $($Request.url.localpath.substring(1) -replace 'api/v\d*','')
            Method = $($Request.httpmethod)
            Body = $Body
            Parameters = $Parameters
          }
        
          #Run action
          Write-Log -Status "Information" -Context "Process $RequestId" -Description "Calling - $Script"
          try
          {
            $Result = & "$Script" $Inputs
          }
          catch
          {
            Write-Log -Status "Error" -Context "Feature" -Description "Internal server error"
            $Result = [PSCustomObject]@{
              ReturnCode = [Int][System.Net.HttpStatusCode]::InternalServerError
              Content = "Error while processing $Script"
            }
          }
        }
        "Denied"
        {
          Write-Log -Status "Error" -Context "Process $RequestId" -Description "Authorization denied"
          $Result = [PSCustomObject]@{
            ReturnCode = [Int][System.Net.HttpStatusCode]::Forbidden
            Content = 'Authorization denied'
          }
        }
        "Expired"
        {
          Write-Log -Status "Error" -Context "Process $RequestId" -Description "Token expired"
          $Result = [PSCustomObject]@{
            ReturnCode = [Int][System.Net.HttpStatusCode]::Unauthorized
            Content = 'Token expired'
          }
        }
        "NotAuthenticated"
        {
          Write-Log -Status "Error" -Context "Process $RequestId" -Description "Not authenticated"
          $Result = [PSCustomObject]@{
            ReturnCode = [Int][System.Net.HttpStatusCode]::Unauthorized
            Content = 'Not authenticated'
          }
        }
        default
        {
        }
      }
    }
    else
    {
      #Endpoint not found
      Write-Log -Status "Error" -Context "Process $RequestId" -Description "Endpoint not found"
      $Result = [PSCustomObject]@{
        ReturnCode = [Int][System.Net.HttpStatusCode]::NotFound
        Content = "Endpoint not found"
      }
    }
  }
        
  if ($Result.ReturnCode -notmatch "\d\d\d")
  {
    Write-Log -Status "Error" -Context "Feature" -Description "Invalid return code"
    $Result = [PSCustomObject]@{
      ReturnCode = [Int][System.Net.HttpStatusCode]::InternalServerError
      Content = "Invalid return code"
    }
  }
  Write-Log -Status "Information" -Context "Process $RequestId" -Description "Request processed"

  ### SEND RESPONSE ###    
  Write-Log -Status "Information" -Context "Process $RequestId" -Description "Return code is $($Result.ReturnCode)"
  $Response.statuscode = $Result.ReturnCode
  if ($Result.Content)
  {
    Write-Log -Status "Information" -Context "Process $RequestId" -Description "Content is $($Result.Content)"
    $Buffer = [Text.Encoding]::UTF8.GetBytes($Result.Content)
    $Response.AddHeader("Access-Control-Allow-Origin","*")
    $Response.AddHeader("Access-Control-Allow-Methods","GET,POST,PUT,DELETE")
    $Response.AddHeader("Access-Control-Allow-Headers","X-Requested-With")
    $Response.AddHeader("Access-Control-Max-Age","86400")
    $Response.ContentType = 'application/json'
    $Response.ContentLength64 = $Buffer.length
    $Response.OutputStream.Write($Buffer, 0, $Buffer.length)
  }
  else
  {
    Write-Log -Status "Information" -Context "Process $RequestId" -Description "No content to send back"
  }
  $Response.Close()
}
