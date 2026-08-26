# gate.ps1 — PowerShell twin of gate.sh. Same contract, same one-line output.
#
# Windows needs its own copy because Windows PowerShell 5.1 has no `&&`, and
# because redirecting a native command's stderr inside PowerShell wraps each
# line in an ErrorRecord and sets $? to $false even when the exe returned 0 —
# a false red that looks exactly like a real one. This script reads
# $LASTEXITCODE from the process itself and never inspects $?.
#
# NOTE: duplicated verbatim in skills/session-end/scripts/gate.ps1.
# Change both or neither.
#
# Usage:
#   pwsh -File scripts/gate.ps1 typecheck npm run typecheck
#   pwsh -File scripts/gate.ps1 -ProveRed typecheck npm run typecheck
#
# Output, always exactly one line on stdout:
#   GATE <label> EXIT <code> LOG <path> LINES <n>

[CmdletBinding()]
param(
    [switch]$ProveRed,
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Label,
    [Parameter(Mandatory = $true, Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Command
)

$ErrorActionPreference = 'Continue'

if ($Label -notmatch '^[A-Za-z0-9_.-]+$') {
    Write-Error "gate.ps1: label must match [A-Za-z0-9_.-]+, got: $Label"
    exit 64
}

$outDir = $env:GATE_LOG_DIR
if ([string]::IsNullOrWhiteSpace($outDir)) { $outDir = $env:TEMP }
if ([string]::IsNullOrWhiteSpace($outDir)) { $outDir = '.' }
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$log = Join-Path $outDir "gate-$Label.log"

$exe = $Command[0]
$rest = @()
if ($Command.Count -gt 1) { $rest = $Command[1..($Command.Count - 1)] }

# Start-Process keeps the native stderr out of PowerShell's error stream, so a
# clean exit 0 cannot be turned into a failure by the redirect itself.
$errLog = "$log.err"
$proc = Start-Process -FilePath $exe -ArgumentList $rest -NoNewWindow -Wait -PassThru `
    -RedirectStandardOutput $log -RedirectStandardError $errLog
$code = $proc.ExitCode

if (Test-Path -LiteralPath $errLog) {
    Get-Content -LiteralPath $errLog -ErrorAction SilentlyContinue | Add-Content -LiteralPath $log -Encoding utf8
    Remove-Item -LiteralPath $errLog -Force -ErrorAction SilentlyContinue
}

$lines = 0
if (Test-Path -LiteralPath $log) {
    $lines = (Get-Content -LiteralPath $log | Measure-Object -Line).Lines
}

Write-Output "GATE $Label EXIT $code LOG $log LINES $lines"

if ($ProveRed) {
    if ($code -eq 0) {
        Write-Error "GATE $Label PROVE_RED INCONCLUSIVE - ran clean; re-run against a known-bad input"
    }
    else {
        Write-Error "GATE $Label PROVE_RED OK - this gate can return non-zero"
    }
}

exit $code
