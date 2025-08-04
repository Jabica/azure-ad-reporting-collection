# Conecte-se ao Microsoft Graph (caso ainda não esteja)
Connect-MgGraph -Scopes "User.Read.All"

# Força busca de todos os usuários
$users = Get-MgUser -All | Select-Object UserPrincipalName

# Lista total de usuários carregados
Write-Host "Total de usuários encontrados: $($users.Count)" -ForegroundColor Cyan

# Agrupa por prefixo do e-mail (parte antes do @)
$prefixGroups = $users | Group-Object {
    ($_.UserPrincipalName).Split("@")[0].ToLower()
}

# Cria um array para salvar os resultados
$result = @()

foreach ($group in $prefixGroups) {
    $domains = $group.Group.UserPrincipalName | ForEach-Object {
        ($_.Split("@")[1]).ToLower()
    } | Sort-Object -Unique

    if ($domains.Count -gt 1) {
        $result += [PSCustomObject]@{
            Prefixo      = $group.Name
            Dominios     = ($domains -join ", ")
            Enderecos    = ($group.Group.UserPrincipalName -join "; ")
        }

        # Exibe no console também
        Write-Host "`nPrefixo duplicado encontrado: $($group.Name)" -ForegroundColor Yellow
        $group.Group.UserPrincipalName | ForEach-Object { Write-Host " - $_" }
    }
}

# Exporta em CSV para facilitar análise
if ($result.Count -gt 0) {
    $result | Export-Csv -Path ".\usuarios_com_mesmo_nome_dominios_diferentes.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "`nExportado para usuarios_com_mesmo_nome_dominios_diferentes.csv" -ForegroundColor Green
} else {
    Write-Host "Nenhum prefixo com domínios diferentes foi encontrado." -ForegroundColor Gray
}