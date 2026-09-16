Add-Type -AssemblyName System.Drawing

$W = 1080
$H = 1510
$bmp = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

# ---------- 配色 ----------
$bg      = [System.Drawing.Color]::FromArgb(255, 13, 17, 15)
$cardBg  = [System.Drawing.Color]::FromArgb(255, 25, 31, 28)
$cardBd  = [System.Drawing.Color]::FromArgb(255, 42, 52, 47)
$green   = [System.Drawing.Color]::FromArgb(255, 76, 200, 100)
$greenD  = [System.Drawing.Color]::FromArgb(255, 30, 80, 46)
$white   = [System.Drawing.Color]::FromArgb(255, 240, 245, 242)
$gray    = [System.Drawing.Color]::FromArgb(255, 150, 162, 156)
$dim     = [System.Drawing.Color]::FromArgb(255, 105, 118, 112)

$g.Clear($bg)

# ---------- 背景装饰: 右上角绿色光晕 ----------
$glow = New-Object System.Drawing.Drawing2D.GraphicsPath
$glow.AddEllipse(620, -320, 780, 780)
$pgb = New-Object System.Drawing.Drawing2D.PathGradientBrush($glow)
$pgb.CenterColor = [System.Drawing.Color]::FromArgb(46, 76, 200, 100)
$pgb.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 76, 200, 100))
$g.FillPath($pgb, $glow)
$pgb.Dispose(); $glow.Dispose()

# ---------- 工具函数 ----------
function New-RoundedPath($x, $y, $w, $h, $r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc(($x + $w - $d), $y, $d, $d, 270, 90)
    $p.AddArc(($x + $w - $d), ($y + $h - $d), $d, $d, 0, 90)
    $p.AddArc($x, ($y + $h - $d), $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}
function Fill-Rounded($x, $y, $w, $h, $r, $color) {
    $b = New-Object System.Drawing.SolidBrush($color)
    if ($r -le 0) {
        $g.FillRectangle($b, $x, $y, $w, $h)
    } else {
        $p = New-RoundedPath $x $y $w $h $r
        $g.FillPath($b, $p); $p.Dispose()
    }
    $b.Dispose()
}
function Stroke-Rounded($x, $y, $w, $h, $r, $color, $width) {
    $p = New-RoundedPath $x $y $w $h $r
    $pen = New-Object System.Drawing.Pen($color, $width)
    $g.DrawPath($pen, $p); $pen.Dispose(); $p.Dispose()
}
function Draw-Text($text, $x, $y, $px, $style, $color) {
    $f = New-Object System.Drawing.Font("Microsoft YaHei", $px, $style, [System.Drawing.GraphicsUnit]::Pixel)
    $b = New-Object System.Drawing.SolidBrush($color)
    $g.DrawString($text, $f, $b, $x, $y)
    $f.Dispose(); $b.Dispose()
}
function Text-Width($text, $px, $style) {
    $f = New-Object System.Drawing.Font("Microsoft YaHei", $px, $style, [System.Drawing.GraphicsUnit]::Pixel)
    $s = $g.MeasureString($text, $f)
    $f.Dispose()
    return $s.Width
}
function Draw-Line($x1, $y1, $x2, $y2, $color, $width) {
    $pen = New-Object System.Drawing.Pen($color, $width)
    $g.DrawLine($pen, $x1, $y1, $x2, $y2); $pen.Dispose()
}

$M = 76           # 左右边距
$CW = $W - $M*2   # 内容宽度

# ---------- 顶部绿色条 ----------
Fill-Rounded 0 0 $W 10 0 $green

# ---------- 标签 pill ----------
$tagText = "Y700 专享增强"
$tagW = [int](Text-Width $tagText 27 ([System.Drawing.FontStyle]::Bold)) + 56
Fill-Rounded $M 92 $tagW 58 29 $greenD
Draw-Text $tagText ($M + 28) 108 27 ([System.Drawing.FontStyle]::Bold) $green

# ---------- 主标题 ----------
$y = 190
Draw-Text "温控增强模块" $M $y 78 ([System.Drawing.FontStyle]::Bold) $white
$y += 100
Draw-Text "+ 充电监控 App" $M $y 58 ([System.Drawing.FontStyle]::Bold) $green
$y += 92
Draw-Text "三代 / 四代 / 五代  全适配" $M $y 30 ([System.Drawing.FontStyle]::Regular) $gray

# ---------- 分隔线 ----------
$y += 62
Draw-Line $M $y ($W - $M) $y $cardBd 2

# ---------- 核心卖点 ----------
$y += 46
Draw-Text "亮屏 / 边充边玩" $M $y 46 ([System.Drawing.FontStyle]::Bold) $white
$y += 66
Draw-Text "也能跑满快充" $M $y 46 ([System.Drawing.FontStyle]::Bold) $green
$y += 68
Draw-Text "实测三代 / 五代激活 40W+ 快充" $M $y 27 ([System.Drawing.FontStyle]::Regular) $gray

# ---------- 四宫格功能卡 ----------
$cardW = [int](($CW - 34) / 2)
$cardH = 196
$gapX = 34
$gapY = 26
$top = $y + 66

$cards = @(
    @{ t = "温控绕过";     l1 = "禁用充电相关温区"; l2 = "伪装温度，消除降频限流" },
    @{ t = "亮屏快充增强"; l1 = "插电伪装温度";     l2 = "拔线自动恢复真实温度" },
    @{ t = "充电日志";     l1 = "功率 / 温度 / 分阶段"; l2 = "充电协议 / 输入功率" },
    @{ t = "配套 App";     l1 = "实时曲线可视化";   l2 = "自动存档 + 历史记录" }
)

for ($i = 0; $i -lt 4; $i++) {
    $col = $i % 2
    $row = [math]::Floor($i / 2)
    $cx = $M + $col * ($cardW + $gapX)
    $cy = $top + $row * ($cardH + $gapY)
    Fill-Rounded $cx $cy $cardW $cardH 20 $cardBg
    Stroke-Rounded $cx $cy $cardW $cardH 20 $cardBd 2
    # 左侧强调条
    Fill-Rounded $cx $cy 7 $cardH 3 $green
    Draw-Text $cards[$i].t ($cx + 30) ($cy + 30) 32 ([System.Drawing.FontStyle]::Bold) $green
    Draw-Text $cards[$i].l1 ($cx + 30) ($cy + 92) 25 ([System.Drawing.FontStyle]::Regular) $white
    Draw-Text $cards[$i].l2 ($cx + 30) ($cy + 130) 25 ([System.Drawing.FontStyle]::Regular) $gray
}

# ---------- 分隔线 ----------
$y = $top + 2 * $cardH + $gapY + 46
Draw-Line $M $y ($W - $M) $y $cardBd 2

# ---------- 下载信息 ----------
$y += 40
Draw-Text "下载 / Download" $M $y 26 ([System.Drawing.FontStyle]::Regular) $dim
$y += 44
Draw-Text "github.com/aweiyry/y700_thermal_boost" $M $y 31 ([System.Drawing.FontStyle]::Bold) $white
$y += 46
Draw-Text "→ Releases 页下载模块 zip 与 App apk" $M $y 26 ([System.Drawing.FontStyle]::Regular) $gray

# ---------- 底部提示 ----------
$y += 62
Draw-Text "需 root（Magisk / KernelSU）" $M $y 25 ([System.Drawing.FontStyle]::Regular) $dim
$y += 38
Draw-Text "温控绕过属硬件保护修改，高温 / 边充边玩有风险，自担风险" $M $y 25 ([System.Drawing.FontStyle]::Regular) $dim
$y += 38
Draw-Text "搬运请标明出处 · 酷安@妲你小己吧" $M $y 25 ([System.Drawing.FontStyle]::Regular) $dim

# ---------- 底部绿色条 ----------
Fill-Rounded 0 ($H - 10) $W 10 0 $green

$out = "C:\Users\AAA\Desktop\temperaturef\promo.png"
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Host "已生成: $out ($([math]::Round((Get-Item $out).Length/1KB)) KB, ${W}x${H})"
