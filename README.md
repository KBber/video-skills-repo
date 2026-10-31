# video-skills

把 5 套视频类 Agent Skills 打包成可一键部署的仓库：克隆或一行命令，即可把 26 个技能装进本机 MiniMax Code（以及任何兼容 Agent Skills 规范的 Agent）。

| 合集 | 定位 | 技能数 | 上游 |
| --- | --- | --- | --- |
| HyperFrames | 动效生成 | 5 | [heygen-com/hyperframes](https://github.com/heygen-com/hyperframes) |
| Video Use | 素材后期 | 1 | [browser-use/video-use](https://github.com/browser-use/video-use) |
| Remotion | 批量视频 | 12 | [remotion-dev/skills](https://github.com/remotion-dev/skills) |
| Generative Media | 多模态素材 | 1 | [Lynricsy/HyperSkills](https://github.com/Lynricsy/HyperSkills) |
| Video Cut | 中文剪辑 | 7 | [Ceeon/videocut-skills](https://github.com/Ceeon/videocut-skills) |
| **合计** | | **26** | |

---

## 一键部署

### Windows（PowerShell 5.1+）

```powershell
curl.exe -fsSL --retry 3 --retry-all-errors -o install.ps1 https://raw.githubusercontent.com/KBber/video-skills-repo/main/install.ps1; .\install.ps1
```

本机 TLS 正常的话，也可以直接管道执行：

```powershell
iwr -useb https://raw.githubusercontent.com/KBber/video-skills-repo/main/install.ps1 | iex
```

> **为什么推荐先下载再执行**：PowerShell 5.1 的 `Invoke-WebRequest` 在部分网络/代理环境下会 TLS 握手中断
> （报「基础连接已经关闭」），而 `curl.exe` 自带重试、能扛住抖动；
> 下载到文件再执行还能避免「半截脚本被 `iex` 解析」这类难懂的报错。装完可删掉 `install.ps1`。

### macOS / Linux

```bash
curl -fsSL --retry 3 --retry-all-errors https://raw.githubusercontent.com/KBber/video-skills-repo/main/install.sh | bash
```

### 克隆后本地执行

```bash
git clone https://github.com/KBber/video-skills-repo.git
cd video-skills-repo
powershell -ExecutionPolicy Bypass -File install.ps1    # Windows
bash install.sh                                        # macOS / Linux
```

安装程序会自动完成：

1. 把 `skills/` 与 `plugins/` 同构复制到 `<数据目录>/skills/`
2. 调用 `verify` 按 **MiniMax Code 运行时的真实 skill 发现规则**体检
3. 检查 Node ≥ 22 / FFmpeg / Python，并为 **video-use** 建独立虚拟环境装依赖
4. 安装 **Bun ≥ 1.2** 并激活 **chengfeng-videocut Runtime**

> 数据目录默认 `%USERPROFILE%\.minimax`（Windows）/ `~/.minimax`（Unix）。
> 私有仓库请先设 `VIDEO_SKILLS_TOKEN` 或 `GITHUB_TOKEN`。

### ⚠️ 装完必须重开一个会话

MiniMax Code 在**会话启动时**扫描技能目录，新装的技能不会出现在当前会话里。
重开后即可点名调用（`用 hyperframes 做一个 30 秒片头`），也可以只描述需求由 Agent 自行匹配。

---

## 单个技能安装（skills.sh CLI）

仓库内 `skills/<name>/SKILL.md` 的布局兼容 skills.sh / Agent Skills 规范，可以只装需要的：

```bash
npx skills add https://github.com/KBber/video-skills-repo --skill hyperframes
npx skills add https://github.com/KBber/video-skills-repo --skill video-use
```

> **Video Cut 的 7 个技能请用 `install.ps1` / `install.sh` 整包安装。**
> 它们依赖插件结构（`scripts/`、`references/`、`.codex-plugin/`），
> 单独复制会破坏「从 SKILL.md 向上两级 = 插件根」的路径推导。

---

## 技能清单

### HyperFrames —— HTML 写代码，渲染成视频
用 HTML/CSS/GSAP 写动效合成，逐帧确定性渲染成 MP4/WebM。适合片头、字幕条、图表、产品演示、竖屏短片。

| 技能 | 作用 |
| --- | --- |
| `hyperframes` | 主技能：合成契约与工作流 |
| `hyperframes-cli` | CLI 按活分工：init/lint/validate/inspect/preview/render/publish |
| `hyperframes-registry` | 约 450 个现成动效块（转场、遮罩、图表、卡片） |
| `media-use` | 取用或生成素材：音乐、音效、图片、Logo、配音、数字人 |
| `remotion-to-hyperframes` | 把 Remotion 代码或素材迁到 HyperFrames 并逐帧校验 |

```bash
npx hyperframes init my-video
npx hyperframes lint
npx hyperframes render --output final.mp4
```

### Video Use —— 对话式剪素材
把素材丢进文件夹，说一句「剪成发布视频」就出片。核心是让 LLM 读逐词转录稿，而不是逐帧看画面。

| 技能 | 作用 |
| --- | --- |
| `video-use` | 转录、剪切、调色、叠加动画、烧字幕 |

```bash
python .venv/bin/python helpers/transcribe.py <video>   # Unix
.venv\Scripts\python.exe helpers\transcribe.py <video>  # Windows
```

> `helpers/` 必须与 `SKILL.md` 同级（合集已保持这个结构）。

### Remotion —— React 写视频，批量出片
用 React 组件 + spring 物理动画描述视频，渲染 MP4/GIF。适合产品演示、数据看板、可复现动效。

| 技能 | 作用 |
| --- | --- |
| `remotion-best-practices` | **总路由**，按需求分发 |
| `remotion-create` | 新建 Remotion 视频工程 |
| `remotion-markup` | React 标记与动效最佳实践 |
| `remotion-render` | 渲染导出 MP4 |
| `remotion-captions` | 字幕转录、显示与动效 |
| `remotion-multimedia` | 浏览器内多媒体处理（裁剪/元数据/Mediabunny） |
| `remotion-maps` | 地图、路线、地理动效 |
| `remotion-interactivity` | Studio 内交互与回写代码 |
| `remotion-studio` | 打开交互预览 |
| `remotion-saas` | 用 Remotion 做应用/SaaS |
| `remotion-docs` | 查官方文档 |
| `remotion-upgrade` | 升级 Remotion 与相关包 |

```bash
npx create-video@latest
npx remotion studio
npx remotion render
```

### Generative Media —— 多模态素材生成的通用管线
图像/视频/语音/音乐的生成与转录怎么调：运行时解析模型 ID、按各家 schema 构造请求、作业生命周期与成本控制、种子与版本复现、溯源与披露义务。

| 技能 | 作用 |
| --- | --- |
| `generative-media` | 生成与转录管线的正确性/可复现性/可审计规则 |

纯 Markdown，无需本地运行时。

### Video Cut —— 中文口播剪辑
中文口播专用流水线：逐词转录 → 词典修字 → 扫口误重复 → 出删词账本 → 人工复核 → 字幕 → 配画面 → 烧成成片。

| 技能 | 作用 |
| --- | --- |
| `chengfeng-cut` | 剪口播：出删词账本并复核 |
| `chengfeng-subtitle` | 字幕：算剪后时间、按句分屏、词典纠错 |
| `chengfeng-visual` | 画面/分镜：录屏上盖 HTML 层 |
| `chengfeng-export` | 导出：切片段 + 推近 + 字幕 + 画面一次烧成 mp4 |
| `chengfeng-videocut-workbench` | 时间线操作：插入/删除/拆分/移动/换比例 |
| `chengfeng-check-updates` | 环境总管：就绪检查、Runtime 体检 |
| `chengfeng-report-bug` | 整理脱敏并上报 Issue |

```bash
node "<插件根>/scripts/videocut-cli.cjs" doctor --json
```

---

## 目录结构

```
video-skills-repo/
├── install.ps1 / install.sh      一键部署（Windows / Unix）
├── verify.ps1  / verify.sh       独立体检：按运行时规则列出可调用技能
├── uninstall.ps1 / uninstall.sh  卸载（只删本包列出的顶层目录）
├── manifest.json                 技能清单：名称/说明/落地路径/上游/依赖/密钥
├── tools/validate_skills.py      仓库自检：manifest 与技能目录是否一致
├── .github/workflows/validate.yml CI：校验 frontmatter + 跑一遍一键部署
├── NOTICE.md                     上游来源与许可映射
├── LICENSE                       打包脚本的 MIT 许可
└── skills/                       21 个自包含技能（扁平，skills/ 与 skills.sh CLI 兼容）
    ├── hyperframes/  hyperframes-cli/  hyperframes-registry/
    ├── media-use/    remotion-to-hyperframes/
    ├── remotion-best-practices/  remotion-create/  ... (12 个)
    ├── video-use/            （SKILL.md + helpers/ + skills/manim-video/）
    └── generative-media/
└── plugins/
    └── chengfeng-videocut/            Video Cut 完整插件结构（整目录）
        ├── .codex-plugin/  scripts/  references/  skills/  dist/  public/
```

仓库内不含 `.git` / `.venv` / `node_modules`；`video-use` 的虚拟环境在安装时按需创建。

### 安装后落在哪

安装器把仓库的 `skills/*` 与 `plugins/*` **顶层条目**复制到 `<数据目录>/skills/`：

| 仓库内 | 安装后 |
| --- | --- |
| `skills/hyperframes/` | `<数据目录>/skills/hyperframes/` |
| `skills/remotion-create/` | `<数据目录>/skills/remotion-create/` |
| `skills/video-use/` | `<数据目录>/skills/video-use/` |
| `plugins/chengfeng-videocut/` | `<数据目录>/skills/chengfeng-videocut/` |

所以 Video Cut 的插件根是 `<数据目录>/skills/chengfeng-videocut/`，
它的 7 个技能在 `<数据目录>/skills/chengfeng-videocut/skills/` 下 ——
**必须整包安装**，单独复制某个技能目录会破坏「从 SKILL.md 向上两级 = 插件根」的推导。

---

## 系统要求

| 组件 | 要求 | 安装脚本行为 |
| --- | --- | --- |
| Node.js | ≥ 22 | 只检测，不代装（HyperFrames 硬性要求） |
| FFmpeg + FFprobe | 任意现代版本 | 只检测，不代装（视频处理硬性要求） |
| Python | ≥ 3.10 | 只检测；video-use 用它建独立 venv |
| Bun | ≥ 1.2 | **自动安装**（winget → npm 官方平台包 → 官方安装脚本，三级回退） |

Python 依赖安装耗时较长（numpy / scipy / librosa 等），首次约 1–3 分钟。

---

## 还需要三个密钥

技能本身不需要密钥，**实际调用生成/转录接口时**才需要：

| 技能 | 密钥 | 写到哪里 |
| --- | --- | --- |
| video-use | `ELEVENLABS_API_KEY` | `<数据目录>/skills/video-use/.env`（模板 `.env.example` 已在包里） |
| videocut | 火山引擎 API Key | `node "<插件根>/scripts/videocut-cli.cjs" config set transcription.apiKey <key>` |
| generative-media | 各 provider 的 API Key | 按目标 provider 提供 |

---

## 体检与卸载

```powershell
powershell -ExecutionPolicy Bypass -File verify.ps1     # Windows
bash verify.sh                                          # macOS / Linux
```

```powershell
powershell -ExecutionPolicy Bypass -File uninstall.ps1   # Windows
bash uninstall.sh                                        # macOS / Linux
```

卸载只删除 `manifest.json` 里列出的**顶层目录**，不会碰数据目录里的其它内容。
Video Cut 的顶层目录 `chengfeng-videocut` 会整块删除（含 `scripts/`、`references/`）。

体检不是「文件存在即通过」，而是**复刻 MiniMax Code 运行时的 skill 发现规则**
实际扫一遍目录，再与 `manifest.json` 比对，所以它能真实反映「重开会话后能不能点名调用」。

### 仓库自检（改动仓库后跑一下）

```bash
python3 tools/validate_skills.py
```

校验 `manifest.json` 与 `skills/`、`plugins/` 是否一致：每个技能的 frontmatter
`name` / `description` 是否齐备、`name` 是否符合 `^[a-z0-9-]+$`、
目录名与 `name` 是否一致、有没有漏登记或重名。
GitHub Actions 会在每次 push 时自动跑它，并顺带在 Ubuntu / Windows 上各做一遍
「安装 → 体检」冒烟测试（含远程下载链路）。

---

## 离线 / 内网镜像部署

如果拿不到 GitHub，可以直接给安装器一个 zip 地址：

```powershell
$env:VIDEO_SKILLS_ZIP_URL = 'https://mirror.example.com/video-skills-repo.zip'
curl.exe -fsSL --retry 3 --retry-all-errors -o install.ps1 https://raw.githubusercontent.com/KBber/video-skills-repo/main/install.ps1; .\install.ps1
```

```bash
VIDEO_SKILLS_TARBALL_URL=https://mirror.example.com/video-skills-repo.tar.gz \
  bash <(curl -fsSL --retry 3 https://raw.githubusercontent.com/KBber/video-skills-repo/main/install.sh)
```

私有仓库请设置 `GITHUB_TOKEN`（或 `VIDEO_SKILLS_TOKEN`），安装器会带上 `Authorization` 头。

---

## 更新

```bash
git pull
powershell -ExecutionPolicy Bypass -File install.ps1     # 或 bash install.sh
```

技能文件会被覆盖更新；`video-use` 的 `.venv` 保留，`pip install -e` 会按新的 `pyproject.toml` 重新对齐依赖。

---

## 上游与许可

本仓库只做**打包与部署**，所有技能内容版权归各自上游作者，许可见 [NOTICE.md](NOTICE.md)。
各技能目录内保留了自己的 `LICENSE` 文件。
