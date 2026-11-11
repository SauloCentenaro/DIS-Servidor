[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Target,
  [Parameter(Mandatory)][string]$Experiment,
  [double]$Rate, [string]$Duration, [string]$Warmup, [string]$Cooldown,
  [string]$Payload, [string]$BaseUrl, [int]$Repetition = 1,
  [string]$TargetsFile, [string]$ExperimentsFile, [string]$ThresholdsFile,
  [string]$ApplicationCommit, [string]$Dataset,
  [string[]]$Set,
  [switch]$InsecureTls, [switch]$RestartTarget
)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$arguments = @('scripts/benchmark.py','run','--target',$Target,'--experiment',$Experiment,'--repetition',$Repetition)
foreach ($item in @(@('rate',$Rate),@('duration',$Duration),@('warmup',$Warmup),@('cooldown',$Cooldown),@('payload',$Payload),@('base-url',$BaseUrl),@('targets-file',$TargetsFile),@('experiments-file',$ExperimentsFile),@('thresholds-file',$ThresholdsFile),@('application-commit',$ApplicationCommit),@('dataset',$Dataset))) {
  if ($null -ne $item[1] -and "$($item[1])" -ne '' -and "$($item[1])" -ne '0') { $arguments += @("--$($item[0])", "$($item[1])") }
}
if ($InsecureTls) { $arguments += '--insecure-tls' }
if ($RestartTarget) { $arguments += '--restart-target' }
foreach ($override in $Set) { $arguments += @('--set',$override) }
& python @arguments
exit $LASTEXITCODE
