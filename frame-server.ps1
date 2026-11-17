# Minimaler lokaler Server: liefert Dateien aus diesem Ordner aus und speichert
# per POST /save?name=xyz.jpg gesendete Einzelbilder nach video\frames.
$root = $PSScriptRoot
$out = Join-Path $root 'video\frames'
New-Item -ItemType Directory -Force $out | Out-Null
$l = New-Object System.Net.HttpListener
$l.Prefixes.Add('http://localhost:8765/')
$l.Start()
Write-Host 'Server laeuft auf http://localhost:8765/'
$types = @{ '.html'='text/html; charset=utf-8'; '.mp4'='video/mp4'; '.jpg'='image/jpeg'; '.png'='image/png'; '.js'='text/javascript' }
while ($l.IsListening) {
  $c = $l.GetContext(); $req = $c.Request; $res = $c.Response
  try {
    if ($req.HttpMethod -eq 'POST' -and $req.Url.AbsolutePath -eq '/save') {
      $name = [IO.Path]::GetFileName($req.QueryString['name'])
      $fs = [IO.File]::Create((Join-Path $out $name)); $req.InputStream.CopyTo($fs); $fs.Close()
      $res.StatusCode = 204
    } elseif ($req.Url.AbsolutePath -eq '/preview') {
      # Vorschau der Startseite (index.html ist jetzt ein vollstaendiges HTML-Dokument)
      $bytes = [IO.File]::ReadAllBytes((Join-Path $root 'index.html'))
      $res.ContentType = 'text/html; charset=utf-8'; $res.ContentLength64 = $bytes.Length; $res.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
      $rel = [Uri]::UnescapeDataString($req.Url.AbsolutePath.TrimStart('/'))
      $path = [IO.Path]::GetFullPath((Join-Path $root $rel))
      if (-not $path.StartsWith($root) -or -not (Test-Path $path -PathType Leaf)) { $res.StatusCode = 404 }
      else {
        $ext = [IO.Path]::GetExtension($path).ToLower()
        $res.ContentType = $(if ($types[$ext]) { $types[$ext] } else { 'application/octet-stream' })
        $fs = [IO.File]::OpenRead($path); $len = $fs.Length
        $range = $req.Headers['Range']
        if ($range -match 'bytes=(\d+)-(\d*)') {
          $start = [long]$Matches[1]; $end = $(if ($Matches[2]) { [long]$Matches[2] } else { [Math]::Min($len - 1, $start + 4MB) })
          $res.StatusCode = 206; $res.AddHeader('Content-Range', "bytes $start-$end/$len"); $res.AddHeader('Accept-Ranges', 'bytes')
          $n = $end - $start + 1; $res.ContentLength64 = $n; $fs.Seek($start, 'Begin') | Out-Null
          $buf = New-Object byte[] 65536; while ($n -gt 0) { $r = $fs.Read($buf, 0, [Math]::Min($buf.Length, $n)); if ($r -le 0) { break }; $res.OutputStream.Write($buf, 0, $r); $n -= $r }
        } else { $res.AddHeader('Accept-Ranges', 'bytes'); $res.ContentLength64 = $len; $fs.CopyTo($res.OutputStream) }
        $fs.Close()
      }
    }
  } catch { try { $res.StatusCode = 500 } catch {} }
  try { $res.Close() } catch {}
}
