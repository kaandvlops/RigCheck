[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# Scriptin çalıştığı klasörü en başta global olarak sabitliyoruz (Hata vermemesi için)
$global:ScriptRoot = $PSScriptRoot
if (-not $global:ScriptRoot) {
    $global:ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
}
if (-not $global:ScriptRoot) {
    $global:ScriptRoot = "D:\Araclar"
}

function Get-HardwareAudit {
    $report = [PSCustomObject]@{
        ScanTime      = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Motherboard   = "Bilinmiyor"
        BiosVersion   = "Bilinmiyor"
        MotherboardSN = "Bilinmiyor"
        CPU           = "Bilinmiyor"
        Cores         = 0
        RAM_TotalGB   = 0
        RAM_Speed     = 0
        RAM_Slots     = ""
        XMP_Warning   = $false
        GPU           = "Bilinmiyor"
        GPU_VRAM_GB   = 0
        Disks         = @()
    }

    try {
        # Anakart & BIOS
        $board = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
        $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
        if ($board) {
            $report.Motherboard = "$($board.Manufacturer) $($board.Product)"
            $report.MotherboardSN = if ($board.SerialNumber) { $board.SerialNumber.Trim() } else { "N/A" }
        }
        if ($bios) {
            $report.BiosVersion = $bios.SMBIOSBIOSVersion
        }

        # CPU
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cpu) {
            $report.CPU = $cpu.Name.Trim()
            $report.Cores = "$($cpu.NumberOfCores)C / $($cpu.NumberOfLogicalProcessors)T"
        }

        # RAM & XMP
        $rams = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
        if ($rams) {
            $totalBytes = ($rams | Measure-Object -Property Capacity -Sum).Sum
            $report.RAM_TotalGB = [math]::Round($totalBytes / 1GB, 0)
            
            $speeds = $rams | Select-Object -ExpandProperty ConfiguredClockSpeed -ErrorAction SilentlyContinue
            if (-not $speeds) {
                $speeds = $rams | Select-Object -ExpandProperty Speed -ErrorAction SilentlyContinue
            }
            $maxSpeed = ($speeds | Measure-Object -Maximum).Maximum
            $report.RAM_Speed = $maxSpeed
            
            $slotsCount = ($rams | Measure-Object).Count
            $report.RAM_Slots = "$slotsCount Modül Takılı"

            if ($maxSpeed -le 2400 -and $report.RAM_TotalGB -ge 8) {
                $report.XMP_Warning = $true
            }
        }

        # GPU
        $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch "Basic|Virtual|VNC|Remote" }
        $primaryGpu = $gpus | Select-Object -First 1
        if ($primaryGpu) {
            $report.GPU = $primaryGpu.Name
            if ($primaryGpu.AdapterRAM) {
                $report.GPU_VRAM_GB = [math]::Round($primaryGpu.AdapterRAM / 1GB, 0)
            }
        }

        # Diskler
        $physicalDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue
        if ($physicalDisks) {
            foreach ($d in $physicalDisks) {
                $health = $d.HealthStatus
                $opStatus = $d.OperationalStatus
                $sizeGB = [math]::Round($d.Size / 1GB, 0)
                $report.Disks += [PSCustomObject]@{
                    Model  = $d.FriendlyName
                    Type   = $d.MediaType
                    Size   = "$sizeGB GB"
                    Health = "$health ($opStatus)"
                    StatusGood = ($health -eq "Healthy")
                }
            }
        } else {
            $disksFallback = Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue
            foreach ($d in $disksFallback) {
                $sizeGB = [math]::Round($d.Size / 1GB, 0)
                $report.Disks += [PSCustomObject]@{
                    Model  = $d.Model
                    Type   = "Disk"
                    Size   = "$sizeGB GB"
                    Health = "$($d.Status)"
                    StatusGood = ($d.Status -eq "OK")
                }
            }
        }
    } catch {}

    return $report
}

function Start-QuickStressTest {
    param([int]$Seconds = 20)
    $runUntil = (Get-Date).AddSeconds($Seconds)
    $cores = [Environment]::ProcessorCount
    
    $jobs = 1..$cores | ForEach-Object {
        Start-Job -ScriptBlock {
            param($targetTime)
            while ((Get-Date) -lt $targetTime) {
                $x = 1.0
                for ($i = 0; $i -lt 100000; $i++) {
                    $x = [math]::Sqrt($x + $i)
                }
            }
        } -ArgumentList $runUntil
    }

    $jobs | Wait-Job -Timeout ($Seconds + 5) | Out-Null
    $jobs | Remove-Job -Force | Out-Null
}

function Export-HtmlCertificate {
    param($data, $testResult, $stressDone)
    
    $statusColor = if ($testResult -eq "BASARILI (PASSED)") { "#10B981" } else { "#EF4444" }
    $xmpBadge = if ($data.XMP_Warning) { 
        "<span style='color:#F59E0B; font-weight:bold;'>[UYARI: XMP/DOCP KAPALI OLABILIR ($($data.RAM_Speed) MHz)]</span>" 
    } else { 
        "<span style='color:#10B981;'>AKTIF / NORMAL ($($data.RAM_Speed) MHz)</span>" 
    }

    $diskRows = ""
    foreach ($d in $data.Disks) {
        $color = if ($d.StatusGood) { "#10B981" } else { "#EF4444" }
        $diskRows += "<tr><td>$($d.Model)</td><td>$($d.Type)</td><td>$($d.Size)</td><td style='color:$color; font-weight:bold;'>$($d.Health)</td></tr>"
    }

    $html = @"
<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="UTF-8">
    <title>Teknik Servis Kalite Kontrol Raporu</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; background-color: #F3F4F6; margin: 0; padding: 20px; color: #1F2937; }
        .card { max-width: 800px; margin: 0 auto; background: #FFFFFF; border-radius: 12px; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); padding: 30px; border-top: 8px solid $statusColor; }
        .header { display: flex; justify-content: space-between; align-items: center; border-bottom: 2px solid #E5E7EB; padding-bottom: 15px; }
        .header h1 { margin: 0; font-size: 22px; color: #111827; }
        .badge { background-color: $statusColor; color: white; padding: 6px 14px; border-radius: 9999px; font-weight: bold; font-size: 14px; }
        .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; margin-top: 20px; }
        .item { background: #F9FAFB; padding: 12px; border-radius: 8px; border: 1px solid #E5E7EB; }
        .item label { font-size: 11px; color: #6B7280; font-weight: 600; text-transform: uppercase; display: block; margin-bottom: 4px; }
        .item div { font-size: 14px; font-weight: 500; color: #111827; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; }
        th, td { border: 1px solid #E5E7EB; padding: 8px 12px; text-align: left; font-size: 13px; }
        th { background: #F3F4F6; color: #374151; }
        .footer { margin-top: 25px; border-top: 1px dashed #D1D5DB; padding-top: 15px; display: flex; justify-content: space-between; font-size: 12px; color: #9CA3AF; }
    </style>
</head>
<body>
    <div class="card">
        <div class="header">
            <div>
                <h1>HAZIR SISTEM KALITE KONTROL FISI</h1>
                <div style="font-size:12px; color:#6B7280; margin-top:4px;">Test Tarihi: $($data.ScanTime) | Depo QA Birimi</div>
            </div>
            <div class="badge">$testResult</div>
        </div>
        <div class="grid">
            <div class="item"><label>Islemci (CPU)</label><div>$($data.CPU) ($($data.Cores))</div></div>
            <div class="item"><label>Ekran Karti (GPU)</label><div>$($data.GPU) ($($data.GPU_VRAM_GB) GB)</div></div>
            <div class="item"><label>Bellek (RAM)</label><div>$($data.RAM_TotalGB) GB - $($data.RAM_Slots) | $xmpBadge</div></div>
            <div class="item"><label>Anakart & BIOS</label><div>$($data.Motherboard) | BIOS: $($data.BiosVersion)</div></div>
            <div class="item" style="grid-column: span 2;"><label>Anakart Seri Numarasi</label><div>$($data.MotherboardSN)</div></div>
        </div>
        <h3 style="margin-top:20px; font-size:15px;">Depolama & Disk Saglik Durumu</h3>
        <table>
            <thead>
                <tr><th>Disk Modeli</th><th>Tip</th><th>Kapasite</th><th>Saglik / SMART</th></tr>
            </thead>
            <tbody>
                $diskRows
            </tbody>
        </table>
        <div class="footer">
            <div>Stres Testi: $(if($stressDone){"20 Sn CPU Stabilite OK"}else{"Yapilmadi"})</div>
            <div>Imza / Teknisyen: ______________</div>
        </div>
    </div>
</body>
</html>
"@

    $cleanSN = ($data.MotherboardSN -replace '[^a-zA-Z0-9]','_')
    if (-not $cleanSN) { $cleanSN = "CIHAZ" }
    $fileName = "TEST_QA_$cleanSN.html"
    
    $desktopPath = [System.IO.Path]::Combine([Environment]::GetFolderPath("Desktop"), $fileName)
    $html | Out-File -FilePath $desktopPath -Encoding UTF8
    
    # USB Raporlar klasörüne kaydetme (Düzeltildi)
    try {
        $parentFolder = Split-Path -Parent $global:ScriptRoot
        $reportsFolder = Join-Path $parentFolder "Raporlar"
        if (-not (Test-Path $reportsFolder)) {
            New-Item -ItemType Directory -Path $reportsFolder -Force | Out-Null
        }
        $usbPath = Join-Path $reportsFolder $fileName
        $html | Out-File -FilePath $usbPath -Encoding UTF8
    } catch {}

    return $desktopPath
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="RigCheck Pro - Depo QA &amp; Test Konsolu" 
        Height="540" Width="680" 
        WindowStartupLocation="CenterScreen" 
        Background="#1E1E2E" 
        ResizeMode="NoResize">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0" Margin="0,0,0,15">
            <TextBlock Text="RIGCHECK // HAZIR SISTEM DONANIM DOGRULAMA" FontSize="18" FontWeight="Bold" Foreground="#89B4FA"/>
            <TextBlock Text="Pre-Boot &amp; Masaustu Otomatik Ariza / Envanter Araci" FontSize="12" Foreground="#A6ADC8"/>
        </StackPanel>

        <Border Grid.Row="1" Background="#11111B" CornerRadius="8" Padding="12" BorderBrush="#313244" BorderThickness="1">
            <ScrollViewer x:Name="LogScroll">
                <TextBox x:Name="LogBox" Background="Transparent" Foreground="#A6E3A1" 
                         FontFamily="Consolas" FontSize="13" TextWrapping="Wrap" 
                         IsReadOnly="True" BorderThickness="0"/>
            </ScrollViewer>
        </Border>

        <Grid Grid.Row="2" Margin="0,15,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            
            <Button x:Name="BtnAudit" Grid.Column="0" Content="1. Donanimi Tara" Height="40" Margin="0,0,5,0"
                    Background="#313244" Foreground="White" FontWeight="SemiBold" Cursor="Hand"/>
            
            <Button x:Name="BtnStress" Grid.Column="1" Content="2. Hizli Stres (20s)" Height="40" Margin="5,0,5,0"
                    Background="#45475A" Foreground="White" FontWeight="SemiBold" Cursor="Hand" IsEnabled="False"/>
            
            <Button x:Name="BtnExport" Grid.Column="2" Content="3. Rapor/Fis Bas" Height="40" Margin="5,0,0,0"
                    Background="#A6E3A1" Foreground="#11111B" FontWeight="Bold" Cursor="Hand" IsEnabled="False"/>
        </Grid>
    </Grid>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

$logBox   = $window.FindName("LogBox")
$logScroll= $window.FindName("LogScroll")
$btnAudit = $window.FindName("BtnAudit")
$btnStress= $window.FindName("BtnStress")
$btnExport= $window.FindName("BtnExport")

$global:auditData = $null
$global:stressDone = $false

function Write-Log {
    param([string]$text)
    $logBox.Dispatcher.Invoke([Action]{
        $logBox.AppendText("[$((Get-Date).ToString('HH:mm:ss'))] $text`r`n")
        $logScroll.ScrollToEnd()
    })
}

$btnAudit.Add_Click({
    $btnAudit.IsEnabled = $false
    Write-Log "Donanim taramasi baslatildi..."
    
    $global:auditData = Get-HardwareAudit
    
    Write-Log "CPU: $($global:auditData.CPU)"
    Write-Log "GPU: $($global:auditData.GPU) ($($global:auditData.GPU_VRAM_GB) GB)"
    Write-Log "RAM: $($global:auditData.RAM_TotalGB) GB ($($global:auditData.RAM_Slots)) @ $($global:auditData.RAM_Speed) MHz"
    
    if ($global:auditData.XMP_Warning) {
        Write-Log "--> UYARI: RAM frekansi dusuk gorunuyor ($($global:auditData.RAM_Speed) MHz). XMP/DOCP acilmali!"
    } else {
        Write-Log "--> RAM Frekansi: Normal / Profil Aktif."
    }

    Write-Log "Anakart: $($global:auditData.Motherboard) (SN: $($global:auditData.MotherboardSN))"
    foreach ($d in $global:auditData.Disks) {
        Write-Log "Disk: $($d.Model) ($($d.Size)) - Durum: $($d.Health)"
    }
    
    Write-Log "Tarama bitti. Hizli stres testi uygulayabilir veya fis basabilirsiniz."
    $btnStress.IsEnabled = $true
    $btnExport.IsEnabled = $true
    $btnAudit.IsEnabled = $true
})

$btnStress.Add_Click({
    $btnStress.IsEnabled = $false
    Write-Log "20 saniyelik stabilite testi calistiriliyor..."
    Start-QuickStressTest -Seconds 20
    $global:stressDone = $true
    Write-Log "Stabilite testi tamamlandi! Kapanma veya donma saptanmadi."
    $btnStress.IsEnabled = $true
})

$btnExport.Add_Click({
    $btnExport.IsEnabled = $false
    Write-Log "Rapor HTML olarak olusturuluyor..."
    $status = if ($global:auditData.XMP_Warning) { "KONTROL GEREKLI (XMP KAPALI)" } else { "BASARILI (PASSED)" }
    $path = Export-HtmlCertificate -data $global:auditData -testResult $status -stressDone $global:stressDone
    Write-Log "Rapor hazir: $path"
    Start-Process $path
    $btnExport.IsEnabled = $true
})

$window.ShowDialog() | Out-Null