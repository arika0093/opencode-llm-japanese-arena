$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$bench = $PSScriptRoot
$contextPath = Join-Path $bench 'context.md'
$instruction = (Get-Content (Join-Path $bench 'instruction.md') -Raw).Trim()
$opencodeExe = Join-Path (Split-Path (Get-Command opencode).Source) 'node_modules\opencode-ai\bin\opencode.exe'
$workRoot = Join-Path $bench 'work'
$outRoot = Join-Path $bench 'output'
New-Item -ItemType Directory -Force -Path $workRoot, $outRoot | Out-Null

$models = @(
    'opencode/big-pickle',
    'opencode/ling-3.0-flash-fin-free',
    'opencode/longcat-2.5-preview-free',
    'opencode/mimo-v2.6-flash-free',
    'opencode/muse-spark-1.3-contributor-free',
    'opencode/nemotron-3-ultra-free',
    'opencode/nemotron-3.5-lightning-free',
    'opencode/space-bunny-free',
    'opencode-go/deepseek-v4.1-flash',
    'opencode-go/glm-5.3',
    'opencode-go/glm-5.3-flash',
    'opencode-go/gpt-6-luna',
    'opencode-go/grok-4.7',
    'opencode-go/hy4-preview',
    'opencode-go/kimi-k3',
    'opencode-go/longcat-2.5-preview-free',
    'opencode-go/mimo-v2.6-flash',
    'opencode-go/mimo-v2.6-pro',
    'opencode-go/minimax-m3',
    'opencode-go/muse-spark-1.3-contributor',
    'opencode-go/qwen3.8-flash',
    'opencode-go/qwen3.8-max',
    'opencode-go/space-bunny-free'
)

$models | ForEach-Object -ThrottleLimit 4 -Parallel {
    $model = $_
    $bench = $using:bench
    $contextPath = $using:contextPath
    $instruction = $using:instruction
    $opencodeExe = $using:opencodeExe
    $workRoot = $using:workRoot
    $outRoot = $using:outRoot
    $safe = ($model -replace '[\\/:]', '-')
    $wd = Join-Path $workRoot $safe
    $od = Join-Path $outRoot $safe
    $stdoutFile = Join-Path $outRoot "$safe.stdout.md"
    $metrics = Join-Path $outRoot "$safe.metrics.txt"
    Remove-Item -Recurse -Force $wd, $od -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $wd, $od | Out-Null
    Copy-Item $contextPath (Join-Path $wd 'context.md') -Force
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $opencodeExe
        foreach ($a in @('run', '-m', $model, '--format', 'json', $instruction, '-f', $contextPath)) {
            $psi.ArgumentList.Add($a)
        }
        $psi.WorkingDirectory = $wd
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
        $p = [System.Diagnostics.Process]::Start($psi)
        $stdout = $p.StandardOutput.ReadToEnd()
        $stderr = $p.StandardError.ReadToEnd()
        if (-not $p.WaitForExit(600000)) {
            try { $p.Kill($true) } catch {}
            throw 'timeout after 600s'
        }
        $sw.Stop()

        $texts = [System.Collections.Generic.List[string]]::new()
        $tools = [System.Collections.Generic.List[string]]::new()
        $cost = 0.0; $inTok = 0; $outTok = 0; $reasonTok = 0
        foreach ($line in ($stdout -split "`n")) {
            $t = $line.Trim()
            if (-not $t.StartsWith('{')) { continue }
            try { $ev = $t | ConvertFrom-Json } catch { continue }
            if ($ev.type -eq 'text' -and $ev.part.text) { $texts.Add([string]$ev.part.text) }
            elseif ($ev.type -eq 'tool') { $tools.Add([string]$ev.part.tool) }
            elseif ($ev.type -eq 'step_finish') {
                $cost += [double]$ev.part.cost
                $inTok += [int]$ev.part.tokens.input
                $outTok += [int]$ev.part.tokens.output
                $reasonTok += [int]$ev.part.tokens.reasoning
            }
        }
        $text = ($texts -join '')
        Set-Content -LiteralPath $stdoutFile -Value $text -Encoding UTF8

        $produced = Get-ChildItem -LiteralPath $wd -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'context.md' }
        $list = [System.Collections.Generic.List[string]]::new()
        foreach ($f in $produced) {
            $rel = $f.FullName.Substring($wd.Length).TrimStart('\')
            $dest = Join-Path $od $rel
            New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
            Copy-Item $f.FullName $dest -Force
            $list.Add("$rel`t$($f.Length)")
        }
        Set-Content -LiteralPath $metrics -Encoding UTF8 -Value @(
            "model=$model",
            "elapsed_sec=$([math]::Round($sw.Elapsed.TotalSeconds,1))",
            "cost_usd=$([math]::Round($cost,6))",
            "input_tokens=$inTok",
            "output_tokens=$outTok",
            "reasoning_tokens=$reasonTok",
            "chat_chars=$($text.Length)",
            "tools=$([string]::Join(',', $tools))",
            "files=$([string]::Join(';', $list))"
        )
        "OK   $model  ($([math]::Round($sw.Elapsed.TotalSeconds,1))s, files=$($produced.Count), chat=$($text.Length))"
    }
    catch {
        $sw.Stop()
        Set-Content -LiteralPath $stdoutFile -Encoding UTF8 -Value "<!-- 実行失敗: $model -->`n`n$($_.Exception.Message)`n`n$stderr"
        "FAIL $model : $($_.Exception.Message)"
    }
}
