$root = (Resolve-Path "$PSScriptRoot\..").Path
$port = 8934
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()
Write-Host "Serving $root on http://localhost:$port/"
$mime = @{ ".html"="text/html"; ".js"="text/javascript"; ".css"="text/css"; ".json"="application/json"; ".sql"="text/plain"; ".md"="text/plain" }
while ($listener.IsListening) {
  $context = $listener.GetContext()
  try {
    $req = $context.Request
    $res = $context.Response
    $res.KeepAlive = $false
    $path = $req.Url.LocalPath
    if ($path -eq "/") { $path = "/index.html" }
    $filePath = Join-Path $root ($path.TrimStart("/"))
    Write-Host ("{0} {1} -> {2}" -f $req.HttpMethod, $path, $filePath)
    if (Test-Path $filePath -PathType Leaf) {
      $ext = [System.IO.Path]::GetExtension($filePath)
      $ct = $mime[$ext]
      if (-not $ct) { $ct = "application/octet-stream" }
      $res.ContentType = $ct
      $bytes = [System.IO.File]::ReadAllBytes($filePath)
      $res.ContentLength64 = [int64]$bytes.Length
      if ($req.HttpMethod -ne "HEAD") {
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
      }
    } else {
      $res.StatusCode = 404
      $res.ContentLength64 = 0
    }
  } catch {
    Write-Host "Request error: $_"
  } finally {
    $context.Response.OutputStream.Close()
  }
}
