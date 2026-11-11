$ErrorActionPreference = 'Stop'

$healthUrls = @(
  'http://localhost:8080/health',
  'http://localhost:8081/health',
  'http://localhost:4200/health',
  'http://localhost:4200/api/cpp/health',
  'http://localhost:4200/api/elixir/health',
  'http://localhost:9090/-/healthy',
  'http://localhost:3000/api/health'
)
foreach ($url in $healthUrls) {
  $response = Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 15
  if ($response.StatusCode -ne 200) { throw "Health inválido: $url" }
  Write-Output "OK $url"
}

$cpp = docker inspect dis-cpp | ConvertFrom-Json
$elixir = docker inspect dis-elixir | ConvertFrom-Json
$resourceFields = @('NanoCpus', 'Memory', 'MemoryReservation', 'PidsLimit')
foreach ($field in $resourceFields) {
  if ($cpp.HostConfig.$field -ne $elixir.HostConfig.$field) {
    throw "Recursos diferentes em ${field}: C++=$($cpp.HostConfig.$field), Elixir=$($elixir.HostConfig.$field)"
  }
}
Write-Output 'OK recursos de container idênticos'

$csvPath = 'DIS-Cliente/src/assets/model2/MODEL1.csv'
if (-not (Test-Path -LiteralPath $csvPath)) {
  throw "Dados ausentes: $csvPath. Consulte README.md."
}
$vector = @(Get-Content -LiteralPath $csvPath | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$body = @{user=930002; model=$false; ganho=$false; vector=$vector} | ConvertTo-Json -Compress
$cppResult = Invoke-RestMethod 'http://localhost:8080/reconstruct' -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 600
$elixirResult = Invoke-RestMethod 'http://localhost:8081/reconstruct' -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 600

if ($cppResult.user -ne $elixirResult.user -or $cppResult.iteracoes -ne $elixirResult.iteracoes) {
  throw 'Divergência de user ou iterações entre C++ e Elixir.'
}
$difference = Compare-Object @($cppResult.imageVector) @($elixirResult.imageVector)
if ($difference) { throw 'Divergência em imageVector entre C++ e Elixir.' }
if ($cppResult.imageVector.Count -notin @(900, 3600)) { throw 'Dimensão de imagem inválida.' }

[pscustomobject]@{
  Status = 'PASS'
  Pixels = $cppResult.imageVector.Count
  Iterations = $cppResult.iteracoes
  CppSeconds = $cppResult.durationSeconds
  ElixirSeconds = $elixirResult.durationSeconds
} | ConvertTo-Json
