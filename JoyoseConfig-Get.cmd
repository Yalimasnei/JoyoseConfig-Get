@echo off
setlocal
set "JOYOSE_TEG_SELF=%~f0"
set "JOYOSE_TEG_TMP_DIR=%~dp0JoyoseConfig-tmp"
if not exist "%JOYOSE_TEG_TMP_DIR%" mkdir "%JOYOSE_TEG_TMP_DIR%"
set "JOYOSE_TEG_TMP=%JOYOSE_TEG_TMP_DIR%\joyose_teg_%RANDOM%_%RANDOM%.ps1"
set "JOYOSE_TEG_KEEP=%JOYOSE_TEG_TMP_DIR%\.keep"
more +18 "%JOYOSE_TEG_SELF%" > "%JOYOSE_TEG_TMP%"
if errorlevel 1 exit /b %ERRORLEVEL%
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%JOYOSE_TEG_TMP%"
set "ERR=%ERRORLEVEL%"
del "%JOYOSE_TEG_TMP%" >nul 2>nul
if not exist "%JOYOSE_TEG_KEEP%" rmdir /s /q "%JOYOSE_TEG_TMP_DIR%" >nul 2>nul
echo.
if "%ERR%"=="0" echo Done. Output directory is shown above.
if not "%ERR%"=="0" echo Failed. Error code: %ERR%.
if not defined JOYOSE_TEG_NO_PAUSE pause
exit /b %ERR%
# POWERSHELL_PAYLOAD

# ===================== 改这里就行 ======================
# 服务器: cn / intl / india / russia / staging
$Server = "cn"

# 输出目录，默认在脚本所在目录创建
$OutDir = "."

# Joyose APK 信息
$PackageName = "com.xiaomi.joyose"
$AppVersion = "532"
$VersionName = "2.5.32"

# 本地已有最大版本。0 表示全量拉取
$LocalVersion = "0"

# 机型和系统信息，一般改设备代号就行
$Device = "songyuan"
$MiuiRegion = "CN"
$Locale = "zh_CN"
$Incremental = "4.0.5.0.AUTO"
$MiuiVersionName = "V816"
$BuildType = "stable"
$AndroidRelease = "16"

# 一般不用填。Joyose 真机上 uid 是随机 UUID；留空会每次自动生成
$Uid = ""
$IHash = ""

# 默认只保留 机型_版本.zip。
# 需要散文件和 request/raw/rule/module 等调试文件时改成 $true
$KeepDebugFiles = $false
# ===================== 配置到此结束 =====================

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$ScriptDir = Split-Path -Parent $env:JOYOSE_TEG_SELF
$script:Utf8NoBom = New-Object Text.UTF8Encoding($false)

function Test-Text {
    param([object]$Value)
    return ($null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value))
}

function Select-FirstText {
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Values)
    foreach ($value in $Values) {
        if (Test-Text $value) {
            return ([string]$value).Trim()
        }
    }
    return $null
}

function Convert-LocaleName {
    param([string]$Value)
    if (-not (Test-Text $Value)) {
        return $null
    }
    $normalized = $Value.Trim().Replace("-", "_")
    $parts = $normalized.Split("_")
    if ($parts.Count -ge 2) {
        return ("{0}_{1}" -f $parts[0].ToLowerInvariant(), $parts[1].ToUpperInvariant())
    }
    return $normalized
}

function Normalize-Region {
    param([string]$Value)
    if (-not (Test-Text $Value)) {
        return $null
    }
    return $Value.Trim().ToUpperInvariant()
}

function Get-TegBaseUrl {
    param([string]$ServerName)
    switch ($ServerName) {
        "staging" { return "http://staging.mcc.inf.miui.com/" }
        "india" { return "https://mcc.india.inf.miui.com/" }
        "russia" { return "https://mcc.russia.inf.miui.com/" }
        "intl" { return "https://mcc.intl.inf.miui.com/" }
        default { return "https://mcc.inf.miui.com/" }
    }
}

function ConvertTo-PrettyJson {
    param([object]$Value)
    $json = $Value | ConvertTo-Json -Depth 100 -Compress
    # Windows PowerShell escapes HTML characters as \uXXXX. The decrypted
    # config format keeps these characters literal (for example, 2160x994->2052x944).
    $json = $json `
        -replace '(?<!\\)\\u003[cC]', '<' `
        -replace '(?<!\\)\\u003[eE]', '>' `
        -replace '(?<!\\)\\u0026', '&' `
        -replace '(?<!\\)\\u0027', "'"

    $builder = New-Object Text.StringBuilder
    $indent = 0
    $inString = $false
    $escaped = $false

    for ($i = 0; $i -lt $json.Length; $i++) {
        $char = $json[$i]

        if ($inString) {
            [void]$builder.Append($char)
            if ($escaped) {
                $escaped = $false
            } elseif ($char -eq '\') {
                $escaped = $true
            } elseif ($char -eq '"') {
                $inString = $false
            }
            continue
        }

        switch ($char) {
            '"' {
                $inString = $true
                [void]$builder.Append($char)
            }
            { $_ -eq '{' -or $_ -eq '[' } {
                $close = if ($char -eq '{') { '}' } else { ']' }
                $j = $i + 1
                while ($j -lt $json.Length -and [char]::IsWhiteSpace($json[$j])) { $j++ }
                if ($j -lt $json.Length -and $json[$j] -eq $close) {
                    [void]$builder.Append($char)
                    [void]$builder.Append($close)
                    $i = $j
                } else {
                    [void]$builder.Append($char)
                    $indent++
                    [void]$builder.Append("`r`n")
                    [void]$builder.Append((' ' * ($indent * 2)))
                }
            }
            { $_ -eq '}' -or $_ -eq ']' } {
                $indent--
                [void]$builder.Append("`r`n")
                [void]$builder.Append((' ' * ($indent * 2)))
                [void]$builder.Append($char)
            }
            ',' {
                [void]$builder.Append($char)
                [void]$builder.Append("`r`n")
                [void]$builder.Append((' ' * ($indent * 2)))
            }
            ':' {
                [void]$builder.Append(": ")
            }
            { [char]::IsWhiteSpace($_) } {
            }
            default {
                [void]$builder.Append($char)
            }
        }
    }

    return $builder.ToString()
}

function Save-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )
    [IO.File]::WriteAllText($Path, (ConvertTo-PrettyJson $Value), $script:Utf8NoBom)
}

function Convert-ResponseBytesToText {
    param([byte[]]$Bytes)

    if ($null -eq $Bytes -or $Bytes.Length -eq 0) {
        return ""
    }

    if ($Bytes.Length -ge 4 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE -and $Bytes[2] -eq 0x00 -and $Bytes[3] -eq 0x00) {
        return [Text.Encoding]::UTF32.GetString($Bytes, 4, $Bytes.Length - 4)
    }
    if ($Bytes.Length -ge 4 -and $Bytes[0] -eq 0x00 -and $Bytes[1] -eq 0x00 -and $Bytes[2] -eq 0xFE -and $Bytes[3] -eq 0xFF) {
        return (New-Object Text.UTF32Encoding($true, $true)).GetString($Bytes, 4, $Bytes.Length - 4)
    }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
        return [Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2)
    }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) {
        return [Text.Encoding]::BigEndianUnicode.GetString($Bytes, 2, $Bytes.Length - 2)
    }
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        return [Text.Encoding]::UTF8.GetString($Bytes, 3, $Bytes.Length - 3)
    }

    $strictUtf8 = New-Object Text.UTF8Encoding($false, $true)
    try {
        return $strictUtf8.GetString($Bytes)
    } catch {
        # Some TEG responses are Chinese text encoded as GB18030 without a charset.
        try {
            return [Text.Encoding]::GetEncoding(936).GetString($Bytes)
        } catch {
            return [Text.Encoding]::UTF8.GetString($Bytes)
        }
    }
}

function Encode-FormComponent {
    param([string]$Value)
    if ($null -eq $Value) {
        $Value = "null"
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    $builder = New-Object Text.StringBuilder
    foreach ($byte in $bytes) {
        $isAlphaNum = (
            ($byte -ge 0x30 -and $byte -le 0x39) -or
            ($byte -ge 0x41 -and $byte -le 0x5A) -or
            ($byte -ge 0x61 -and $byte -le 0x7A)
        )
        if ($isAlphaNum -or $byte -eq 0x2E -or $byte -eq 0x2D -or $byte -eq 0x2A -or $byte -eq 0x5F) {
            [void]$builder.Append([char]$byte)
        } elseif ($byte -eq 0x20) {
            [void]$builder.Append("+")
        } else {
            [void]$builder.Append("%")
            [void]$builder.Append($byte.ToString("X2"))
        }
    }
    return $builder.ToString()
}

function Get-TegSign {
    param(
        [Collections.IDictionary]$Params,
        [string]$SigningPackageName
    )
    [string[]]$keys = @($Params.Keys | ForEach-Object { [string]$_ })
    [Array]::Sort($keys, [StringComparer]::Ordinal)

    $parts = New-Object "Collections.Generic.List[string]"
    foreach ($key in $keys) {
        if ([string]::IsNullOrEmpty($key)) {
            continue
        }
        $value = $Params[$key]
        if ($null -eq $value) {
            $value = "null"
        }
        [void]$parts.Add(("{0}={1}" -f $key, [string]$value))
    }

    $raw = (($parts.ToArray()) -join "&") + "&" + $SigningPackageName
    $base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($raw))
    $md5 = [Security.Cryptography.MD5]::Create()
    try {
        $hash = $md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($base64))
    } finally {
        $md5.Dispose()
    }

    $hex = New-Object Text.StringBuilder
    foreach ($byte in $hash) {
        [void]$hex.Append($byte.ToString("X2"))
    }

    return [pscustomobject]@{
        Raw = $raw
        Base64 = $base64
        Sign = $hex.ToString()
    }
}

function New-TegFormBody {
    param(
        [Collections.IDictionary]$Params,
        [string]$SigningPackageName
    )
    $pairs = New-Object "Collections.Generic.List[string]"
    [string[]]$keys = @($Params.Keys | ForEach-Object { [string]$_ })
    [Array]::Sort($keys, [StringComparer]::Ordinal)
    foreach ($key in $keys) {
        if ([string]::IsNullOrEmpty($key)) {
            continue
        }
        $value = $Params[$key]
        if ($null -eq $value) {
            $value = "null"
        }
        [void]$pairs.Add(("{0}={1}" -f (Encode-FormComponent $key), (Encode-FormComponent ([string]$value))))
    }

    $signature = Get-TegSign -Params $Params -SigningPackageName $SigningPackageName
    [void]$pairs.Add(("sign={0}" -f (Encode-FormComponent $signature.Sign)))

    return [pscustomobject]@{
        Body = (($pairs.ToArray()) -join "&")
        Signature = $signature
    }
}

function Invoke-TegPost {
    param(
        [string]$Uri,
        [string]$Body,
        [string]$BodyPath,
        [string]$TempDirectory
    )

    try {
        $response = Invoke-WebRequest `
            -Uri $Uri `
            -Method Post `
            -Body $Body `
            -ContentType "application/x-www-form-urlencoded" `
            -UseBasicParsing `
            -TimeoutSec 30
        $stream = $response.RawContentStream
        if ($stream.CanSeek) {
            $stream.Position = 0
        }
        $memory = New-Object IO.MemoryStream
        try {
            $stream.CopyTo($memory)
            return ,([byte[]]$memory.ToArray())
        } finally {
            $memory.Dispose()
        }
    } catch {
        $webError = $_.Exception.Message
        $curlError = ""
        $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
        if ($curl) {
            Write-Warning "Invoke-WebRequest failed: $webError; retrying with curl.exe"
            $responsePath = Join-Path $TempDirectory ("response_{0}.tmp" -f [guid]::NewGuid().ToString("N"))
            $curlArgs = @(
                "-sS",
                "--tlsv1.2",
                "--ssl-no-revoke",
                "-X", "POST",
                "-H", "Content-Type: application/x-www-form-urlencoded",
                "--data-binary", "@$BodyPath",
                "--connect-timeout", "10",
                "--max-time", "30",
                "--output", $responsePath,
                $Uri
            )
            $oldErrorActionPreference = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                $curlOutput = & $curl.Source @curlArgs 2>&1
                $curlExit = $LASTEXITCODE
            } finally {
                $ErrorActionPreference = $oldErrorActionPreference
            }
            try {
                if ($curlExit -eq 0) {
                    return ,([IO.File]::ReadAllBytes($responsePath))
                }
                $curlError = $curlOutput -join "`n"
            } finally {
                Remove-Item -LiteralPath $responsePath -Force -ErrorAction SilentlyContinue
            }
        } else {
            $curlError = "curl.exe not found"
        }

        $pythonCandidates = @(
            (Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"),
            "python.exe"
        )
        $pythonExe = $null
        foreach ($candidate in $pythonCandidates) {
            if (Test-Path -LiteralPath $candidate) {
                $pythonExe = $candidate
                break
            }
            $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
            if ($cmd) {
                $pythonExe = $cmd.Source
                break
            }
        }
        if (-not $pythonExe) {
            throw "Invoke-WebRequest failed: $webError; curl.exe failed: $curlError; python.exe not found"
        }

        Write-Warning "curl.exe failed: $curlError; retrying with python urllib"
        $responsePath = Join-Path $TempDirectory ("response_{0}.tmp" -f [guid]::NewGuid().ToString("N"))
        $pythonCode = @'
import pathlib
import sys
import urllib.request

url = sys.argv[1]
body_path = pathlib.Path(sys.argv[2])
response_path = pathlib.Path(sys.argv[3])
body = body_path.read_bytes()
request = urllib.request.Request(
    url,
    data=body,
    headers={'Content-Type': 'application/x-www-form-urlencoded'},
    method='POST',
)
with urllib.request.urlopen(request, timeout=30) as response:
    response_path.write_bytes(response.read())
'@
        $oldErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $pythonOutput = & $pythonExe -c $pythonCode $Uri $BodyPath $responsePath 2>&1
            $pythonExit = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $oldErrorActionPreference
        }
        try {
            if ($pythonExit -ne 0) {
                throw "Invoke-WebRequest failed: $webError; curl.exe failed: $curlError; python urllib failed: $($pythonOutput -join "`n")"
            }
            return ,([IO.File]::ReadAllBytes($responsePath))
        } finally {
            Remove-Item -LiteralPath $responsePath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Convert-JsonStringOrNull {
    param([string]$Text)
    if (-not (Test-Text $Text)) {
        return $null
    }
    try {
        return ($Text | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        return $null
    }
}

function Prepare-Rule {
    param([object]$Rule)

    $contentText = [string]$Rule.content
    $parsedContent = Convert-JsonStringOrNull $contentText
    return [pscustomobject]@{
        Status = [int]$Rule.status
        RuleId = [long]$Rule.ruleId
        Version = [long]$Rule.version
        ModuleKey = [string]$Rule.moduleKey
        Module = Get-SafeFileName ([string]$Rule.moduleKey)
        ParsedContent = $parsedContent
        Content = $(if ($null -ne $parsedContent) { $parsedContent } else { $contentText })
    }
}

function Get-SafeFileName {
    param([string]$Value)
    if (-not (Test-Text $Value)) {
        return "unknown"
    }
    return ($Value -replace '[\\/:*?"<>|]', "_")
}

function Remove-GeneratedExtraFiles {
    param(
        [string]$OutRoot,
        [string[]]$KeepPaths
    )

    $keepNames = @{}
    foreach ($path in $KeepPaths) {
        if (Test-Text $path) {
            $keepNames[[IO.Path]::GetFileName($path).ToLowerInvariant()] = $true
        }
    }

    $generatedPatterns = @(
        '^teg_getData_(request|response|raw)\.json$',
        '^teg_getData_body\.txt$',
        '^rules\.json$',
        '^rule_.+\.(json|txt)$',
        '^module_.+_(merged|rules)\.json$',
        '^\[teg_config\.db\]\[.+\]\.json$',
        '^\[(booster_config|common_config)\]\.json$'
    )

    foreach ($file in Get-ChildItem -LiteralPath $OutRoot -File) {
        if ($keepNames.ContainsKey($file.Name.ToLowerInvariant())) {
            continue
        }
        foreach ($pattern in $generatedPatterns) {
            if ($file.Name -match $pattern) {
                Remove-Item -LiteralPath $file.FullName -Force
                break
            }
        }
    }
}

$Device = Select-FirstText $Device "myron"
$MiuiRegion = Normalize-Region (Select-FirstText $MiuiRegion "CN")
$Locale = Convert-LocaleName (Select-FirstText $Locale "zh_CN")
$Incremental = Select-FirstText $Incremental "OS3.0.306.0.WPMCNXM"
$MiuiVersionName = Select-FirstText $MiuiVersionName "V816"
$BuildType = Select-FirstText $BuildType "stable"
$AndroidRelease = Select-FirstText $AndroidRelease "16"
$Uid = Select-FirstText $Uid ([guid]::NewGuid().ToString())

$baseUrl = Get-TegBaseUrl $Server
$url = $baseUrl.TrimEnd("/") + "/cloud/app/getData"

$deviceInfo = [ordered]@{}
if (Test-Text $IHash) { $deviceInfo["ihash"] = $IHash }
if (Test-Text $Uid) { $deviceInfo["uid"] = $Uid }
if (Test-Text $Device) { $deviceInfo["d"] = $Device }
if (Test-Text $MiuiRegion) { $deviceInfo["r"] = $MiuiRegion }
if (Test-Text $Locale) { $deviceInfo["l"] = $Locale }
if (Test-Text $Incremental) { $deviceInfo["v"] = $Incremental }
if (Test-Text $MiuiVersionName) { $deviceInfo["bv"] = $MiuiVersionName }
if (Test-Text $BuildType) { $deviceInfo["t"] = $BuildType }
if (Test-Text $AndroidRelease) { $deviceInfo["av"] = $AndroidRelease }
$deviceInfo["p"] = "android"

$deviceInfoJson = $deviceInfo | ConvertTo-Json -Depth 100 -Compress
$params = [ordered]@{
    packageName = $PackageName
    appVersion = [string]$AppVersion
    versionName = $VersionName
    deviceInfo = $deviceInfoJson
    version = [string]$LocalVersion
}

$form = New-TegFormBody -Params $params -SigningPackageName $PackageName

$outputRoot = Join-Path $ScriptDir $OutDir
$outRoot = Join-Path $ScriptDir "JoyoseConfig-tmp"
New-Item -ItemType Directory -Force -Path $outRoot | Out-Null
$keepMarker = Join-Path $outRoot ".keep"
if ($KeepDebugFiles) {
    [IO.File]::WriteAllText($keepMarker, "keep", $script:Utf8NoBom)
} else {
    Remove-Item -LiteralPath $keepMarker -Force -ErrorAction SilentlyContinue
}
$bodyPath = Join-Path $outRoot "teg_getData_body.txt"

[IO.File]::WriteAllText($bodyPath, $form.Body, [Text.Encoding]::ASCII)

if ($KeepDebugFiles) {
    $requestInfo = [ordered]@{
        url = $url
        method = "POST"
        contentType = "application/x-www-form-urlencoded"
        server = $Server
        params = $params
        deviceInfo = $deviceInfo
        signRaw = $form.Signature.Raw
        signBase64 = $form.Signature.Base64
        sign = $form.Signature.Sign
        body = $form.Body
    }
    Save-JsonFile -Path (Join-Path $outRoot "teg_getData_request.json") -Value $requestInfo
}

Write-Host "Joyose TEG getData"
Write-Host "  URL: $url"
Write-Host "  Device: $Device / region=$MiuiRegion / incremental=$Incremental"
Write-Host "  Sign: $($form.Signature.Sign)"
if ($KeepDebugFiles) {
    Write-Host "  Request: $(Join-Path $outRoot 'teg_getData_request.json')"
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {}

$responseBytes = $null
try {
    $responseBytes = Invoke-TegPost -Uri $url -Body $form.Body -BodyPath $bodyPath -TempDirectory $outRoot
} finally {
    if (-not $KeepDebugFiles) {
        Remove-Item -LiteralPath $bodyPath -Force -ErrorAction SilentlyContinue
    }
}
$responseContent = Convert-ResponseBytesToText -Bytes $responseBytes
$rawPath = Join-Path $outRoot "teg_getData_raw.json"
if ($KeepDebugFiles) {
    [IO.File]::WriteAllBytes($rawPath, $responseBytes)
}

$responseJson = $responseContent | ConvertFrom-Json -ErrorAction Stop
if ($KeepDebugFiles) {
    Save-JsonFile -Path (Join-Path $outRoot "teg_getData_response.json") -Value $responseJson
}

if ([int]$responseJson.code -ne 200) {
    if (-not $KeepDebugFiles) {
        $rawPath = "temporary response not retained"
    }
    Write-Warning "服务端返回 code=$($responseJson.code), msg=$($responseJson.msg)。原始响应已保存: $rawPath"
    return
}

$rules = @($responseJson.data.rules)
if ($KeepDebugFiles) {
    if ($rules.Count -eq 0) {
        [IO.File]::WriteAllText((Join-Path $outRoot "rules.json"), "[]", $script:Utf8NoBom)
    } else {
        Save-JsonFile -Path (Join-Path $outRoot "rules.json") -Value $rules
    }
}

$activeRules = @($rules | Where-Object { [int]$_.status -eq 1 })
$preparedRules = @($activeRules | ForEach-Object { Prepare-Rule $_ })

if ($KeepDebugFiles) {
    foreach ($rule in $preparedRules) {
        if ($null -ne $rule.ParsedContent) {
            Save-JsonFile -Path (Join-Path $outRoot ("rule_{0}_{1}_v{2}.json" -f $rule.Module, $rule.RuleId, $rule.Version)) -Value $rule.ParsedContent
        } else {
            [IO.File]::WriteAllText((Join-Path $outRoot ("rule_{0}_{1}_v{2}.txt" -f $rule.Module, $rule.RuleId, $rule.Version)), [string]$rule.Content, $script:Utf8NoBom)
        }
    }
}

$outputModules = @("booster_config", "common_config")
$finalFiles = New-Object "Collections.Generic.List[string]"
$groups = $preparedRules | Group-Object -Property ModuleKey
foreach ($group in $groups) {
    $module = Get-SafeFileName ([string]$group.Name)
    $orderedRules = @($group.Group | Sort-Object -Property Version)
    $moduleRules = New-Object "Collections.Generic.List[object]"
    $merged = [ordered]@{}

    foreach ($rule in $orderedRules) {
        [void]$moduleRules.Add([pscustomobject]@{
            status = $rule.Status
            ruleId = $rule.RuleId
            version = $rule.Version
            moduleKey = $rule.ModuleKey
            content = $rule.Content
        })

        if ($null -ne $rule.ParsedContent -and @($rule.ParsedContent.PSObject.Properties).Count -gt 0) {
            foreach ($prop in $rule.ParsedContent.PSObject.Properties) {
                $merged[$prop.Name] = $prop.Value
            }
        }
    }

    if ($KeepDebugFiles) {
        Save-JsonFile -Path (Join-Path $outRoot ("module_{0}_rules.json" -f $module)) -Value $moduleRules
    }
    if ($merged.Count -gt 0) {
        if ($KeepDebugFiles) {
            Save-JsonFile -Path (Join-Path $outRoot ("module_{0}_merged.json" -f $module)) -Value $merged
            Save-JsonFile -Path (Join-Path $outRoot ("[teg_config.db][{0}].json" -f $module)) -Value $merged
        }
        if ($outputModules -contains $module) {
            $finalPath = Join-Path $outRoot ("[{0}].json" -f $module)
            Save-JsonFile -Path $finalPath -Value $merged
            [void]$finalFiles.Add($finalPath)
        }
    }
}

$zipPath = $null
if ($finalFiles.Count -gt 0) {
    $zipName = "{0}-{1}-teg_config.zip" -f (Get-SafeFileName $Device), (Get-SafeFileName $Incremental)
    $zipPath = Join-Path $outputRoot $zipName
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }
    Compress-Archive -LiteralPath $finalFiles.ToArray() -DestinationPath $zipPath -Force
}

Write-Host "  maxVersion: $($responseJson.data.maxVersion)"
Write-Host "  rules: $($rules.Count), active: $($activeRules.Count)"
Write-Host "  Output: $outputRoot"
if ($zipPath) {
    Write-Host "  Zip: $zipPath"
}
