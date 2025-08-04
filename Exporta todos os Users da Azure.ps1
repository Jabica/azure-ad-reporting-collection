# ===========================================
# Script: Export-Users.ps1
# Descrição: Conecta ao Microsoft Graph e exporta todos os usuários
# Saída: users_list.csv (DisplayName, UserPrincipalName e Prefixo)
# Compatível: PowerShell 5+, Core (Windows/macOS/Linux)
# ===========================================

# 1) Conecta ao Graph (precisa de User.Read.All)
Connect-MgGraph -Scopes "User.Read.All"

# 2) Coleta DisplayName e UPN
Write-Host "🔄 Coletando usuários..." -ForegroundColor Cyan
$users = Get-MgUser -All | Select-Object DisplayName, UserPrincipalName

# 3) Extrai prefixo antes do “@” e monta objeto
$data = $users | ForEach-Object {
    [PSCustomObject]@{
        DisplayName        = $_.DisplayName
        UserPrincipalName  = $_.UserPrincipalName
        Prefixo            = ($_.UserPrincipalName.Split("@")[0]).ToLower()
    }
}

# 4) Exporta para CSV no mesmo diretório do script
$exportPath = Join-Path -Path $PSScriptRoot -ChildPath "users_list.csv"
$data | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8

Write-Host "`n✅ Export concluído: $exportPath" -ForegroundColor Green