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

$payloadPath = 'stresser+benchmarker/k6/payloads/dis-request.json'
if (-not (Test-Path -LiteralPath $payloadPath)) {
  throw "Payload ausente: $payloadPath. Gere-o conforme README.md."
}
& py -3 scripts/compare_backends.py --payload $payloadPath --output stresser+benchmarker/results/backend-parity.json
if ($LASTEXITCODE -ne 0) { throw "Comparação entre backends falhou com código $LASTEXITCODE." }
Write-Output 'PASS: saúde, recursos idênticos e paridade lógica C++/Elixir'
