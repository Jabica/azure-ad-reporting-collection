# ===========================================
# Script: Validate-Similarity.ps1
# Descrição: Lê users_list.csv e detecta pares com prefixo ou DisplayName semelhantes
#            Exibe barra de progresso durante a execução.
# Saída: usuarios_similares.csv
# ===========================================

param(
    [int]$Threshold = 85    # limiar mínimo de similaridade (%)
)

# 1) Função Levenshtein (retorna % de similaridade)
function Get-Similarity {
    param (
        [string]$s1,
        [string]$s2
    )
    $s1 = $s1.ToLower()
    $s2 = $s2.ToLower()
    $len1 = $s1.Length
    $len2 = $s2.Length

    # cria matriz 2D
    $matrix = @()
    for ($i = 0; $i -le $len1; $i++) {
        $row = @()
        for ($j = 0; $j -le $len2; $j++) { $row += 0 }
        $matrix += ,$row
    }

    for ($i = 0; $i -le $len1; $i++) { $matrix[$i][0] = $i }
    for ($j = 0; $j -le $len2; $j++) { $matrix[0][$j] = $j }

    for ($i = 1; $i -le $len1; $i++) {
        for ($j = 1; $j -le $len2; $j++) {
            $cost = if ($s1[$i-1] -eq $s2[$j-1]) { 0 } else { 1 }
            $del = $matrix[$i-1][$j] + 1
            $ins = $matrix[$i][$j-1] + 1
            $sub = $matrix[$i-1][$j-1] + $cost
            $matrix[$i][$j] = [Math]::Min($del, [Math]::Min($ins, $sub))
        }
    }

    $distance = $matrix[$len1][$len2]
    $maxLen = [Math]::Max($len1, $len2)
    if ($maxLen -eq 0) { return 100 }
    return [Math]::Round((1 - $distance/$maxLen) * 100)
}

# 2) Carrega lista exportada
$inputPath = Join-Path $PSScriptRoot "users_list.csv"
if (-Not (Test-Path $inputPath)) {
    Write-Error "Arquivo não encontrado: $inputPath"
    exit 1
}
$lista = Import-Csv -Path $inputPath

# 3) Pré-cálculo para barra de progresso
$totalUsers   = $lista.Count
$totalPairs   = [int]($totalUsers * ($totalUsers - 1) / 2)
$counter      = 0

Write-Host "🔍 Comparando $totalUsers usuários ($totalPairs pares) com threshold de $Threshold%..." -ForegroundColor Cyan

# 4) Compara pares e atualiza a barra
$result = @()
for ($i = 0; $i -lt $totalUsers; $i++) {
    for ($j = $i + 1; $j -lt $totalUsers; $j++) {
        $counter++
        $percent = [Math]::Round(($counter / $totalPairs) * 100)
        Write-Progress `
          -Activity "Validando similaridade de usuários" `
          -Status "Processando par $counter de $totalPairs" `
          -PercentComplete $percent

        # calcula similaridade
        $simPref = Get-Similarity -s1 $lista[$i].Prefixo -s2 $lista[$j].Prefixo
        $simName = Get-Similarity -s1 $lista[$i].DisplayName -s2 $lista[$j].DisplayName

        if ($simPref -ge $Threshold -or $simName -ge $Threshold) {
            $result += [PSCustomObject]@{
                Nome1                 = $lista[$i].DisplayName
                Email1                = $lista[$i].UserPrincipalName
                Nome2                 = $lista[$j].DisplayName
                Email2                = $lista[$j].UserPrincipalName
                Similaridade_Prefixo  = "$simPref%"
                Similaridade_Nome     = "$simName%"
            }
        }
    }
}

# limpa barra
Write-Progress -Activity "Validando similaridade de usuários" -Completed

# 5) Exporta resultado
$outPath = Join-Path $PSScriptRoot "usuarios_similares.csv"
$result | Export-Csv -Path $outPath -NoTypeInformation -Encoding UTF8

# 6) Feedback final
if ($result.Count -gt 0) {
    Write-Host "`n✅ Encontrados $($result.Count) pares semelhantes." -ForegroundColor Green
    Write-Host "Relatório: $outPath" -ForegroundColor Green
} else {
    Write-Host "`nℹ️ Nenhum par acima de $Threshold%." -ForegroundColor Yellow
}