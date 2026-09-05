# Cai .deb len iPhone qua SSH (muc 9.2). Yeu cau module Posh-SSH.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools/install_device.ps1 -Ip 192.168.1.23 -Deb .\KhoangCachAnToan_0.1.0_iphoneos-arm64.deb
param(
  [Parameter(Mandatory=$true)][string]$Ip,
  [Parameter(Mandatory=$true)][string]$Deb,
  [string]$User = "mobile",
  [string]$Password = "1"
)
Import-Module Posh-SSH -ErrorAction Stop
$debName = [System.IO.Path]::GetFileName($Deb)
$cred = New-Object System.Management.Automation.PSCredential($User, (ConvertTo-SecureString $Password -AsPlainText -Force))
$sf = New-SFTPSession -ComputerName $Ip -Credential $cred -AcceptKey
Set-SFTPItem -SFTPSession $sf -Path $Deb -Destination '/var/mobile' -Force
Remove-SFTPSession -SFTPSession $sf | Out-Null
$ssh = New-SSHSession -ComputerName $Ip -Credential $cred -AcceptKey
$cmd = "echo $Password | sudo -S dpkg -i /var/mobile/$debName 2>&1 | tail -5; dpkg-query -W -f='`${Version}\n' com.khoangcachantoan.app; ls -la /var/jb/Applications/KhoangCachAnToan.app | head -5"
(Invoke-SSHCommand -SSHSession $ssh -Command $cmd -TimeOut 120).Output
Remove-SSHSession -SSHSession $ssh | Out-Null
