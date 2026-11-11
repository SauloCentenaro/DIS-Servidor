[CmdletBinding()]
param([string]$TargetsFile, [string]$ExperimentsFile, [string]$ThresholdsFile)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$arguments = @('scripts/benchmark.py','validate')
foreach ($item in @(@('targets-file',$TargetsFile),@('experiments-file',$ExperimentsFile),@('thresholds-file',$ThresholdsFile))) {
  if ($item[1]) { $arguments += @("--$($item[0])", "$($item[1])") }
}
& python @arguments
exit $LASTEXITCODE
