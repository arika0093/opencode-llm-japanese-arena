$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$bench = $PSScriptRoot
$outDir = Join-Path $bench 'output'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$contextPath = Join-Path $bench 'context.md'
$instruction = Get-Content (Join-Path $bench 'instruction.md') -Raw
$opencodeExe = Join-Path (Split-Path (Get-Command opencode).Source) 'node_modules\opencode-ai\bin\opencode.exe'

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
    $outDir = $using:outDir
    $contextPath = $using:contextPath
    $instruction = $using:instruction
    $opencodeExe = $using:opencodeExe
    $safe = ($model -replace '[\\/:]', '-')
    $target = Join-Path $outDir "$safe.md"
    $metrics = Join-Path $outDir "$safe.metrics.txt"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $opencodeExe
        foreach ($a in @('run', '-m', $model, '--format', 'json', $instruction, '-f', $contextPath)) {
            $psi.ArgumentList.Add($a)
        }
        $psi.WorkingDirectory = $bench
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
        $cost = 0.0; $inTok = 0; $outTok = 0; $reasonTok = 0
        foreach ($line in ($stdout -split "`n")) {
            $t = $line.Trim()
            if (-not $t.StartsWith('{')) { continue }
            try { $ev = $t | ConvertFrom-Json } catch { continue }
            if ($ev.type -eq 'text' -and $ev.part.text) { $texts.Add([string]$ev.part.text) }
            elseif ($ev.type -eq 'step_finish') {
                $cost += [double]$ev.part.cost
                $inTok += [int]$ev.part.tokens.input
                $outTok += [int]$ev.part.tokens.output
                $reasonTok += [int]$ev.part.tokens.reasoning
            }
        }
        $text = ($texts -join '')
        if ([string]::IsNullOrWhiteSpace($text)) {
            $header = "<!-- 出力取得失敗: $model -->`n`n"
            $text = $header + "STDERR:`n" + $stderr
        }
        Set-Content -LiteralPath $target -Value $text -Encoding UTF8
        Set-Content -LiteralPath $metrics -Encoding UTF8 -Value @(
            "model=$model",
            "elapsed_sec=$([math]::Round($sw.Elapsed.TotalSeconds,1))",
            "cost_usd=$([math]::Round($cost,6))",
            "input_tokens=$inTok",
            "output_tokens=$outTok",
            "reasoning_tokens=$reasonTok",
            "chars=$($text.Length)"
        )
        "OK   $model  ($([math]::Round($sw.Elapsed.TotalSeconds,1))s, $($text.Length) chars)"
    }
    catch {
        $sw.Stop()
        Set-Content -LiteralPath $target -Encoding UTF8 -Value "<!-- 実行失敗: $model -->`n`n$($_.Exception.Message)"
        "FAIL $model : $($_.Exception.Message)"
    }
}
