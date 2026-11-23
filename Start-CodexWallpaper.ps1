param([switch]$SelfTest,[switch]$AttachOnce,[switch]$ManageWallpaper)
$ErrorActionPreference='Stop'
$stateDir=Join-Path $env:LOCALAPPDATA 'WallpaperDesk'
if (!$SelfTest) {[void][IO.Directory]::CreateDirectory($stateDir)}
$log=Join-Path $stateDir 'wallpaper-status.log'
$theme=[pscustomobject]@{
    colors=[pscustomobject]@{accent='#356357';background='#f4f1ea';text='#252d29';panel='#faf8f3'}
    art=[pscustomobject]@{focusX=0.57}
}
$originalPng=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'default-wallpaper.png')))
$launcherPath=$PSCommandPath
$settingsFile=Join-Path $stateDir 'wallpaper-settings.json'
$custom=Join-Path $stateDir 'custom-wallpaper.image'
function Get-PhotoType([byte[]]$bytes) {
    if ($bytes.Length -lt 12) {throw '图片文件太短。'}
    $head=[BitConverter]::ToString($bytes,0,12)
    if ($head.StartsWith('89-50-4E-47-0D-0A-1A-0A')) {return 'image/png'}
    if ($head.StartsWith('FF-D8-FF')) {return 'image/jpeg'}
    if ($head -match '^52-49-46-46-(?:[A-F0-9]{2}-){4}57-45-42-50$') {return 'image/webp'}
    throw '支持 PNG、JPG 和 WebP 图片。'
}
$nativeConfig=Join-Path $env:USERPROFILE '.codex\config.toml'
function Get-WallpaperPalette {
    $fallback=[pscustomobject]@{
        accent=$theme.colors.accent
        background=$theme.colors.background
        foreground=$theme.colors.text
        panel=$theme.colors.panel
    }
    if (![IO.File]::Exists($settingsFile)) {return $fallback}
    try {
        $saved=(ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($settingsFile))).palette
        foreach ($name in 'accent','background','foreground','panel') {
            if($saved.$name -notmatch '^#[\da-fA-F]{6}$'){return $fallback}
        }
        return $saved
    } catch {return $fallback}
}
function Get-CodexMode {
    if ([IO.File]::Exists($nativeConfig)) {
        $config=[IO.File]::ReadAllText($nativeConfig)
        $mode=[regex]::Match($config,'(?m)^appearanceTheme[ \t]*=[ \t]*"(light|dark)"')
        if($mode.Success){return $mode.Groups[1].Value}
    }
    $appColors=Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction SilentlyContinue
    if($appColors -and $appColors.AppsUseLightTheme -eq 0){return 'dark'}
    'light'
}
function Read-PhotoPalette([string]$file) {
    $python=Get-Command python.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $result=& $python.Source (Join-Path $PSScriptRoot 'wallpaper_palette.py') extract $file (Get-CodexMode)
    if($LASTEXITCODE -ne 0){throw '无法读取这张图片的配色。'}
    ConvertFrom-Json -InputObject ($result -join [Environment]::NewLine)
}
function Set-NativeWallpaperPalette($palette) {
    if(![IO.File]::Exists($nativeConfig)){return}
    $python=Get-Command python.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1
    & $python.Source (Join-Path $PSScriptRoot 'wallpaper_palette.py') sync $nativeConfig (Get-CodexMode) $palette.accent $palette.background $palette.foreground
    if($LASTEXITCODE -ne 0){throw '壁纸配色已保存，但未能同步到 Codex 外观设置。'}
}

function Get-WallpaperOpacity {
    if (![IO.File]::Exists($settingsFile)) {return 100}
    try {
        $s=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($settingsFile))
        return [int][Math]::Max(0,[Math]::Min(100,[int]$s.opacity))
    } catch {return 100}
}
function Write-WallpaperFile([string]$path,[byte[]]$bytes) {
    $temp=Join-Path $stateDir ('wallpaper-'+[guid]::NewGuid()+'.tmp')
    try {
        [IO.File]::WriteAllBytes($temp,$bytes)
        if ([IO.File]::Exists($path)) {[IO.File]::Replace($temp,$path,[NullString]::Value)}
        else {[IO.File]::Move($temp,$path)}
    } finally {if ([IO.File]::Exists($temp)) {[IO.File]::Delete($temp)}}
}
function Get-WallpaperStamp {
    "$([IO.File]::GetLastWriteTimeUtc($custom).Ticks)/$([IO.File]::GetLastWriteTimeUtc($settingsFile).Ticks)"
}

function Get-WallpaperRevision {
    $raw=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Wallpaper.css'))
    $mime='image/png'
    $encoded=$originalPng
    if (!$SelfTest -and (Test-Path -LiteralPath $custom -PathType Leaf)) {
        $photo=[IO.FileInfo]::new($custom)
        if ($photo.Length -gt 12582912) {throw '请选择 12 MB 以内的图片。'}
        $bytes=[IO.File]::ReadAllBytes($custom)
        $mime=Get-PhotoType $bytes
        $encoded=[Convert]::ToBase64String($bytes)
    }
    $palette=Get-WallpaperPalette
    $focus=[Math]::Max(0,[Math]::Min(100,[Math]::Round(100 * [double]$theme.art.focusX)))
    $css=$raw.Replace('__PNG__',$encoded).Replace('__MIME__',$mime).Replace('__BASE__',$palette.background).Replace('__PANEL__',$palette.panel).Replace('__INK__',$palette.foreground).Replace('__ACCENT__',$palette.accent).Replace('__VEIL__',((100 - (Get-WallpaperOpacity)).ToString() + '%')).Replace('__FOCUS__',"$focus%")
    $sha=[Security.Cryptography.SHA256]::Create()
    try {
        [pscustomobject]@{
            Css=$css
            Revision=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($css))).Replace('-','')
        }
    } finally {$sha.Dispose()}
}
if ($ManageWallpaper) {
    . (Join-Path $PSScriptRoot 'Wallpaper-Console.ps1')
    return
}
$wallpaper=Get-WallpaperRevision
if ($SelfTest) {
    if ($wallpaper.Css -notmatch 'data:image/png;base64,iVBOR' -or $wallpaper.Css -match '__(PNG|MIME|BASE|PANEL|FOCUS|VEIL|INK|ACCENT)__') {throw 'Unresolved theme data.'}
    'Bundled artwork and stylesheet verified.'
    return
}

function Invoke-DebugCommand($socket,[string]$method,$params,$token) {
    $script:messageId++
    $id=$script:messageId
    $bytes=[Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{id=$id;method=$method;params=$params} -Depth 8 -Compress))
    $null=$socket.SendAsync([ArraySegment[byte]]::new($bytes),[Net.WebSockets.WebSocketMessageType]::Text,$true,$token).GetAwaiter().GetResult()
    $buffer=[byte[]]::new(32768)
    do {
        $message=[IO.MemoryStream]::new()
        try {
            do {
                $part=$socket.ReceiveAsync([ArraySegment[byte]]::new($buffer),$token).GetAwaiter().GetResult()
                if ($part.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close) {throw 'Codex renderer closed.'}
                $message.Write($buffer,0,$part.Count)
            } until ($part.EndOfMessage)
            $reply=[Text.Encoding]::UTF8.GetString($message.ToArray()) | ConvertFrom-Json
        } finally {$message.Dispose()}
    } until ($reply.id -eq $id)
    if ($reply.error) {throw "$method failed: $($reply.error.message)"}
    $reply.result
}

function Set-RendererWallpaper($target,[int]$port) {
    $css=$wallpaper.Css
    $styleRevision=$wallpaper.Revision
    $url=[uri]$target.webSocketDebuggerUrl
    if ($url.Scheme -ne 'ws' -or $url.Host -ne '127.0.0.1' -or $url.Port -ne $port -or
        $url.AbsolutePath -notmatch '^/devtools/page/[a-zA-Z0-9]+$') {throw 'Unexpected renderer endpoint.'}
    $socket=[Net.WebSockets.ClientWebSocket]::new()
    $timeout=[Threading.CancellationTokenSource]::new(12000)
    try {
        $null=$socket.ConnectAsync($url,$timeout.Token).GetAwaiter().GetResult()
        # Check the document before sending the image again after a renderer reload.
        $known=Invoke-DebugCommand $socket 'Runtime.evaluate' @{expression=(('window.__wallpaperDeskWallpaper === "{0}"') -f $styleRevision);returnByValue=$true} $timeout.Token
        if ($known.result.value -eq $true) {return}
        $encoded=ConvertTo-Json -InputObject $css -Compress
        $expression="(()=>{if(location.protocol!=='app:'||!(location.hostname==='codex'||(location.hostname==='-'&&location.pathname==='/index.html'))||new URLSearchParams(location.search).get('initialRoute')==='/avatar-overlay')return false;const s=new CSSStyleSheet();s.replaceSync($encoded);const old=window.__wallpaperDeskWallpaperSheet;document.adoptedStyleSheets=[...document.adoptedStyleSheets.filter(x=>x!==old),s];window.__wallpaperDeskWallpaperSheet=s;window.__wallpaperDeskWallpaper='$styleRevision';return true;})()"
        $result=Invoke-DebugCommand $socket 'Runtime.evaluate' @{expression=$expression;returnByValue=$true} $timeout.Token
        if ($result.exceptionDetails -or $result.result.value -ne $true) {throw 'The renderer did not accept the Wallpaper Desk stylesheet.'}
        $visible=Invoke-DebugCommand $socket 'Runtime.evaluate' @{
            expression="!document.querySelector('.thread-scroll-container,[data-composer-placement=home],[data-testid=home-icon]') || getComputedStyle(document.documentElement).backgroundImage.includes('data:image/')"
            returnByValue=$true
        } $timeout.Token
        if($visible.result.value -ne $true){throw 'The wallpaper image did not reach the chat background.'}
    } finally {$socket.Dispose();$timeout.Dispose()}
}

function Show-Message([string]$text) {
    Add-Type -AssemblyName PresentationFramework
    [void][Windows.MessageBox]::Show($text,'Wallpaper Desk')
}
$mutex=[Threading.Mutex]::new($false,'Local\WallpaperDeskSession')
$owned=$false
try {
    try {$owned=$mutex.WaitOne(0)} catch [Threading.AbandonedMutexException] {$owned=$true}
    $focusExisting=!$AttachOnce
    if (!$owned -and !$AttachOnce) {$AttachOnce=$true}
    $package=Get-AppxPackage -Name OpenAI.Codex | Where-Object SignatureKind -eq Store |
        Sort-Object Version -Descending | Select-Object -First 1
    if (!$package) {throw 'Microsoft Store Codex package not found.'}
    $appId=$package.PackageFamilyName + '!App'
    if (!('CodexTaskbar' -as [type])) {Add-Type -Path (Join-Path $PSScriptRoot 'CodexTaskbar.cs')}
    $exe=Join-Path $package.InstallLocation 'app\ChatGPT.exe'
    if (!(Test-Path -LiteralPath $exe -PathType Leaf)) {throw 'Codex executable not found.'}
    $existing=@(Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" |
        Where-Object {$_.ExecutablePath -ieq $exe -and $_.CommandLine -notmatch '(?:^|\s)--type='})
    if ($existing.Count) {
        $debuggable=@($existing | Where-Object {
            $_.CommandLine -match '(?:^|\s)--remote-debugging-address=127\.0\.0\.1(?:\s|$)' -and
            $_.CommandLine -match '(?:^|\s)--remote-debugging-port=\d{1,5}(?:\s|$)'
        })
        if ($debuggable.Count -ne 1) {
            if ($AttachOnce) {throw 'Codex is running without the wallpaper launcher.'}
            Show-Message '当前 Codex 没有启动壁纸调试模式。请先从菜单完全退出 Codex，再双击 Wallpaper Desk。'
            return
        }
        $port=[int]([regex]::Match($debuggable[0].CommandLine,'--remote-debugging-port=(\d+)').Groups[1].Value)
        $app=Get-Process -Id $debuggable[0].ProcessId
        $null=[CodexTaskbar]::SetIdentity($app.Id,$appId,$focusExisting)
    } else {

        if ($AttachOnce) {throw 'No existing Codex process.'}
        $reserve=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
        $reserve.Start()
        try {$port=$reserve.LocalEndpoint.Port} finally {$reserve.Stop()}
        $app=Start-Process -FilePath $exe -ArgumentList @('--remote-debugging-address=127.0.0.1',"--remote-debugging-port=$port") -PassThru
    }
    $http=[Net.WebClient]::new()
    $http.Proxy=$null
    $started=[DateTime]::UtcNow
    $ready=$false
    $script:messageId=0
    $customStamp=Get-WallpaperStamp
    while (!$app.HasExited) {
        $stamp=Get-WallpaperStamp
        if ($stamp -ne $customStamp) {$wallpaper=Get-WallpaperRevision;$customStamp=$stamp}
        $listeners=@(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
        if ($AttachOnce -and !$listeners) {throw 'No verified listener.'}
        if ($listeners) {
            if ($listeners | Where-Object {$_.LocalAddress -ne '127.0.0.1' -or $_.OwningProcess -ne $app.Id}) {
                throw 'The debugging endpoint is not owned exclusively by the launched Codex process on loopback.'
            }
            try {
                $json=[Text.Encoding]::UTF8.GetString($http.DownloadData("http://127.0.0.1:$port/json/list"))
                $targets=ConvertFrom-Json -InputObject $json
            }
            catch {if ($AttachOnce) {throw};$targets=@()}
            foreach ($target in $targets) {
                if ($target.type -ne 'page' -or $target.url -notmatch '^app://(?:codex(?:/|$)|-/index\.html(?:[?#]|$))' -or $target.url -match '[?&]initialRoute=(?:%2[fF]|/)avatar-overlay(?:[&#]|$)' -or !$target.webSocketDebuggerUrl) {continue}
                try {
                    Set-RendererWallpaper $target $port
                    if(!$ready){$null=[CodexTaskbar]::SetIdentity($app.Id,$appId,$false)}
                    if (!$ready) {[IO.File]::WriteAllText($log,'Wallpaper Desk rendered in Codex.')}
                    $ready=$true
                    if ($AttachOnce) { "Wallpaper accepted by the current Codex renderer."; return }
                } catch {if ($AttachOnce) {throw};[IO.File]::WriteAllText($log,$_.Exception.Message)}
            }
        }
        if (!$ready -and (([DateTime]::UtcNow-$started).TotalSeconds -gt 35)) {throw 'The Codex renderer did not accept the wallpaper.'}
        Start-Sleep -Seconds 3
    }
    if (!$ready) {throw 'Codex exited before the wallpaper loaded.'}
} catch {
    [IO.File]::WriteAllText($log,$_.Exception.Message)
    if ($AttachOnce) {throw}
    Show-Message '壁纸未能加载。Codex 本身可继续使用。'
} finally {
    if ($http) {$http.Dispose()}
    if ($owned) {$mutex.ReleaseMutex()}
    $mutex.Dispose()
}
