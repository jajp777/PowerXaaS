
I choose JSON web tokens as the way to manage authentication with PowerXaas.

### /connect endpoint

There is a special endpoint for authenticating : /connect.

You must call it that way :

    $Body = '{"Username":"<yourname>","password":"<yourpassword>"}'
    $Result = Invoke-WebRequest -Uri https://<ipaddress>:<port>/connect -Method POST -Body $Body
    $Result.Content | ConvertFrom-JSON


### Token and headers

The object it returns contains a token, the API version, the username and an expiration date.

The token will then be used until expiration date to authenticate by placing it in the headers of next requests :

    $Token = ($Result.Content | ConvertFrom-JSON).Token
    $Headers = @{"Authorization" = "Bearer " + $Token}
    $Result = Invoke-WebRequest -Uri https://<ipaddress>:<port>/version -Method GET -Headers $Headers

You will also probably need that code before :

    add-type @"
      using System.Net;
      using System.Security.Cryptography.X509Certificates;
      public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
          ServicePoint srvPoint, X509Certificate certificate,
          WebRequest request, int certificateProblem) {
            return true;
          }
      }
    "@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy


### Authentication and authorization management scripts

There are 2 scripts designed to manage authentication and authorization : `connect.ps1` and `Request-Authorization.ps1`

`Connect.ps1` is part of the API since it is an endpoint exposed to clients. This is the one used for authentication. You may need to update it your own way to match your needs.

`Request-Authorization.ps1` is used to manage authorizations. You also may need to update it your own way to match your needs.

I Hope I will be able to propose a more mature solution for next releases of PowerXaaS.
