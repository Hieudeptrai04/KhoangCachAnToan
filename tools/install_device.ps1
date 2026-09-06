# Cai .deb len iPhone qua SSH (muc 9.2). Yeu cau module Posh-SSH.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools/install_device.ps1 -Ip 192.168.1.23 -Deb .\KhoangCachAnToan_0.3.0_iphoneos-arm64.deb
#
# PATH: kenh exec cua SSH chi co /usr/bin:/bin:/usr/sbin:/sbin. Tren jailbreak rootless,
# sudo/dpkg/dpkg-query/tail nam trong /var/jb/usr/bin -> phai tu them vao PATH.
param(
  [Parameter(Mandatory=$true)][string]$Ip,
  [Parameter(Mandatory=$true)][string]$Deb,
  [string]$User = "mobile",
  [string]$Password = "1"
)
Import-Module Posh-SSH -ErrorAction Stop
if (-not (Test-Path $Deb)) { throw "Khong thay file: $Deb" }
$debName = [System.IO.Path]::GetFileName($Deb)
$jb = "/var/jb/usr/local/bin:/var/jb/usr/bin:/var/jb/usr/sbin:/var/jb/bin:/var/jb/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
$cred = New-Object System.Management.Automation.PSCredential($User, (ConvertTo-SecureString $Password -AsPlainText -Force))

$sf = New-SFTPSession -ComputerName $Ip -Credential $cred -AcceptKey
Set-SFTPItem -SFTPSession $sf -Path $Deb -Destination '/var/mobile' -Force
Remove-SFTPSession -SFTPSession $sf | Out-Null

$ssh = New-SSHSession -ComputerName $Ip -Credential $cred -AcceptKey
$cmd = "export PATH=$jb; " +
       "echo $Password | sudo -S dpkg -i /var/mobile/$debName; " +
       "echo '--- phien ban da cai ---'; dpkg-query -W -f='`${Version}\n' com.khoangcachantoan.app; " +
       "echo '--- noi dung app ---'; ls -la /var/jb/Applications/KhoangCachAnToan.app | head -8; " +
       "echo '--- cdhash ---'; cat /var/jb/etc/khoangcachantoan/cdhashes"
$r = Invoke-SSHCommand -SSHSession $ssh -Command "{ $cmd ; } 2>&1" -TimeOut 180
$r.Output
if ($r.Error) { "--- stderr ---"; $r.Error }
Remove-SSHSession -SSHSession $ssh | Out-Null
