param([Parameter(Mandatory=$true)][string]$Gate)
$fail = 0
function Check($name, $got, $wantPrefix, $wantCode, $code) {
    if ($got -like "$wantPrefix*" -and $code -eq $wantCode) { Write-Host "PASS $name" }
    else { Write-Host "FAIL $name: got [$got] code=$code"; $script:fail = 1 }
}
$o = & $Gate -Expect 'ran 3 tests' t-match cmd /c "echo ran 3 tests"; Check 'match' $o 'GATE t-match EXIT 0' 0 $LASTEXITCODE
$o = & $Gate -Expect 'ran 3 tests' t-nomatch cmd /c "echo killed"; Check 'nomatch' $o 'GATE t-nomatch UNDECIDED' 75 $LASTEXITCODE
$o = & $Gate -Expect 'failed' t-red cmd /c "echo 2 failed & exit 1"; Check 'real-red' $o 'GATE t-red EXIT 1' 1 $LASTEXITCODE
$o = & $Gate t-plain cmd /c "echo anything"; Check 'no-flag' $o 'GATE t-plain EXIT 0' 0 $LASTEXITCODE
exit $fail
