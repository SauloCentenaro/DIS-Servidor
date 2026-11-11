[CmdletBinding()]
param(
  [ValidateSet('smoke','baseline','load','stress','spike','soak','breakpoint')]
  [string]$Experiment = 'smoke',
  [double]$Rate,
  [int]$Repetitions = 1,
  [string]$Duration,
  [string]$Payload = 'k6/payloads/dis-request.json'
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$arguments = @(
  'stresser+benchmarker/scripts/benchmark.py', 'suite',
  '--targets', 'cpp,elixir', '--experiments', $Experiment,
  '--repetitions', $Repetitions, '--order', 'alternate', '--payload', $Payload
)
if ($PSBoundParameters.ContainsKey('Rate')) { $arguments += @('--rate', $Rate) }
if ($Duration) { $arguments += @('--duration', $Duration) }
& py -3 @arguments
exit $LASTEXITCODE
