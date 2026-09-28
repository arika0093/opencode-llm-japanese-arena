# Configlue README 日本語生成ベンチマーク

- 情報源: [context.md](./context.md)（このリポジトリを調査した固定コンテキスト）
- 指示: [instruction.md](./instruction.md)（概要・主な特徴・基本的な使い方の3部のみ、Markdownのみ出力）
- モデル: 各ファミリーの最新版 23件

| # | モデル | 出力ファイル | 秒 | 文字数 | 出力tok | 推論tok | コスト(USD) |
|---|---|---|---:|---:|---:|---:|---:|
| 1 | `opencode-go/deepseek-v4.1-flash` | [opencode-go-deepseek-v4.1-flash.md](./output/opencode-go-deepseek-v4.1-flash.md) | 12.5 | 7581 | 3083 | 106 | 0.003936 |
| 2 | `opencode-go/glm-5.3` | [opencode-go-glm-5.3.md](./output/opencode-go-glm-5.3.md) | 134.9 | 7697 | 3189 | 6100 | 0.061711 |
| 3 | `opencode-go/glm-5.3-flash` | [opencode-go-glm-5.3-flash.md](./output/opencode-go-glm-5.3-flash.md) | 523.2 | 8391 | 16694 | 0 | 0.010595 |
| 4 | `opencode-go/gpt-6-luna` | [opencode-go-gpt-6-luna.md](./output/opencode-go-gpt-6-luna.md) | 18.1 | 3967 | 1501 | 269 | 0.002472 |
| 5 | `opencode-go/grok-4.7` | [opencode-go-grok-4.7.md](./output/opencode-go-grok-4.7.md) | 165.4 | 7937 | 3192 | 11363 | 0.11397 |
| 6 | `opencode-go/hy4-preview` | [opencode-go-hy4-preview.md](./output/opencode-go-hy4-preview.md) | 61.4 | 7891 | 3155 | 229 | 0.020693 |
| 7 | `opencode-go/kimi-k3` | [opencode-go-kimi-k3.md](./output/opencode-go-kimi-k3.md) | 39.8 | 6494 | 2679 | 507 | 0.091377 |
| 8 | `opencode-go/longcat-2.5-preview-free` | [opencode-go-longcat-2.5-preview-free.md](./output/opencode-go-longcat-2.5-preview-free.md) | 50.4 | 6401 | 2511 | 355 | 0 |
| 9 | `opencode-go/mimo-v2.6-flash` | [opencode-go-mimo-v2.6-flash.md](./output/opencode-go-mimo-v2.6-flash.md) | 56 | 6706 | 2765 | 51 | 0.002095 |
| 10 | `opencode-go/mimo-v2.6-pro` | [opencode-go-mimo-v2.6-pro.md](./output/opencode-go-mimo-v2.6-pro.md) | 44 | 7717 | 3216 | 56 | 0.009526 |
| 11 | `opencode-go/minimax-m3` | [opencode-go-minimax-m3.md](./output/opencode-go-minimax-m3.md) | 18.9 | 7382 | 2473 | 2858 | 0.010107 |
| 12 | `opencode-go/muse-spark-1.3-contributor` | [opencode-go-muse-spark-1.3-contributor.md](./output/opencode-go-muse-spark-1.3-contributor.md) | 32.2 | 7217 | 2580 | 804 | 0.002093 |
| 13 | `opencode-go/qwen3.8-flash` | [opencode-go-qwen3.8-flash.md](./output/opencode-go-qwen3.8-flash.md) | 48.9 | 6752 | 3340 | 0 | 0.004554 |
| 14 | `opencode-go/qwen3.8-max` | [opencode-go-qwen3.8-max.md](./output/opencode-go-qwen3.8-max.md) | 66.8 | 7796 | 2930 | 650 | 0.051344 |
| 15 | `opencode-go/space-bunny-free` | [opencode-go-space-bunny-free.md](./output/opencode-go-space-bunny-free.md) | 19.1 | 7323 | 2425 | 0 | 0 |
| 16 | `opencode/big-pickle` | [opencode-big-pickle.md](./output/opencode-big-pickle.md) | 17.7 | 7621 | 2538 | 32 | 0 |
| 17 | `opencode/ling-3.0-flash-fin-free` | [opencode-ling-3.0-flash-fin-free.md](./output/opencode-ling-3.0-flash-fin-free.md) | 6.7 | 3591 | 1448 | 104 | 0 |
| 18 | `opencode/longcat-2.5-preview-free` | [opencode-longcat-2.5-preview-free.md](./output/opencode-longcat-2.5-preview-free.md) | 58.5 | 7472 | 2883 | 429 | 0 |
| 19 | `opencode/mimo-v2.6-flash-free` | [opencode-mimo-v2.6-flash-free.md](./output/opencode-mimo-v2.6-flash-free.md) | 44.7 | 6400 | 2633 | 60 | 0 |
| 20 | `opencode/muse-spark-1.3-contributor-free` | [opencode-muse-spark-1.3-contributor-free.md](./output/opencode-muse-spark-1.3-contributor-free.md) | 32.3 | 6909 | 2426 | 754 | 0 |
| 21 | `opencode/nemotron-3-ultra-free` | [opencode-nemotron-3-ultra-free.md](./output/opencode-nemotron-3-ultra-free.md) | 164.4 | 6311 | 2756 | 96 | 0 |
| 22 | `opencode/nemotron-3.5-lightning-free` | [opencode-nemotron-3.5-lightning-free.md](./output/opencode-nemotron-3.5-lightning-free.md) | 145.5 | 5155 | 2110 | 845 | 0 |
| 23 | `opencode/space-bunny-free` | [opencode-space-bunny-free.md](./output/opencode-space-bunny-free.md) | 18.1 | 7152 | 2364 | 0 | 0 |

