Param(
  [string]$OutDir = $(Join-Path $PSScriptRoot "..\geojson\areas_v3\bound"),
  [int]$MaxRetries = 3,
  [int]$RetryDelaySeconds = 2
)

$ErrorActionPreference = "Stop"

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

function Download-Json([string]$Url, [string]$DestPath) {
  if (Test-Path -LiteralPath $DestPath) {
    return
  }

  for ($i = 1; $i -le $MaxRetries; $i++) {
    try {
      Write-Host "Downloading $Url"
      Invoke-WebRequest -Uri $Url -OutFile $DestPath -UseBasicParsing
      return
    } catch {
      # 某些 adcode 在源站不存在（常见返回：404 或 NoSuchKey），这种情况直接跳过即可
      $msg = $_.Exception.Message
      if ($msg -match "NoSuchKey" -or $msg -match "404") {
        Write-Warning "Skip (not found): $Url"
        return
      }
      if ($i -eq $MaxRetries) { throw }
      Start-Sleep -Seconds $RetryDelaySeconds
    }
  }
}

Ensure-Dir $OutDir

$BaseUrl = "https://geo.datav.aliyun.com/areas_v3/bound"

# 先下载全国底图（用于替代 china.js 作为统一底图，减少省份标签偏移）
Download-Json -Url "$BaseUrl/100000_full.json" -DestPath (Join-Path $OutDir "100000_full.json")
# 台湾 full 数据源不存在，补充下载非 full 版本用于下钻兜底
Download-Json -Url "$BaseUrl/710000.json" -DestPath (Join-Path $OutDir "710000.json")

# 与 platform_K.html 保持一致的省份 adcode 映射
$ProvinceAdcodes = [ordered]@{
  "北京"="110000"; "天津"="120000"; "河北"="130000"; "山西"="140000"; "内蒙古"="150000";
  "辽宁"="210000"; "吉林"="220000"; "黑龙江"="230000";
  "上海"="310000"; "江苏"="320000"; "浙江"="330000"; "安徽"="340000"; "福建"="350000"; "江西"="360000"; "山东"="370000";
  "河南"="410000"; "湖北"="420000"; "湖南"="430000"; "广东"="440000"; "广西"="450000"; "海南"="460000";
  "重庆"="500000"; "四川"="510000"; "贵州"="520000"; "云南"="530000"; "西藏"="540000";
  "陕西"="610000"; "甘肃"="620000"; "青海"="630000"; "宁夏"="640000"; "新疆"="650000";
  "台湾"="710000"; "香港"="810000"; "澳门"="820000"
}

# 这些省级行政区在页面里会直接下钻到区县，不需要再下载其“地级市”文件
$DirectMunicipalities = @("北京","天津","上海","重庆","香港","澳门","台湾")

foreach ($provName in $ProvinceAdcodes.Keys) {
  $provAdcode = $ProvinceAdcodes[$provName]
  $provFile = "${provAdcode}_full.json"
  $provDest = Join-Path $OutDir $provFile
  $provUrl = "$BaseUrl/$provFile"

  Download-Json -Url $provUrl -DestPath $provDest

  if ($DirectMunicipalities -contains $provName) {
    continue
  }

  # 从省级 GeoJSON 中提取下一级 adcode（PowerShell 5.x 兼容：不用 ConvertFrom-Json -Depth）
  # 直接在文本中匹配："adcode": 123456
  $provJsonText = Get-Content -LiteralPath $provDest -Raw -Encoding UTF8
  $childAdcodes = New-Object System.Collections.Generic.HashSet[string]
  $matches = [regex]::Matches($provJsonText, '"adcode"\s*:\s*"?(\d{6})"?')
  foreach ($m in $matches) {
    $code = $m.Groups[1].Value
    if ($code -and $code.Length -eq 6) {
      $childAdcodes.Add($code) | Out-Null
    }
  }

  foreach ($cityAdcode in $childAdcodes) {
    $cityFile = "${cityAdcode}_full.json"
    $cityDest = Join-Path $OutDir $cityFile
    $cityUrl = "$BaseUrl/$cityFile"
    Download-Json -Url $cityUrl -DestPath $cityDest
  }
}

Write-Host ""
Write-Host "Done."
Write-Host "GeoJSON saved to: $OutDir"
