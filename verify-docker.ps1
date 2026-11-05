$ErrorActionPreference = 'Stop'
foreach ($url in @('http://localhost:8080/health', 'http://localhost:4200/health', 'http://localhost:4200/api/health', 'http://localhost:8081/health')) {
  $result = Invoke-RestMethod $url -TimeoutSec 10
  if ($result.status -ne 'ok') { throw "Health inválido: $url" }
  Write-Output "OK $url"
}
foreach ($url in @('http://localhost:4200', 'http://localhost:8081')) {
  if ((Invoke-WebRequest $url -TimeoutSec 10).StatusCode -ne 200) { throw "Interface indisponível: $url" }
}
$csv = (Invoke-WebRequest http://localhost:4200/assets/model2/MODEL1.csv).Content
$vector = @($csv -split '\r?\n' | Where-Object { $_.Trim() })
foreach ($case in @(@{Url='http://localhost:4200/api'; User=930002}, @{Url='http://localhost:8081/'; User=930012})) {
  $body = @{user=$case.User; model=$false; ganho=$false; vector=$vector} | ConvertTo-Json -Compress
  $result = Invoke-RestMethod $case.Url -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 300
  if ($result.imageVector.Count -ne 900) { throw 'Quantidade incorreta de pixels' }
  if (@($result.imageVector | Where-Object { $_ -lt 0 -or $_ -gt 255 }).Count) { throw 'Pixel inválido' }
  if ($result.iteracoes -gt 20) { throw 'Contagem incorreta de iterações' }
  [pscustomobject]@{Endpoint=$case.Url; Pixels=$result.imageVector.Count; Iterations=$result.iteracoes; Seconds=$result.durationSeconds} | ConvertTo-Json -Compress
}
Write-Output 'PASS: os três sistemas, proxy Angular/C++, CSVs e reconstrução nas duas APIs'
