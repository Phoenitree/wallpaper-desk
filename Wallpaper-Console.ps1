Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase

[xml]$markup=@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Wallpaper Desk" Width="490" SizeToContent="Height"
        ResizeMode="NoResize" WindowStartupLocation="CenterScreen"
        Background="#F7F6F5" Foreground="#201A18" FontFamily="Microsoft YaHei UI" FontSize="14">
  <StackPanel Margin="24">
    <TextBlock Text="Codex 壁纸" FontSize="24" FontWeight="SemiBold"/>
    <TextBlock Margin="0,8,0,20" Foreground="#605856" TextWrapping="Wrap"
               Text="设置聊天窗口的背景图。设置会保留到下次启动。"/>
    <Border Background="White" BorderBrush="#E2DDDA" BorderThickness="1" CornerRadius="8" Padding="16">
      <StackPanel>
        <TextBlock x:Name="PhotoLabel" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
        <StackPanel Orientation="Horizontal" Margin="0,12,0,18">
          <Button x:Name="Choose" Padding="12,5" Content="选择图片…"/>
          <Button x:Name="Reset" Padding="12,5" Margin="8,0,0,0" Content="恢复默认壁纸"/>
        </StackPanel>
        <StackPanel Margin="0,0,0,18">
          <TextBlock Text="随图片自动配色" FontWeight="SemiBold"/>
          <TextBlock x:Name="PaletteText" Margin="0,7,0,0" Foreground="#605856" TextWrapping="Wrap"/>
        </StackPanel>
        <DockPanel>
          <TextBlock x:Name="Percent" DockPanel.Dock="Right" FontWeight="SemiBold"/>
          <TextBlock Text="壁纸不透明度"/>
        </DockPanel>
        <Slider x:Name="OpacitySlider" Margin="0,8,0,2" Minimum="0" Maximum="100"
                TickFrequency="1" IsSnapToTickEnabled="True" SmallChange="1" LargeChange="10"
                AutomationProperties.Name="壁纸不透明度"/>
        <DockPanel>
          <TextBlock DockPanel.Dock="Right" Text="100% 原图强度" Foreground="#605856" FontSize="12"/>
          <TextBlock Text="0% 隐藏" Foreground="#605856" FontSize="12"/>
        </DockPanel>
      </StackPanel>
    </Border>
    <TextBlock x:Name="Status" Margin="0,14,0,12" MinHeight="42" Foreground="#605856" TextWrapping="Wrap"
               Text="已打开普通 Codex 时，请先完全退出，再启动带主题的版本。"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="Apply" MinWidth="92" Padding="12,7" Content="保存并应用"/>
      <Button x:Name="Launch" Margin="8,0,0,0" Padding="12,7" Foreground="White"
              Background="#923D27" BorderBrush="#923D27" Content="启动带主题的 Codex"/>
    </StackPanel>
  </StackPanel>
</Window>
"@
$reader=[Xml.XmlNodeReader]::new($markup)
try {$form=[Windows.Markup.XamlReader]::Load($reader)} finally {$reader.Dispose()}
$choose=$form.FindName('Choose')
$reset=$form.FindName('Reset')
$apply=$form.FindName('Apply')
$launch=$form.FindName('Launch')
$slider=$form.FindName('OpacitySlider')
$percent=$form.FindName('Percent')
$label=$form.FindName('PhotoLabel')
$status=$form.FindName('Status')
$paletteText=$form.FindName('PaletteText')
$state=@{Photo=$null;Reset=$false;Palette=(Get-WallpaperPalette)}
function Show-Palette {
    $paletteText.Text="强调色 $($state.Palette.accent)    背景 $($state.Palette.background)    前景 $($state.Palette.foreground)"
}
Show-Palette
$label.Text=if([IO.File]::Exists($custom)){'当前壁纸 · 自定义图片'}else{'当前壁纸 · 默认'}
$slider.Value=Get-WallpaperOpacity
$percent.Text="$([int]$slider.Value)%"
$slider.Add_ValueChanged({$percent.Text="$([int]$slider.Value)%"})
if ($SelfTest) {
    $slider.Value=37
    if($percent.Text -ne '37%' -or !$launch -or !$apply){throw 'Wallpaper console UI self-test failed.'}
    'Wallpaper console controls and opacity slider verified.'
    return
}

function Save-ConsoleSettings {
    $paletteChanged=$null -ne $state.Photo -or $state.Reset
    if($state.Photo){
        Write-WallpaperFile $custom $state.Photo
        $state.Photo=$null
        $label.Text='当前壁纸 · 自定义图片'
    } elseif($state.Reset){
        [IO.File]::Delete($custom)
        $state.Reset=$false
        $label.Text='当前壁纸 · 默认'
    }
    $value=ConvertTo-Json -Compress -InputObject @{opacity=[int]$slider.Value;palette=$state.Palette}
    Write-WallpaperFile $settingsFile ([Text.Encoding]::UTF8.GetBytes($value))
    if ($paletteChanged) {
        try {Set-NativeWallpaperPalette $state.Palette}
        catch {$state.SyncWarning=$_.Exception.Message}
    }
}

function Start-ConsoleAction([bool]$startCodex) {
    try {
        Save-ConsoleSettings
        $arguments='-NoProfile -STA -WindowStyle Hidden -File "'+$launcherPath+'"'
        if(!$startCodex){$arguments+=' -AttachOnce'}
        $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $info=[Diagnostics.ProcessStartInfo]::new($exe,$arguments)
        $info.UseShellExecute=$false
        $info.CreateNoWindow=$true
        $state.Task=[Diagnostics.Process]::Start($info)
        if($startCodex){
            $status.Text='设置已保存。正在打开带主题的 Codex。'
        }else{
            $apply.IsEnabled=$false
            $launch.IsEnabled=$false
            $status.Text='设置已保存，正在更新当前 Codex…'
            $timer.Start()
        }
    } catch {
        $status.Text=$_.Exception.Message
    }
}

$choose.Add_Click({
    $picker=[Microsoft.Win32.OpenFileDialog]::new()
    $picker.Title='选择 Codex 壁纸'
    $picker.Filter='壁纸图片 (*.png;*.jpg;*.jpeg;*.webp)|*.png;*.jpg;*.jpeg;*.webp'
    if(!$picker.ShowDialog($form)){return}
    try {
        if([IO.FileInfo]::new($picker.FileName).Length -gt 12582912){throw '请选择 12 MB 以内的图片。'}
        $bytes=[IO.File]::ReadAllBytes($picker.FileName)
        $null=Get-PhotoType $bytes
        $state.Palette=Read-PhotoPalette $picker.FileName
        Show-Palette
        $state.Photo=$bytes
        $state.Reset=$false
        $label.Text=[IO.Path]::GetFileName($picker.FileName)
        $status.Text='图片已选好，点击「保存并应用」更新。'
    } catch {$status.Text=$_.Exception.Message}
})
$reset.Add_Click({
    $state.Photo=$null
    $state.Reset=$true
    $state.Palette=[pscustomobject]@{accent=$theme.colors.accent;background=$theme.colors.background;foreground=$theme.colors.text;panel=$theme.colors.panel}
    Show-Palette
    $label.Text='默认壁纸'
    $status.Text='点击「保存并应用」恢复默认壁纸。'
})
$timer=[Windows.Threading.DispatcherTimer]::new()
$timer.Interval=[TimeSpan]::FromMilliseconds(350)
$timer.Add_Tick({
    $state.Task.Refresh()
    if(!$state.Task.HasExited){return}
    $timer.Stop()
    $apply.IsEnabled=$true
    $launch.IsEnabled=$true
    if($state.Task.ExitCode -eq 0){
        $status.Text=if($state.SyncWarning){$state.SyncWarning}else{'已更新当前 Codex 的壁纸和配色。'}
    }else{
        $status.Text='设置已保存。完全退出普通 Codex 后，用「启动带主题的 Codex」打开。'
    }
})
$apply.Add_Click({Start-ConsoleAction $false})
$launch.Add_Click({Start-ConsoleAction $true})
$form.Add_Closed({$timer.Stop()})
[void]$form.ShowDialog()
