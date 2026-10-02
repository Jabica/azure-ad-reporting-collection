[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$InputPath = (Join-Path $PSScriptRoot "departamentos_ma111.csv"),
    [string]$OutputPath = (Join-Path $PSScriptRoot "departamento_update_result.csv"),
    [string]$TenantId,
    [switch]$UseDeviceCode
)

$ErrorActionPreference = "Stop"

function Import-DepartmentUpdates {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Arquivo nao encontrado: $Path"
    }

    $firstLine = Get-Content -LiteralPath $Path -TotalCount 1 -ErrorAction Stop
    $delimiter = if ($firstLine -match "`t") { "`t" } else { "," }
    $rows = @(Import-Csv -LiteralPath $Path -Delimiter $delimiter)

    if ($rows.Count -eq 0) {
        throw "Arquivo sem registros: $Path"
    }

    $requiredColumns = @("DisplayName", "UserPrincipalName", "Id", "Department")
    $availableColumns = @($rows[0].PSObject.Properties.Name)

    foreach ($column in $requiredColumns) {
        if ($availableColumns -notcontains $column) {
            throw "Coluna obrigatoria ausente: $column"
        }
    }

    return $rows
}

$rows = Import-DepartmentUpdates -Path $InputPath

$connectParams = @{
    Scopes    = @("User.ReadWrite.All")
    NoWelcome = $true
}

if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
    $connectParams["TenantId"] = $TenantId
}

if ($UseDeviceCode) {
    $connectParams["UseDeviceCode"] = $true
}

Connect-MgGraph @connectParams | Out-Null

$results = New-Object System.Collections.Generic.List[object]
$total = $rows.Count
$index = 0

try {
    foreach ($row in $rows) {
        $index++
        $percent = [math]::Round(($index / [math]::Max($total, 1)) * 100, 0)

        Write-Progress `
            -Activity "Atualizando department no Entra ID" `
            -Status "$index / $total" `
            -PercentComplete $percent

        $displayName = [string]$row.DisplayName
        $userPrincipalName = [string]$row.UserPrincipalName
        $userId = [string]$row.Id
        $targetDepartment = [string]$row.Department

        if ([string]::IsNullOrWhiteSpace($userId) -or [string]::IsNullOrWhiteSpace($targetDepartment)) {
            $results.Add([PSCustomObject]@{
                DisplayName          = $displayName
                UserPrincipalName    = $userPrincipalName
                Id                   = $userId
                PreviousDepartment   = $null
                TargetDepartment     = $targetDepartment
                Status               = "InvalidInput"
                Message              = "Id ou Department vazio"
            })
            continue
        }

        try {
            $currentUser = Get-MgUser -UserId $userId -Property Id,DisplayName,UserPrincipalName,Department -ErrorAction Stop
            $currentDepartment = [string]$currentUser.Department
            $resolvedName = if ([string]::IsNullOrWhiteSpace($currentUser.DisplayName)) { $displayName } else { $currentUser.DisplayName }
            $resolvedUpn = if ([string]::IsNullOrWhiteSpace($currentUser.UserPrincipalName)) { $userPrincipalName } else { $currentUser.UserPrincipalName }

            if ($currentDepartment -eq $targetDepartment) {
                $results.Add([PSCustomObject]@{
                    DisplayName          = $resolvedName
                    UserPrincipalName    = $resolvedUpn
                    Id                   = $userId
                    PreviousDepartment   = $currentDepartment
                    TargetDepartment     = $targetDepartment
                    Status               = "SkippedAlreadySet"
                    Message              = "Department ja esta correto"
                })
                continue
            }

            $targetDescription = "{0} <{1}> :: '{2}' -> '{3}'" -f $resolvedName, $resolvedUpn, $currentDepartment, $targetDepartment

            if ($PSCmdlet.ShouldProcess($targetDescription, "Update-MgUser -Department")) {
                Update-MgUser -UserId $userId -Department $targetDepartment -ErrorAction Stop | Out-Null
                $status = "Updated"
                $message = "Department atualizado"
            }
            else {
                $status = "WhatIf"
                $message = "Somente simulacao"
            }

            $results.Add([PSCustomObject]@{
                DisplayName          = $resolvedName
                UserPrincipalName    = $resolvedUpn
                Id                   = $userId
                PreviousDepartment   = $currentDepartment
                TargetDepartment     = $targetDepartment
                Status               = $status
                Message              = $message
            })
        }
        catch {
            $results.Add([PSCustomObject]@{
                DisplayName          = $displayName
                UserPrincipalName    = $userPrincipalName
                Id                   = $userId
                PreviousDepartment   = $null
                TargetDepartment     = $targetDepartment
                Status               = "Failed"
                Message              = $_.Exception.Message
            })
        }
    }
}
finally {
    Write-Progress -Activity "Atualizando department no Entra ID" -Completed
    Disconnect-MgGraph | Out-Null
}

$results | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8

$summary = $results |
    Group-Object -Property Status |
    Sort-Object -Property Name |
    ForEach-Object { "{0}: {1}" -f $_.Name, $_.Count }

Write-Host ""
Write-Host ("Arquivo de entrada : {0}" -f $InputPath) -ForegroundColor Cyan
Write-Host ("Arquivo de saida   : {0}" -f $OutputPath) -ForegroundColor Cyan
Write-Host ("Registros lidos    : {0}" -f $rows.Count) -ForegroundColor Cyan
Write-Host ("Resumo             : {0}" -f ($summary -join " | ")) -ForegroundColor Green
