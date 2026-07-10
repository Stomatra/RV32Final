param(
    [string]$RepoRoot = "."
)

$ErrorActionPreference = 'Stop'
Set-Location $RepoRoot

function Get-WordsFromMem([string]$path) {
    $raw = Get-Content $path
    return ($raw | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[0-9a-fA-F]{1,8}$' } | ForEach-Object { $_.ToLowerInvariant() })
}

function Get-WordsFromCoe([string]$path) {
    $raw = Get-Content $path -Raw
    $m = [regex]::Match($raw, 'memory_initialization_vector\s*=\s*(.+?);', 'Singleline,IgnoreCase')
    if(-not $m.Success) { throw "Invalid COE: $path" }
    return ($m.Groups[1].Value -split '[,\s]+' | Where-Object { $_ -match '^[0-9a-fA-F]+$' } | ForEach-Object { $_.PadLeft(8,'0').ToLowerInvariant() })
}

function Hash-Words([string[]]$words) {
    $joined = ($words -join "`n")
    $bytes = [Text.Encoding]::ASCII.GetBytes($joined)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
    } finally {
        $sha.Dispose()
    }
}

function Show-Image([string]$name, [string]$path, [string[]]$words) {
    $first = $words | Select-Object -First 32
    Write-Output "=== $name ==="
    Write-Output "Path: $path"
    Write-Output ("WordCount: {0}" -f $words.Count)
    Write-Output ("SHA256(all words): {0}" -f (Hash-Words $words))
    Write-Output "First32Words:"
    for($i=0; $i -lt $first.Count; $i++) {
        Write-Output ("  [{0:D2}] {1}" -f $i, $first[$i])
    }
    Write-Output ""
}

$iromXci = "digital_twin.srcs/sources_1/ip/IROM/IROM.xci"
$dramXci = "digital_twin.srcs/sources_1/ip/DRAM/DRAM.xci"

$iromCoeffRel = (Get-Content $iromXci -Raw | ConvertFrom-Json).ip_inst.parameters.component_parameters.coefficient_file[0].value
$dramCoeffRel = (Get-Content $dramXci -Raw | ConvertFrom-Json).ip_inst.parameters.component_parameters.coefficient_file[0].value

$iromCoeffAbs = (Resolve-Path (Join-Path "digital_twin.srcs/sources_1/ip/IROM" $iromCoeffRel)).Path
$dramCoeffAbs = (Resolve-Path (Join-Path "digital_twin.srcs/sources_1/ip/DRAM" $dramCoeffRel)).Path

$images = @(
    @{name='generated/irom.mem'; path='digital_twin.srcs/sim_iverilog/build/generated/irom.mem'; type='mem'},
    @{name='generated/dram.mem'; path='digital_twin.srcs/sim_iverilog/build/generated/dram.mem'; type='mem'},
    @{name='Vivado IROM IP irom.coe'; path=$iromCoeffAbs; type='coe'},
    @{name='Vivado DRAM IP dram.coe'; path=$dramCoeffAbs; type='coe'}
)

foreach($img in $images) {
    $p = (Resolve-Path $img.path).Path
    $w = if($img.type -eq 'mem') { Get-WordsFromMem $p } else { Get-WordsFromCoe $p }
    Show-Image $img.name $p $w
}
