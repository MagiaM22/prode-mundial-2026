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

while ($listener.IsListening) {
    try {
        $ctx  = $listener.GetContext()
        $req  = $ctx.Request
        $resp = $ctx.Response

        $path = $req.Url.LocalPath.TrimStart('/')

        # -- Proxy para la API de football-data.org --
        if ($path -eq 'api/sync') {
            $apiKey = $req.QueryString['key']
            $apiUrl = 'https://api.football-data.org/v4/competitions/WC/matches?stage=GROUP_STAGE'

            try {
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add('X-Auth-Token', $apiKey)
                $wc.Encoding = [System.Text.Encoding]::UTF8
                $json = $wc.DownloadString($apiUrl)

                $data = [System.Text.Encoding]::UTF8.GetBytes($json)
                $resp.ContentType = 'application/json; charset=utf-8'
                $resp.Headers.Add('Access-Control-Allow-Origin', '*')
                $resp.StatusCode      = 200
                $resp.ContentLength64 = $data.Length
                $resp.OutputStream.Write($data, 0, $data.Length)
                Write-Host "  [API] Sync OK - $([int]($json | ConvertFrom-Json).matches.Count) partidos" -ForegroundColor Green
            } catch {
                $msg  = '{"error":"' + $_.Exception.Message.Replace('"','\"') + '"}'
                $data = [System.Text.Encoding]::UTF8.GetBytes($msg)
                $resp.ContentType = 'application/json'
                $resp.Headers.Add('Access-Control-Allow-Origin', '*')
                $resp.StatusCode      = 500
                $resp.ContentLength64 = $data.Length
                $resp.OutputStream.Write($data, 0, $data.Length)
                Write-Host "  [API] Error: $($_.Exception.Message)" -ForegroundColor Red
            }
            $resp.Close()
            continue
        }

        # -- Proxy para Sofascore (Gran DT) --
        if ($path -eq 'api/sofascore') {
            $matchId = $req.QueryString['match_id']

            # Mapa fixture: match_id -> fecha y nombres de equipo en ingles para matching
            $fx = @{
                'A1'=@{d='2026-06-11';h='Mexico';a='South Africa'}
                'A2'=@{d='2026-06-11';h='South Korea';a='Czech Republic'}
                'A3'=@{d='2026-06-18';h='Czech Republic';a='South Africa'}
                'A4'=@{d='2026-06-18';h='Mexico';a='South Korea'}
                'A5'=@{d='2026-06-24';h='South Africa';a='South Korea'}
                'A6'=@{d='2026-06-24';h='Czech Republic';a='Mexico'}
                'B1'=@{d='2026-06-12';h='Canada';a='Bosnia'}
                'B2'=@{d='2026-06-13';h='Qatar';a='Switzerland'}
                'B3'=@{d='2026-06-18';h='Switzerland';a='Bosnia'}
                'B4'=@{d='2026-06-18';h='Canada';a='Qatar'}
                'B5'=@{d='2026-06-24';h='Switzerland';a='Canada'}
                'B6'=@{d='2026-06-24';h='Bosnia';a='Qatar'}
                'C1'=@{d='2026-06-13';h='Brazil';a='Morocco'}
                'C2'=@{d='2026-06-13';h='Haiti';a='Scotland'}
                'C3'=@{d='2026-06-19';h='Scotland';a='Morocco'}
                'C4'=@{d='2026-06-19';h='Brazil';a='Haiti'}
                'C5'=@{d='2026-06-24';h='Morocco';a='Haiti'}
                'C6'=@{d='2026-06-24';h='Scotland';a='Brazil'}
                'D1'=@{d='2026-06-12';h='United States';a='Paraguay'}
                'D2'=@{d='2026-06-14';h='Australia';a='Turkey'}
                'D3'=@{d='2026-06-19';h='United States';a='Australia'}
                'D4'=@{d='2026-06-20';h='Turkey';a='Paraguay'}
                'D5'=@{d='2026-06-25';h='Turkey';a='United States'}
                'D6'=@{d='2026-06-25';h='Paraguay';a='Australia'}
                'E1'=@{d='2026-06-14';h='Germany';a='Curacao'}
                'E2'=@{d='2026-06-14';h='Ivory Coast';a='Ecuador'}
                'E3'=@{d='2026-06-20';h='Germany';a='Ivory Coast'}
                'E4'=@{d='2026-06-20';h='Ecuador';a='Curacao'}
                'E5'=@{d='2026-06-25';h='Ecuador';a='Germany'}
                'E6'=@{d='2026-06-25';h='Curacao';a='Ivory Coast'}
                'F1'=@{d='2026-06-14';h='Netherlands';a='Japan'}
                'F2'=@{d='2026-06-14';h='Sweden';a='Tunisia'}
                'F3'=@{d='2026-06-20';h='Netherlands';a='Sweden'}
                'F4'=@{d='2026-06-21';h='Tunisia';a='Japan'}
                'F5'=@{d='2026-06-25';h='Tunisia';a='Netherlands'}
                'F6'=@{d='2026-06-25';h='Japan';a='Sweden'}
                'G1'=@{d='2026-06-15';h='Belgium';a='Egypt'}
                'G2'=@{d='2026-06-15';h='Iran';a='New Zealand'}
                'G3'=@{d='2026-06-21';h='Belgium';a='Iran'}
                'G4'=@{d='2026-06-21';h='New Zealand';a='Egypt'}
                'G5'=@{d='2026-06-27';h='New Zealand';a='Belgium'}
                'G6'=@{d='2026-06-27';h='Egypt';a='Iran'}
                'H1'=@{d='2026-06-15';h='Spain';a='Cape Verde'}
                'H2'=@{d='2026-06-15';h='Saudi Arabia';a='Uruguay'}
                'H3'=@{d='2026-06-21';h='Spain';a='Saudi Arabia'}
                'H4'=@{d='2026-06-21';h='Uruguay';a='Cape Verde'}
                'H5'=@{d='2026-06-26';h='Cape Verde';a='Saudi Arabia'}
                'H6'=@{d='2026-06-26';h='Uruguay';a='Spain'}
                'I1'=@{d='2026-06-16';h='France';a='Senegal'}
                'I2'=@{d='2026-06-16';h='Iraq';a='Norway'}
                'I3'=@{d='2026-06-22';h='France';a='Iraq'}
                'I4'=@{d='2026-06-22';h='Norway';a='Senegal'}
                'I5'=@{d='2026-06-26';h='Norway';a='France'}
                'I6'=@{d='2026-06-26';h='Senegal';a='Iraq'}
                'J1'=@{d='2026-06-16';h='Argentina';a='Algeria'}
                'J2'=@{d='2026-06-17';h='Austria';a='Jordan'}
                'J3'=@{d='2026-06-22';h='Argentina';a='Austria'}
                'J4'=@{d='2026-06-23';h='Jordan';a='Algeria'}
                'J5'=@{d='2026-06-27';h='Algeria';a='Austria'}
                'J6'=@{d='2026-06-27';h='Jordan';a='Argentina'}
                'K1'=@{d='2026-06-17';h='Portugal';a='DR Congo'}
                'K2'=@{d='2026-06-17';h='Uzbekistan';a='Colombia'}
                'K3'=@{d='2026-06-23';h='Portugal';a='Uzbekistan'}
                'K4'=@{d='2026-06-23';h='Colombia';a='DR Congo'}
                'K5'=@{d='2026-06-27';h='Colombia';a='Portugal'}
                'K6'=@{d='2026-06-27';h='DR Congo';a='Uzbekistan'}
                'L1'=@{d='2026-06-17';h='England';a='Croatia'}
                'L2'=@{d='2026-06-17';h='Ghana';a='Panama'}
                'L3'=@{d='2026-06-23';h='England';a='Ghana'}
                'L4'=@{d='2026-06-23';h='Panama';a='Croatia'}
                'L5'=@{d='2026-06-27';h='Panama';a='England'}
                'L6'=@{d='2026-06-27';h='Croatia';a='Ghana'}
            }

            function Send-Json($code, $obj) {
                $json = $obj | ConvertTo-Json -Depth 6
                $data = [System.Text.Encoding]::UTF8.GetBytes($json)
                $resp.ContentType = 'application/json; charset=utf-8'
                $resp.Headers.Add('Access-Control-Allow-Origin', '*')
                $resp.StatusCode      = $code
                $resp.ContentLength64 = $data.Length
                $resp.OutputStream.Write($data, 0, $data.Length)
                $resp.Close()
            }

            if (-not $fx.ContainsKey($matchId)) {
                Send-Json 400 @{ error="match_id '$matchId' no encontrado" }
                continue
            }

            $info = $fx[$matchId]
            $hdrs = @{
                'User-Agent'      = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36'
                'Accept'          = 'application/json, text/plain, */*'
                'Accept-Language' = 'en-US,en;q=0.9'
                'Origin'          = 'https://www.sofascore.com'
                'Referer'         = 'https://www.sofascore.com/'
            }

            try {
                $scheduled = Invoke-RestMethod -Uri "https://api.sofascore.com/api/v1/sport/football/scheduled-events/$($info.d)" -Headers $hdrs
                $events    = $scheduled.events

                $target = $null
                foreach ($ev in $events) {
                    $evH = $ev.homeTeam.name.ToLower()
                    $evA = $ev.awayTeam.name.ToLower()
                    $kH  = $info.h.ToLower()
                    $kA  = $info.a.ToLower()
                    if (($evH -like "*$kH*" -or $kH -like "*$evH*") -and
                        ($evA -like "*$kA*" -or $kA -like "*$evA*")) {
                        $target = $ev; break
                    }
                }

                if (-not $target) {
                    Send-Json 404 @{ error="Partido no encontrado en Sofascore para $($info.d). Quizas aun no esta disponible o el nombre difiere." }
                    continue
                }

                $eid      = $target.id
                $homeName = $target.homeTeam.name
                $awayName = $target.awayTeam.name

                $incData   = Invoke-RestMethod -Uri "https://api.sofascore.com/api/v1/event/$eid/incidents" -Headers $hdrs
                $incidents = $incData.incidents

                $mvpName = $null
                try {
                    $mvpData = Invoke-RestMethod -Uri "https://api.sofascore.com/api/v1/event/$eid/best-player" -Headers $hdrs
                    $mvpName = $mvpData.bestPlayers[0].player.name
                } catch { }

                $ps = @{}
                function EnsurePlayer($name, $team) {
                    if (-not $ps.ContainsKey($name)) {
                        $ps[$name] = @{ player_name=$name; team=$team; goals=0; assists=0; yellow_cards=0; red_cards=0; own_goals=0; minutes_played=0; is_mvp=$false }
                    }
                }

                foreach ($inc in $incidents) {
                    $t    = $inc.incidentType
                    $team = if ($inc.isHome) { $homeName } else { $awayName }
                    if ($t -eq 'goal') {
                        $scorer = $inc.player.name
                        EnsurePlayer $scorer $team
                        if ($inc.incidentClass -eq 'own') { $ps[$scorer].own_goals++ }
                        else {
                            $ps[$scorer].goals++
                            if ($inc.assist1) {
                                $ast = $inc.assist1.name
                                EnsurePlayer $ast $team
                                $ps[$ast].assists++
                            }
                        }
                    }
                    if ($t -eq 'card') {
                        $pl = $inc.player.name; EnsurePlayer $pl $team
                        if ($inc.incidentClass -eq 'yellow')                     { $ps[$pl].yellow_cards++ }
                        if ($inc.incidentClass -eq 'red' -or $inc.incidentClass -eq 'yellowRed') { $ps[$pl].red_cards++ }
                    }
                    if ($t -eq 'substitution') {
                        $pl = $inc.playerOut.name; EnsurePlayer $pl $team
                        $ps[$pl].minutes_played = $inc.time
                    }
                }

                if ($mvpName -and $ps.ContainsKey($mvpName)) { $ps[$mvpName].is_mvp = $true }

                $statsArr = @($ps.Values)
                Send-Json 200 @{ event_id=$eid; home=$homeName; away=$awayName; stats=$statsArr }
                Write-Host "  [Sofascore] $matchId OK -- $($statsArr.Count) jugadores" -ForegroundColor Green
            } catch {
                Send-Json 500 @{ error=$_.Exception.Message }
                Write-Host "  [Sofascore] Error $matchId : $($_.Exception.Message)" -ForegroundColor Red
            }
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
        } else {
            $msg  = [System.Text.Encoding]::UTF8.GetBytes('404 Not Found')
            $resp.StatusCode      = 404
            $resp.ContentLength64 = $msg.Length
            $resp.OutputStream.Write($msg, 0, $msg.Length)
        }

        $resp.Close()
    } catch { }
}
