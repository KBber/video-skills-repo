# NOTICE —— 上游来源与许可

本仓库是**打包与部署用的合集**：把 5 套视频类 Agent Skills 收拢到一个仓库，
让它们可以被一行命令装进 MiniMax Code（以及任何兼容 Agent Skills 规范的 Agent）。

**仓库作者不主张对 `skills/` 与 `plugins/` 下技能内容的任何权利。**
这些内容全部来自下列上游项目，各自的版权与许可证保持不变，
上游自带的 `LICENSE` / `NOTICE` 文件均已原样保留（未删除、未改写）。

本仓库自身新增的内容只有打包脚本（`install.*` / `verify.*` / `uninstall.*` /
`manifest.json` / `.github/workflows/`），以 MIT License 发布，见 [LICENSE](LICENSE)。

---

## 许可映射

| 合集 | 上游仓库 | 上游许可证 | 仓库内位置 | 技能数 |
| --- | --- | --- | --- | --- |
| HyperFrames | <https://github.com/heygen-com/hyperframes> | Apache-2.0 | `skills/hyperframes*/`、`skills/media-use/`、`skills/remotion-to-hyperframes/` | 5 |
| Video Use | <https://github.com/browser-use/video-use> | MIT | `skills/video-use/` | 1 |
| Remotion | <https://github.com/remotion-dev/skills> | MIT（见下方说明） | `skills/remotion-*/` | 12 |
| Generative Media | <https://github.com/Lynricsy/HyperSkills> | MIT | `skills/generative-media/` | 1 |
| Video Cut | <https://github.com/Ceeon/videocut-skills> | Apache-2.0 | `plugins/chengfeng-videocut/` | 7 |
| | | | **合计** | **26** |

---

## 各上游声明

### HyperFrames — Apache-2.0

- 版权：HeyGen, Inc.
- 来源：<https://github.com/heygen-com/hyperframes>
- npm 包 `hyperframes`（本仓库实测版本 0.8.217）
- 本仓库收录 `skills/hyperframes`、`skills/hyperframes-cli`、`skills/hyperframes-registry`、
  `skills/media-use`、`skills/remotion-to-hyperframes` 五个技能目录。
- Apache-2.0 §4 要求保留许可与 NOTICE 信息；上游仓库中的许可声明已在技能内容中原样保留。

### Video Use — MIT

- 版权：Copyright (c) 2026 Browser Use
- 来源：<https://github.com/browser-use/video-use>
- 技能目录内自带 `LICENSE`（MIT）与 `README.md`、`pyproject.toml`、`helpers/`。
- `skills/video-use/skills/manim-video/` 为同仓库内的附属技能，随主技能一并收录。

### Remotion — MIT

- 来源：<https://github.com/remotion-dev/skills>（对应 monorepo 内的 `packages/skills`）
- 本仓库实测版本 4.0.539。
- **说明**：该 skills 仓库本身未附带独立的 `LICENSE` 文件，其 `package.json` 声明为
  `private: true` 且未写 `license` 字段。Remotion 主仓库 `remotion-dev/remotion`
  采用 MIT License，skills 作为其一部分收录于此。本仓库按 MIT 处理，
  转载或再分发时请以 Remotion 主仓库的许可声明为准。
- `skills/remotion-best-practices/` 内自带各技能的 `REFERENCE.md` 文档树，
  由上游路由技能一并收录。

### Generative Media — MIT

- 版权：Copyright (c) 2026 Lynricsy
- 来源：<https://github.com/Lynricsy/HyperSkills>，取其 `skills/generative-media`
- 技能目录内自带 `NOTICE.md` 与 `SOURCES.yaml`（来源与溯源信息），已原样保留。

### Video Cut — Apache-2.0

- 来源：<https://github.com/Ceeon/videocut-skills>，取其 `plugins/chengfeng-videocut`
- 插件元数据 `.codex-plugin/plugin.json` 声明：`"license": "Apache-2.0"`，
  作者 Chengfeng（<https://github.com/Agentchengfeng>）
- 上游仓库根目录携带 Apache-2.0 `LICENSE`，本仓库**未收录**该根级文件，
  因为插件目录内已由 `plugins/chengfeng-videocut/skills/chengfeng-videocut-workbench/`
  自带 `LICENSE` 与 `NOTICE.md`；使用该子技能时请一并保留这两份文件。
- `chengfeng-videocut-workbench` 的 NOTICE 声明其代码派生自 HyperFrames
  （Copyright 2026 HeyGen, Inc., Apache-2.0），相关声明已随该子目录保留。
- 本仓库对该插件**整目录收录**（含 `scripts/`、`references/`、`.codex-plugin/`、`dist/`、`public/`），
  不得拆分单独分发其技能目录，否则会破坏「从 SKILL.md 向上两级 = 插件根」的路径推导。

---

## 第三方运行时依赖（不由本仓库分发）

安装脚本会引导你安装下列组件，它们**不在本仓库内**，各自适用自己的许可证：

| 组件 | 用途 | 许可证 | 获取方式 |
| --- | --- | --- | --- |
| Node.js ≥ 22 | HyperFrames / Video Cut 脚本运行时 | MIT | <https://nodejs.org> |
| FFmpeg + FFprobe | 音视频处理 | LGPL/GPL（视构建而定） | <https://ffmpeg.org> |
| Python ≥ 3.10 | video-use 依赖运行时 | PSF | <https://python.org> |
| Bun ≥ 1.2 | Video Cut Runtime | MIT | <https://bun.sh> |
| Python 包（numpy / scipy / librosa / matplotlib / pillow …） | video-use 依赖 | 各自许可 | PyPI |
| Video Cut Runtime | Video Cut 后端 | 见上游 | 由插件 `scripts/ensure-runtime.cjs` 安装 |

各 API 服务（ElevenLabs、火山引擎、各生成式 provider）需自行申请密钥并接受其服务条款。

---

## 转发建议

转发本仓库或其安装包时，请**整体保留**本文件与 `LICENSE`，
并保留各上游目录内的 `LICENSE` / `NOTICE.md` / `SOURCES.yaml`。
