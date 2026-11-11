[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Targets,
  [Parameter(Mandatory)][string]$Experiments,
  [int]$Repetitions = 1,
  [ValidateSet('fixed','alternate','random')][string]$Order = 'alternate',
  [double]$Rate, [string]$Duration, [string]$Warmup, [string]$Cooldown,
  [string]$Payload, [string]$TargetsFile, [string]$ExperimentsFile, [string]$ThresholdsFile,
  [string[]]$Set,
  [switch]$InsecureTls, [switch]$RestartTarget
)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$arguments = @('scripts/benchmark.py','suite','--targets',$Targets,'--experiments',$Experiments,'--repetitions',$Repetitions,'--order',$Order)
foreach ($item in @(@('rate',$Rate),@('duration',$Duration),@('warmup',$Warmup),@('cooldown',$Cooldown),@('payload',$Payload),@('targets-file',$TargetsFile),@('experiments-file',$ExperimentsFile),@('thresholds-file',$ThresholdsFile))) {
  if ($null -ne $item[1] -and "$($item[1])" -ne '' -and "$($item[1])" -ne '0') { $arguments += @("--$($item[0])", "$($item[1])") }
}
if ($InsecureTls) { $arguments += '--insecure-tls' }
if ($RestartTarget) { $arguments += '--restart-target' }
foreach ($override in $Set) { $arguments += @('--set',$override) }
& python @arguments
exit $LASTEXITCODE
