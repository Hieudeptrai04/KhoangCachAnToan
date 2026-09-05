# Doc log app + crash log tu iPhone (muc 9.2).
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools/device_log.ps1 -Ip 192.168.1.23 [-Lines 80]
param(
  [Parameter(Mandatory=$true)][string]$Ip,
  [int]$Lines = 80,
  [string]$User = "mobile",
  [string]$Password = "1"
)
Import-Module Posh-SSH -ErrorAction Stop
$cred = New-Object System.Management.Automation.PSCredential($User, (ConvertTo-SecureString $Password -AsPlainText -Force))
$ssh = New-SSHSession -ComputerName $Ip -Credential $cred -AcceptKey
$cmd = "echo '--- log.txt ---'; tail -n $Lines /var/mobile/Documents/KhoangCachAnToan/log.txt 2>&1; echo '--- crash reports ---'; ls -t /var/mobile/Library/Logs/CrashReporter/KhoangCachAnToan-*.ips 2>/dev/null | head -3"
(Invoke-SSHCommand -SSHSession $ssh -Command $cmd -TimeOut 60).Output
Remove-SSHSession -SSHSession $ssh | Out-Null
