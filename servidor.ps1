# Servidor HTTP para Prode Mundial 2026
# Incluye proxy para football-data.org (resuelve CORS)

$port = 8080
$root = $PSScriptRoot

$mime = @{
    '.html' = 'text/html; charset=utf-8'
    '.css'  = 'text/css'
    '.js'   = 'application/javascript; charset=utf-8'
    '.json' = 'application/json'
    '.ico'  = 'image/x-icon'
    '.png'  = 'image/png'
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://*:$port/")
$listener.Start()

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Green
Write-Host "    Prode Mundial 2026 - Servidor iniciado" -ForegroundColor Green
Write-Host "  ============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  URL: http://localhost:$port" -ForegroundColor Cyan
Write-Host "  Cerra esta ventana para detener el servidor." -ForegroundColor Gray
Write-Host ""

Start-Process "http://localhost:$port"

function Send-Json($resp, $code, $json) {
    $data = [System.Text.Encoding]::UTF8.GetBytes($json)
    $resp.ContentType = 'application/json; charset=utf-8'
    $resp.Headers.Add('Access-Control-Allow-Origin', '*')
    $resp.StatusCode      = $code
    $resp.ContentLength64 = $data.Length
    $resp.OutputStream.Write($data, 0, $data.Length)
    $resp.Close()
}

function Proxy-FootballData($resp, $apiUrl, $apiKey, $logLabel) {
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('X-Auth-Token', $apiKey)
        $wc.Encoding = [System.Text.Encoding]::UTF8
        $json = $wc.DownloadString($apiUrl)
        Send-Json $resp 200 $json
        Write-Host "  [API] $logLabel OK" -ForegroundColor Green
    } catch {
        $msg = '{"error":"' + $_.Exception.Message.Replace('"','\"') + '"}'
        Send-Json $resp 500 $msg
        Write-Host "  [API] Error $logLabel : $($_.Exception.Message)" -ForegroundColor Red
    }
}

while ($listener.IsListening) {
    try {
        $ctx  = $listener.GetContext()
        $req  = $ctx.Request
        $resp = $ctx.Response

        $path = $req.Url.LocalPath.TrimStart('/')

        # -- Proxy: lista de partidos del Mundial (resultados) --
        if ($path -eq 'api/sync') {
            $apiKey = $req.QueryString['key']
            Proxy-FootballData $resp 'https://api.football-data.org/v4/competitions/WC/matches?stage=GROUP_STAGE' $apiKey 'Sync'
            continue
        }

        # -- Proxy: detalle de un partido (goles, tarjetas, cambios, alineaciones) --
        # Para las stats del Gran DT. id = match id de football-data.
        if ($path -eq 'api/fdmatch') {
            $apiKey  = $req.QueryString['key']
            $matchId = $req.QueryString['id']
            if ($matchId -notmatch '^\d+$') {
                Send-Json $resp 400 '{"error":"id de partido invalido"}'
                continue
            }
            Proxy-FootballData $resp "https://api.football-data.org/v4/matches/$matchId" $apiKey "Detalle $matchId"
            continue
        }

        # -- Archivos estaticos --
        if ([string]::IsNullOrEmpty($path)) { $path = 'index.html' }
        $file = Join-Path $root $path

        if (Test-Path $file -PathType Leaf) {
            $ext  = [System.IO.Path]::GetExtension($file).ToLower()
            $type = if ($mime[$ext]) { $mime[$ext] } else { 'application/octet-stream' }
            $data = [System.IO.File]::ReadAllBytes($file)

            $resp.ContentType     = $type
            $resp.ContentLength64 = $data.Length
            $resp.StatusCode      = 200
            $resp.OutputStream.Write($data, 0, $data.Length)
            $resp.Close()
        } else {
            $msg  = [System.Text.Encoding]::UTF8.GetBytes('404 Not Found')
            $resp.StatusCode      = 404
            $resp.ContentLength64 = $msg.Length
            $resp.OutputStream.Write($msg, 0, $msg.Length)
            $resp.Close()
        }
    } catch { }
}
