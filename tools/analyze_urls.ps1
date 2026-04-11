$content = Get-Content 'd:\FreeIPTV\tools\playlist_sample.m3u' -Raw
$lines = $content -split "`n"
Write-Host "Total lines: $($lines.Count)"
Write-Host ""

$liveUrls = @()
$seriesUrls = @()
$movieUrls = @()

for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i].Trim()
    if ($line -match '^#EXTINF') {
        $nextLine = ""
        for ($j = $i + 1; $j -lt $lines.Count; $j++) {
            $candidate = $lines[$j].Trim()
            if ($candidate -ne "" -and $candidate -notmatch '^#') {
                $nextLine = $candidate
                break
            }
        }
        if ($nextLine -eq "") { continue }

        $group = ""
        if ($line -match 'group-title="([^"]*)"') { $group = $matches[1] }

        $name = ""
        $commaIdx = $line.LastIndexOf(',')
        if ($commaIdx -ge 0) { $name = $line.Substring($commaIdx + 1).Trim() }

        if ($nextLine -match '/live/') {
            if ($liveUrls.Count -lt 5) {
                $liveUrls += "  NAME: $name | GROUP: $group"
                $liveUrls += "  URL:  $nextLine"
                $liveUrls += "  ---"
            }
        }
        elseif ($nextLine -match '/series/') {
            if ($seriesUrls.Count -lt 5) {
                $seriesUrls += "  NAME: $name | GROUP: $group"
                $seriesUrls += "  URL:  $nextLine"
                $seriesUrls += "  ---"
            }
        }
        elseif ($nextLine -match '/movie/' -or $group -match 'VOD|movie|peli|film|cine') {
            if ($movieUrls.Count -lt 5) {
                $movieUrls += "  NAME: $name | GROUP: $group"
                $movieUrls += "  URL:  $nextLine"
                $movieUrls += "  ---"
            }
        }
    }
}

Write-Host "=== LIVE TV CHANNELS (sample) ==="
$liveUrls | ForEach-Object { Write-Host $_ }
Write-Host ""
Write-Host "=== SERIES (sample) ==="
$seriesUrls | ForEach-Object { Write-Host $_ }
Write-Host ""
Write-Host "=== MOVIES (sample) ==="
$movieUrls | ForEach-Object { Write-Host $_ }

# Also check: URLs that were classified as movies by the parser
# These are typically under /movie/ path or have VOD file extensions
Write-Host ""
Write-Host "=== ALL UNIQUE URL PATTERNS ==="
$patterns = @{}
for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i].Trim()
    if ($line -ne "" -and $line -notmatch '^#' -and $line -match '^http') {
        if ($line -match '(https?://[^/]+)(/.+?/)') {
            $pathPart = $matches[2]
            if (-not $patterns.ContainsKey($pathPart)) {
                $patterns[$pathPart] = $line
            }
        }
    }
}
foreach ($key in $patterns.Keys) {
    Write-Host "PATH: $key"
    Write-Host "  EXAMPLE: $($patterns[$key])"
}
