param (
  [Parameter(Mandatory=$true)]$Inputs
)

$CredentialsList = @{"JohnDoe"="blabla";"WalterWhite"="CrystalMeth";"DexterMorgan"="SliceOfLife"}

function MAA-ConvertTo-Base64([string]$data)
{
    $temp = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($data))
    $temp = $temp -replace '=',''
    
    return $temp
}
function MAA-JWT-EncodeSignature([string]$data,[string]$secret)
{
    # Powershell HMAC SHA 256
    $hmacsha = New-Object System.Security.Cryptography.HMACSHA256
    $hmacsha.key = [Text.Encoding]::ASCII.GetBytes($secret)
    $signature = $hmacsha.ComputeHash([Text.Encoding]::ASCII.GetBytes($data))
    $signature = [Convert]::ToBase64String($signature)
    $signature = $signature -replace '=',''

    return $signature
}

$ErrorActionPreference = 'stop'
try
{
  switch -regex ($Inputs.url)
  {
    "/connect"
    {
      if ($CredentialsList.$($Inputs.body.username) -eq $Inputs.body.password)  #Credentials validation
      {
        $ExpirationDate = (Get-Date).AddHours(4)
        $JSONheader = '{"alg":"HS256","typ":"JWT"}'
        $JSONpayload = '{"APIVersion":"1.0.0","username":"'+$Inputs.body.username+'","expiration-date":"'+$ExpirationDate+'"}'
        $JWTHeader = MAA-ConvertTo-Base64 $JSONheader
        $JWTPayload = MAA-ConvertTo-Base64 $JSONpayload
        $JWTHeaderandPayload = $JWTHeader + "." + $JWTpayload
        $JWTtoken = $JWTHeaderandPayload + "." + (MAA-JWT-EncodeSignature $JWTHeaderandPayload "secret")

        $Content = [PSCustomObject]@{
          Token = $JWTtoken
          APIVersion = "1.0.0"
          Username = $inputs.body.username
          ExpirationDate = $ExpirationDate
        }

        $result = [PSCustomObject]@{
          ReturnCode = [Int][System.Net.HttpStatusCode]::OK
          Content = $Content | ConvertTo-JSON
        }
      }
      else
      {
        $result = [PSCustomObject]@{
          ReturnCode = [Int][System.Net.HttpStatusCode]::Unauthorized
          Content = "Authentication has failed"
        }
      }
    }

    default
    {
      $result = [PSCustomObject]@{
        ReturnCode = [Int][System.Net.HttpStatusCode]::NotFound
        Content = "This endpoint is not managed by this API version"
      }
    }
  }
}
catch
{
  $result = [PSCustomObject]@{
    ReturnCode = [Int][System.Net.HttpStatusCode]::InternalServerError
    Content = "Error while processing"
  }
}

return $result
