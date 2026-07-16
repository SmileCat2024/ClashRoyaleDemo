param(
    [ValidateRange(2, 8)]
    [int]$LinearScale = 3
)

$projectRoot = Split-Path -Parent $PSScriptRoot
$spriteRoot = Join-Path $projectRoot "assets/sprites"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
Add-Type -AssemblyName System.Drawing

$changed = 0
Get-ChildItem -LiteralPath $spriteRoot -Recurse -Filter *.png |
    Where-Object {
        # 塔、火球、迫击炮弹由独立代码按纹理像素计算尺寸，不走 SpriteRegistry 的统一补偿。
        $_.Directory.Name -ne "towers" -and
        $_.Directory.Name -ne "fireball" -and
        $_.Name -notlike "mortar_shell*"
    } |
    ForEach-Object {
        $image = [System.Drawing.Image]::FromFile($_.FullName)
        try {
            $longEdge = [Math]::Max($image.Width, $image.Height)
            $sizeLimit = [Math]::Ceiling($longEdge / [double]$LinearScale)
        }
        finally {
            $image.Dispose()
        }

        $importPath = $_.FullName + ".import"
        if (-not (Test-Path -LiteralPath $importPath)) {
            Write-Warning "缺少导入配置: $importPath"
            return
        }
        $content = [System.IO.File]::ReadAllText($importPath)
        $updated = [regex]::Replace(
            $content,
            "process/size_limit=\d+",
            "process/size_limit=$sizeLimit"
        )
        if ($updated -ne $content) {
            [System.IO.File]::WriteAllText($importPath, $updated, $utf8NoBom)
            $changed++
        }
    }

Write-Host "已更新 $changed 个序列帧导入配置（线性缩放 1/$LinearScale）。"
Write-Host "请启动 Godot Editor 或运行一次 --editor --quit 以重新生成导入缓存。"
