# ===========================================
# Script: Export-Users.ps1
# Descrição: Conecta ao Microsoft Graph e exporta todos os usuários
# Saída: users_list.csv (DisplayName, UserPrincipalName, Prefixo e MFAStatus)
# Compatível: PowerShell 5+, Core (Windows/macOS/Linux)
# ===========================================

param(
    [switch]$UseDeviceCode
)

$ErrorActionPreference = "Stop"

# 1) Conecta ao Graph
# Obs: para puxar MFAStatus via relatório (userRegistrationDetails), normalmente é necessário consent/admin role.
$scopes = @(
    "User.Read.All",
    "AuditLog.Read.All",
    "UserAuthenticationMethod.Read.All"
)
try {
    $connectParams = @{
        Scopes    = $scopes
        NoWelcome = $true
    }
    if ($UseDeviceCode) {
        $connectParams["UseDeviceCode"] = $true
    }

    Connect-MgGraph @connectParams | Out-Null
}
catch {
    Write-Error ("Falha ao autenticar no Microsoft Graph. Erro: {0}" -f $_.Exception.Message)
    exit 1
}

function Get-MfaStatusViaAuthMethods {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserId
    )

    try {
        $resp = Invoke-MgGraphRequest `
            -Method GET `
            -Uri ("https://graph.microsoft.com/v1.0/users/{0}/authentication/methods" -f $UserId) `
            -ErrorAction Stop

        $methods = @($resp.value)
        if ($methods.Count -eq 0) {
            return "NotRegistered"
        }

        $nonPassword = $methods | Where-Object {
            $_.'@odata.type' -and $_.'@odata.type' -ne "#microsoft.graph.passwordAuthenticationMethod"
        }

        if (@($nonPassword).Count -gt 0) {
            return "Registered"
        }

        return "NotRegistered"
    }
    catch {
        if (-not $script:AuthMethodsWarned) {
            $script:AuthMethodsWarned = $true
            Write-Warning ("Falha ao consultar /users/{id}/authentication/methods para calcular MFAStatus. " +
                "Se o resultado ficar Unknown, normalmente falta consent/admin para o scope UserAuthenticationMethod.Read.All. " +
                "Exemplo de erro: {0}" -f $_.Exception.Message)
        }
        return "Unknown"
    }
}

# 2) Coleta usuários (com Id para correlacionar com o relatório de MFA)
Write-Host "🔄 Coletando usuários..." -ForegroundColor Cyan
$users = Get-MgUser -All -Property Id,DisplayName,UserPrincipalName,Mail |
    Select-Object Id,DisplayName,UserPrincipalName,Mail

# 3) Coleta relatório de registro de métodos de autenticação (MFA)
Write-Host "🔄 Coletando MFA status (userRegistrationDetails)..." -ForegroundColor Cyan
$registrationByKey = @{}
$registrationReportOk = $true

try {
    $registrationDetails = Get-MgReportAuthenticationMethodUserRegistrationDetail -All -ErrorAction Stop
    foreach ($row in $registrationDetails) {
        if ($row.PSObject.Properties.Name -contains "UserId" -and $row.UserId) {
            $registrationByKey[$row.UserId] = $row
        }
        if ($row.Id) {
            $registrationByKey[$row.Id] = $row
        }
        if ($row.PSObject.Properties.Name -contains "UserPrincipalName" -and $row.UserPrincipalName) {
            $registrationByKey[$row.UserPrincipalName] = $row
        }
    }
}
catch {
    $registrationReportOk = $false
    $msg = $_.Exception.Message
    if ($msg -match "Authentication_RequestFromUnsupportedUserRole" -or ($msg -match "User is not in the allowed roles")) {
        Write-Warning ("Nao foi possivel ler userRegistrationDetails (403: User is not in the allowed roles). " +
            "Para consultar esse relatorio, sua conta precisa ter uma destas roles no tenant: " +
            "Reports Reader, Security Reader, Security Administrator, ou Global Reader. " +
            "Vou tentar calcular MFAStatus via /users/{id}/authentication/methods (mais lento).")
    }
    else {
        Write-Warning ("Nao foi possivel ler userRegistrationDetails; MFAStatus ficara como Unknown. Erro: {0}" -f $msg)
    }
}

# 4) Extrai prefixo antes do “@” e monta objeto
$total = @($users).Count
$idx = 0
$data = $users | ForEach-Object {
    $idx++
    if ($idx % 50 -eq 0 -or $idx -eq 1 -or $idx -eq $total) {
        Write-Progress -Activity "Exportando usuários com MFAStatus" -Status "$idx / $total" -PercentComplete ([math]::Round(($idx / [math]::Max($total, 1)) * 100))
    }

    $registration = $registrationByKey[$_.Id]
    if ($null -eq $registration -and $_.UserPrincipalName) {
        $registration = $registrationByKey[$_.UserPrincipalName]
    }

    $mfaStatus = if (-not $registrationReportOk) {
        Get-MfaStatusViaAuthMethods -UserId $_.Id
    }
    elseif ($null -eq $registration) {
        Get-MfaStatusViaAuthMethods -UserId $_.Id
    }
    elseif ($registration.IsMfaRegistered) {
        "Registered"
    }
    else {
        "NotRegistered"
    }

    $email = if ([string]::IsNullOrWhiteSpace($_.Mail)) { $_.UserPrincipalName } else { $_.Mail }

    [PSCustomObject]@{
        DisplayName        = $_.DisplayName
        Email              = $email
        UserPrincipalName  = $_.UserPrincipalName
        Prefixo            = ($_.UserPrincipalName.Split("@")[0]).ToLower()
        MFAStatus          = $mfaStatus
    }
}

# limpa barra
Write-Progress -Activity "Exportando usuários com MFAStatus" -Completed

# 5) Exporta para CSV no mesmo diretório do script
$exportPath = Join-Path -Path $PSScriptRoot -ChildPath "users_list.csv"
$data | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8

# CSV “enxuto” (só o que você pediu: DisplayName, Email, MFAStatus)
$exportMfaPath = Join-Path -Path $PSScriptRoot -ChildPath "users_mfa.csv"
$data |
    Select-Object DisplayName,Email,MFAStatus |
    Export-Csv -Path $exportMfaPath -NoTypeInformation -Encoding UTF8

Write-Host "`n✅ Export concluído: $exportPath" -ForegroundColor Green
Write-Host "✅ Export MFA (enxuto): $exportMfaPath" -ForegroundColor Green

Disconnect-MgGraph | Out-Null
