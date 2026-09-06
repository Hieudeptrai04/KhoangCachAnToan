# Doc log app + crash log tu iPhone (muc 9.2).
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools/device_log.ps1 -Ip 192.168.1.23 [-Lines 80]
#
# PATH: kenh exec cua SSH chi co /usr/bin:/bin:/usr/sbin:/sbin. Tren jailbreak rootless,
# tail/head/ls cua coreutils nam trong /var/jb/usr/bin, khong co trong PATH mac dinh
# -> phai tu them, neu khong lenh bao "not found" va script khong in ra gi huu ich.
param(
  [Parameter(Mandatory=$true)][string]$Ip,
  [int]$Lines = 80,
  [string]$User = "mobile",
  [string]$Password = "1"
)
Import-Module Posh-SSH -ErrorAction Stop
$jb = "/var/jb/usr/local/bin:/var/jb/usr/bin:/var/jb/usr/sbin:/var/jb/bin:/var/jb/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
$cred = New-Object System.Management.Automation.PSCredential($User, (ConvertTo-SecureString $Password -AsPlainText -Force))
$ssh = New-SSHSession -ComputerName $Ip -Credential $cred -AcceptKey
$cmd = "export PATH=$jb; " +
       "echo '--- log.txt ---'; tail -n $Lines /var/mobile/Documents/KhoangCachAnToan/log.txt; " +
       "echo '--- crash reports ---'; ls -t /var/mobile/Library/Logs/CrashReporter/KhoangCachAnToan-*.ips | head -3; " +
       "echo '--- phien ban da cai ---'; dpkg-query -W -f='`${Version}\n' com.khoangcachantoan.app"
$r = Invoke-SSHCommand -SSHSession $ssh -Command "{ $cmd ; } 2>&1" -TimeOut 60
$r.Output
if ($r.Error) { "--- stderr ---"; $r.Error }
Remove-SSHSession -SSHSession $ssh | Out-Null
