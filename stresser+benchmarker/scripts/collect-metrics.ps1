[CmdletBinding()]
param([Parameter(Mandatory)][string]$ResultDir, [string]$PrometheusUrl)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$arguments = @('scripts/benchmark.py','collect','--result-dir',$ResultDir)
if ($PrometheusUrl) { $arguments += @('--prometheus-url',$PrometheusUrl) }
& python @arguments
exit $LASTEXITCODE
