# easytier-tool

这是一个为了更方便使用 EasyTier 而设计的统一工具仓库，目标是把“准备可执行文件、编写配置、启动组网、查看状态、诊断问题、配置开机自启”这些日常操作收敛成一套一致的目录结构和命令行入口。

它适合用在下面这类场景中：

- 你希望在 macOS、Linux、Termux、Windows 上尽量用同一套方式管理 EasyTier
- 你希望把 create / join 两类节点的配置、状态、日志和启动方式统一下来
- 你希望目标机器只需要拉取仓库、下载或放入二进制、修改 `.env` 配置后就可以直接使用
- 你希望在排查问题时，能直接使用内置的状态查看、入口连通性检查、诊断信息和日志查看能力
- 你希望后续把节点接入开机自启，而不是每台机器都单独手写 systemd、launchd 或其他启动脚本

这个仓库不内置任何 EasyTier 可执行文件，也不再区分平台目录。整个项目只保留一个根目录 `bin/`，你既可以手动把当前机器实际要用的 EasyTier 可执行文件复制进去，也可以直接使用内置的 `download` / `upgrade` 命令从官方 GitHub release 下载后安装到 `bin/`，再按需初始化 `.env` 配置即可。

## 目录结构

```text
easytier-tool/
├── easytierctl
├── bin/
├── env-templates/
│   ├── .env.example
│   ├── .env.executables.example
│   ├── .env.create.example
│   └── .env.join.example
├── lib/
│   ├── autostart.sh
│   ├── download.sh
│   ├── easytier.sh
│   ├── os.sh
│   ├── output.sh
│   └── platform.sh
└── README.md
```

## 设计原则

- 只有一套 CLI：所有启动、停止、诊断、检查配置都由根目录 `easytierctl` 统一处理。
- 只有一个 `bin/` 目录：不再使用 `platforms/` 之类的分层目录。
- 所有配置都使用 `.env` 风格：不同平台使用完全一致的变量名。
- 平台差异和系统集成会集中收敛到少数模块：
  - `lib/platform.sh`：平台识别、平台标识、二进制目录约定
  - `lib/os.sh`：hostname、machine-id、路径转换、端口探测等系统差异
  - `lib/autostart.sh`：systemd / launchd / Termux:Boot / Windows Startup
  - `lib/download.sh`：GitHub release 下载、版本安装、升级逻辑
  - `lib/output.sh`：终端彩色输出、状态块渲染、节点信息美化
  - `lib/easytier.sh`：命令分发、配置装载、参数拼装、运行时逻辑

为了避免歧义，这里有一个固定约定：

- 二进制目录永远是项目根目录下的 `bin/`
- 项目级公共环境变量固定放在根目录 `.env`
- `.env.executables` 只负责定义文件名，不负责定义目录

## 你后续要放进去的 4 个文件

如果你不使用内置的 `download` / `upgrade` 命令，而是希望自己管理二进制，可以把下面 4 个文件复制到项目根目录 `bin/` 下：

- `easytier-core`
- `easytier-cli`
- `easytier-web`
- `easytier-web-embed`

如果你放进去的文件名就是上面这些默认值，那可以不修改 `.env.executables`，脚本会直接按默认名字从根目录 `bin/` 中查找。

如果文件名不是默认值，比如加了平台后缀，再去执行初始化并修改 `.env.executables` 即可。

## 使用流程

1. 把 4 个 EasyTier 二进制复制到根目录 `bin/`
2. 如需配置 GitHub token 等公共环境变量，可先执行：
   `./easytierctl init env`
3. 初始化组网配置：
   `./easytierctl init create`
   或
   `./easytierctl init join`
4. 如果二进制文件名不是默认值，再执行：
   `./easytierctl init executables`
5. 修改根目录 `.env`
6. 修改 `.env.executables`
7. 修改 `.env.create` 或 `.env.join`
8. 启动：
   `./easytierctl start create`
   或
   `./easytierctl start join`

大多数运行类命令在 `create` / `join` 只有一项可判定时，都可以省略类型，例如：

```bash
./easytierctl start
./easytierctl status
./easytierctl stop
```

如果你不想手动准备 EasyTier 二进制，也可以直接让脚本下载并安装当前平台对应的官方发布包：

```bash
./easytierctl download
./easytierctl upgrade
./easytierctl upgrade v2.6.4
```

下载/升级逻辑说明：

- 会从 EasyTier 官方 GitHub release 动态查询最新版本或指定版本
- 会通过内置平台标识、`uname`、Termux 环境变量等信息自动匹配当前平台对应的发布包并下载到本地
- 解压后会把 `easytier-core`、`easytier-cli`、`easytier-web`、`easytier-web-embed` 安装到 `bin/`
- 会自动重写根目录 `.env.executables`，让脚本和实际文件名保持一致
- 如果设置了 `GITHUB_TOKEN` 或 `GH_TOKEN`，会自动带上它访问 GitHub API，以缓解匿名访问限流
- 如果本机已经执行过 `gh auth login`，脚本也会自动尝试复用 `gh auth token`

## 命令说明

统一 CLI 形式如下：

```bash
./easytierctl <命令> [类型] [参数]
```

支持的命令：

- `help`：查看帮助
- `platform list`：显示当前脚本内置支持的平台标识
- `platform current`：显示当前系统识别结果
- `platform verify`：检查 `bin/` 中是否存在所需二进制
- `download [version]`：下载并安装当前平台对应的 EasyTier 官方发布包；省略版本时默认最新 release
- `upgrade [version]`：升级当前平台对应的 EasyTier 官方发布包；省略版本时默认最新 release
- `init env`：初始化项目级公共环境变量配置
- `init executables`：初始化可执行文件映射配置
- `init create`：初始化创建组网配置
- `init join`：初始化加入组网配置
- `autostart install [create|join]`：安装开机自启；省略类型时自动判断
- `autostart uninstall [create|join]`：卸载开机自启；省略类型时优先按已安装项判断
- `autostart status [create|join]`：查看开机自启状态；省略类型时优先按已安装项判断
- `check [create|join]`：分层检查组网配置、入口连通性、运行态和核心自检，不实际启动；省略类型时自动判断
- `start [create|join]`：启动组网节点；省略类型时自动判断
- `stop [create|join]`：停止组网节点；省略类型时优先按当前运行实例判断
- `restart [create|join]`：重启组网节点；省略类型时优先按当前运行实例判断
- `status [create|join]`：查看组网节点状态；省略类型时优先按当前运行实例判断
- `diagnose [create|join]`：输出组网节点诊断信息；省略类型时优先按当前运行实例判断
- `logs [create|join]`：查看组网节点日志；省略类型时优先按当前运行实例判断
- `fg [create|join]`：前台运行组网节点；省略类型时自动判断

## 常用参数

- `--force`：允许覆盖已存在的配置文件

## 开机自启

当前仓库已经支持统一的开机自启安装命令：

```bash
./easytierctl autostart install join
./easytierctl autostart status
./easytierctl autostart uninstall join
```

说明：

- macOS：自动生成并安装 `launchd` 的 `LaunchDaemon`
- Linux：自动生成并安装 `systemd` service
- Termux：自动生成并安装 `Termux:Boot` 启动脚本
- Windows：自动生成并安装用户 Startup 启动脚本
- macOS / Linux 安装和卸载时会自动申请 `sudo`，因为需要写入系统服务目录
- macOS / Linux 的服务启动时会调用 `./easytierctl fg <profile>`，这样系统服务管理器可以直接托管 EasyTier 进程
- Termux:Boot 启动脚本会调用 `./easytierctl start <profile>`
- Windows Startup 脚本会调用 Git Bash 中的 `./easytierctl start <profile>`
- 运行日志仍然写入项目内 `logs/` 目录，并保留 10M 上限裁剪逻辑

自动判断规则：

- `autostart install`：优先根据当前唯一存在的 `.env.create` 或 `.env.join` 判断
- `autostart uninstall` / `autostart status`：优先根据当前唯一已安装的开机自启项判断
- 如果 `create` 和 `join` 同时存在、无法唯一判断，脚本会要求你显式指定

## 配置文件说明

### 1. `.env`

项目级公共环境变量文件，会在每次执行 `easytierctl` 时自动加载。

对应模板文件在 `env-templates/.env.example`。

适合放下面这类公共变量：

- `GITHUB_TOKEN`
- `GH_TOKEN`

例如：

```env
GITHUB_TOKEN=github_pat_xxxxxxxxxxxxx
```

### 2. `.env.executables`

初始化后生成在仓库根目录，用于声明 `bin/` 目录里实际使用的文件名。

对应模板文件在 `env-templates/.env.executables.example`。

为了避免“调用目录”和“定义目录”分散在不同文件里的歧义，这个文件不再定义二进制目录；二进制目录固定就是项目根目录的 `bin/`。

例如：

```env
EASYTIER_CORE_FILENAME=easytier-core-macos
EASYTIER_CLI_FILENAME=easytier-cli-macos
EASYTIER_WEB_FILENAME=easytier-web-macos
EASYTIER_WEB_EMBED_FILENAME=easytier-web-embed-macos
```

### 3. `.env.create`

用于入口节点、服务端、创建组网的场景。
对应模板文件在 `env-templates/.env.create.example`。

### 4. `.env.join`

用于客户端、接入节点、加入现有组网的场景。
对应模板文件在 `env-templates/.env.join.example`。

## 运行时目录

- `bin/`：手动放入二进制
- 根目录 `.env`：项目级公共环境变量
- 根目录 `.env.*` 文件：真实运行配置
- `.state/`：自动生成的状态目录
- `logs/`：自动生成的日志目录
- `.downloads/`：自动下载或升级 EasyTier 时使用的缓存和解压工作目录

## 控制台输出与日志

- 默认启用彩色终端输出，便于区分信息、成功、提示、错误和不同状态区块
- 如果你不希望使用颜色，可以临时执行 `NO_COLOR=1 ./easytierctl status`
- `status` / `diagnose` 会将节点、对端、路由信息渲染成更易读的摘要格式
- 运行日志默认写入 `logs/<profile>/runtime.log`
- 日志文件单个最大保留 `10M`，超过后会裁剪旧内容，保持最近日志可用

## 当前内置识别的平台

- `linux-aarch64`
- `linux-x86_64`
- `macos-aarch64`
- `windows-x86_64`
- `windows-aarch64`
- `termux-aarch64`
- `termux-x86_64`

## Termux 支持说明

当前项目已经支持在 Termux 中运行，建议按下面方式使用：

- 将 Termux 对应架构的 EasyTier 可执行文件复制到 `bin/`
- 执行 `./easytierctl platform current` 确认识别为 `termux-aarch64` 或 `termux-x86_64`
- `download` / `upgrade` 会优先匹配 Android / Termux 风格发布包，如果官方 release 没有对应资源，会回退尝试 Linux 同架构发布包
- 普通 Termux 环境通常建议在 `.env.join` 或 `.env.create` 中设置 `NO_TUN=true`
- 如果需要创建 TUN，通常要求设备已 root，并在 root shell 中运行
- 如果需要开机自启，可使用 `./easytierctl autostart install join`，并确保已经安装 `Termux:Boot`

## Windows 支持说明

当前项目已经支持在 Windows 的 Git Bash / MSYS 环境中运行，建议按下面方式使用：

- 将 Windows 对应架构的 EasyTier 可执行文件复制到 `bin/`
- 如果文件名带 `.exe`，请在 `.env.executables` 中显式写成 `.exe`
- 执行 `./easytierctl platform current` 确认识别为 `windows-x86_64` 或 `windows-aarch64`
- Windows 下默认不走 Linux/macOS 的 `sudo` / TUN 提权逻辑
- 如果使用 `download` / `upgrade`，脚本会自动把 `.env.executables` 同步成带 `.exe` 的官方文件名
- 如果需要开机自启，可使用 `./easytierctl autostart install join`

如果后续还要支持别的平台，通常只需要：

1. 把该平台可执行文件复制到 `bin/`
2. 修改 `.env.executables`
3. 如有必要，再扩展 `lib/platform.sh` 的识别逻辑
