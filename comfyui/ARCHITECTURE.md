# ComfyUI Forge 内部架构文档

> 本文档不是使用教程，而是 ComfyUI Forge 的内部系统蓝图。
>
> 目标：记录模块职责、执行顺序、强绑定关系、可替换边界和未来维护规则，避免所有系统关系只存在于脑子里。

---

## 1. 当前系统定位

ComfyUI Forge 不是单个脚本，也不是普通的 ComfyUI 启动器。

它现在的定位是：

```text
一次性恢复环境 + 恢复 ComfyUI Core + 拉取资产状态 + 修复依赖 + 启动服务 + 暴露固定访问入口
```

也就是说，它已经是一个小型的 AI 创作环境恢复/编排系统。

核心目标不是“启动 ComfyUI”，而是：

```text
在一台新的 GPU Pod 上，尽可能自动恢复到可用状态。
```

---

## 2. 总启动链路

当前主入口是：

```bash
bash comfyui/forge_start.sh
```

总链路如下：

```text
forge_start.sh
  ↓
prepare_private_configs
  ↓
detect_torch_profile.sh
  ↓
bootstrap-cu121.sh / bootstrap-cu128.sh
  ↓
activate_project_env
  ↓
restore_comfyui_core.sh
  ↓
r2-sync/check_r2.sh
  ↓
r2-sync/pull_from_r2.sh
  ↓
deps/check_deps.sh
  ↓
deps/auto_deps.py
  ↓
start_all.sh start
  ↓
ComfyUI + Cloudflare Tunnel online
```

### 2.1 一句话理解

```text
forge_start.sh 负责“编排所有阶段”，但不应该自己承担具体业务逻辑。
```

它是调度层，不是环境层、数据层、依赖层或网络层。

---

## 3. 模块分层

### 3.1 Orchestration Layer：编排层

核心文件：

```text
comfyui/forge_start.sh
```

职责：

- 加载 `/root/.env`
- 整理私密配置文件
- 准备 `rclone.conf`
- 准备 Cloudflare Tunnel credential json
- 自动判断 `TORCH_PROFILE`
- 选择对应 bootstrap 脚本
- 串联所有恢复阶段
- 任一关键步骤失败时中止

不应该做的事：

- 不直接安装 Torch
- 不直接 clone ComfyUI
- 不直接写 tunnel config
- 不直接安装 custom_nodes 依赖
- 不直接维护 R2 同步规则

### 3.2 Environment Layer：基础环境层

核心文件：

```text
comfyui/detect_torch_profile.sh
comfyui/bootstrap-cu121.sh
comfyui/bootstrap-cu128.sh
```

职责：

- 检查 Linux / x86_64 / nvidia-smi / CUDA driver
- 安装 apt 基础工具
- 安装 cloudflared
- 安装或复用 Miniconda
- 创建或复用 conda env
- 安装 Python / Torch / torchvision / torchaudio / xformers / tomli
- 生成 `/root/bootstrap_env_info.txt`
- 做基础 healthcheck

边界：

```text
环境层只负责“让系统具备运行能力”。
```

它不负责：

- ComfyUI 源码
- R2 资产
- custom_nodes 依赖扫描
- 服务启动
- tunnel 启动

### 3.3 ComfyUI Core Layer：核心源码层

核心文件：

```text
comfyui/restore_comfyui_core.sh
```

职责：

- 确保 `/root/ComfyUI` 是一个 git repo
- clone 或复用 ComfyUI core
- checkout 指定版本
- 写入 core 信息文件

关键原则：

```text
ComfyUI core 是可重建层，不应该从 R2 当作资产整体同步。
```

这点非常重要。

R2 应该保存模型、插件、用户状态、输入输出等资产/状态层；ComfyUI core 应该通过 git 恢复。

### 3.4 Data Layer：R2 数据层

核心目录：

```text
comfyui/r2-sync/
```

核心文件：

```text
check_r2.sh
pull_from_r2.sh
push_incremental.sh
```

职责：

- 检查 rclone 配置
- 从 Cloudflare R2 拉取 ComfyUI 资产/状态层
- 将本地资产/状态层增量推送回 R2

当前同步目录白名单：

```text
models
custom_nodes
deps
user
input
output2
lora1
alembic_db
```

当前同步文件白名单：

```text
openapi.yaml
comfy_stable_lock.txt
comfy_env_lock.txt
comfyui_stable_info.txt
```

重要规则：

```text
pull_from_r2.sh 使用 rclone copy。
push_incremental.sh 对多数目录使用 rclone copy。
push_incremental.sh 对 custom_nodes 使用 rclone sync。
```

含义：

- 大多数资产目录采用追加式同步，降低误删风险。
- `custom_nodes` 是严格同步目录，本地删除插件后，远端也应该跟着删除，避免旧插件复活。

### 3.5 Dependency Layer：依赖层

核心目录：

```text
comfyui/deps/
```

核心入口：

```text
deps/auto_deps.py
```

内部子层：

```text
scanner/    扫描层
rules/      规则层
installer/  安装层
state/      状态层
```

职责：

- 扫描 `custom_nodes/**/requirements*.txt`
- 标准化依赖行
- 去重
- 跳过不应该自动安装的包
- 区分普通 pip 包和 git 包
- 合并手动补丁依赖
- 合并兼容性依赖
- 安装 ComfyUI core requirements
- 安装 custom_nodes 依赖
- 从 ComfyUI 日志中解析 `ModuleNotFoundError`，写入 `manual_requirements.txt`

关键文件：

```text
custom_nodes.clean.txt      自动扫描后的可安装依赖
custom_nodes.skipped.txt    自动扫描后被跳过的依赖
manual_requirements.txt     人工/修复补丁层
compat_requirements.txt     兼容性补丁层
```

核心运行模式：

```bash
python deps/auto_deps.py
python deps/auto_deps.py --rescan
python deps/auto_deps.py --scan-only
python deps/auto_deps.py --repair-log /root/ComfyUI/user/comfyui.log
python deps/auto_deps.py --repair-log /root/ComfyUI/user/comfyui.log --repair-install
```

设计原则：

```text
scanner 只负责发现。
rules 只负责判断和转换。
installer 只负责安装。
manual_requirements 是补丁层，不是扫描层。
```

### 3.6 Service Layer：运行态服务层

核心文件：

```text
comfyui/start_all.sh
```

职责：

- 启动 ComfyUI
- 停止 ComfyUI
- 重启 ComfyUI
- 查看状态
- 启动 Cloudflare Tunnel
- 检查端口和进程
- 清理错误的 `python -m http.server`

命令：

```bash
bash start_all.sh start
bash start_all.sh stop
bash start_all.sh restart
bash start_all.sh status
```

注意：

```text
stop / restart 当前主要控制 ComfyUI。
Cloudflare Tunnel 由 tunnel/start_tunnel.sh 内部负责先清理旧 cloudflared 再启动。
```

### 3.7 Network Layer：网络入口层

核心目录：

```text
comfyui/tunnel/
```

核心文件：

```text
config.template.yml
render_tunnel_config.sh
start_tunnel.sh
stop_tunnel.sh
check_tunnel.sh
```

职责：

- 从环境变量生成 Cloudflare Tunnel config
- 安装 tunnel credential
- 启动 cloudflared
- 停止旧 cloudflared 进程
- 检查 tunnel 状态

关键环境变量：

```text
CF_TUNNEL_UUID
CF_HOSTNAME
CF_LOCAL_PORT
CF_TUNNEL_NAME
```

默认访问入口：

```text
https://comfy.jhinforge.xyz
```

---

## 4. 强绑定关系

强绑定指：改一个就必须同时检查另一个，否则系统容易炸。

### 4.1 TORCH_PROFILE ↔ bootstrap 脚本

```text
TORCH_PROFILE=cu121  ↔  bootstrap-cu121.sh
TORCH_PROFILE=cu128  ↔  bootstrap-cu128.sh
```

`detect_torch_profile.sh` 会根据 GPU 名称和 CUDA driver 判断使用哪个 profile。

当前逻辑：

- RTX 50 系列倾向 `cu128`
- CUDA driver >= 12.8 倾向 `cu128`
- 其它默认 `cu121`

### 4.2 CUDA / Torch / xformers 强绑定

`cu121` profile 当前是稳定锁定型：

```text
Python 3.10
Torch 2.5.1+cu121
torchvision 0.20.1+cu121
torchaudio 2.5.1+cu121
xformers 0.0.27.post2
```

`cu128` profile 当前是适配探索型：

```text
Python 3.10
Torch cu128 wheels
默认不安装 xformers
ComfyUI 使用 pytorch attention 作为 safer baseline
```

维护规则：

```text
不要把 cu121 的 xformers 策略直接套到 cu128。
不要把 cu128 的“跟随当前兼容 wheel”策略直接套到 cu121。
```

### 4.3 rclone.conf ↔ R2 同步脚本

强绑定文件路径：

```text
/root/rclone.conf
/root/.config/rclone/rclone.conf
```

相关脚本：

```text
forge_start.sh
r2-sync/check_r2.sh
r2-sync/pull_from_r2.sh
r2-sync/push_incremental.sh
```

规则：

```text
/root/rclone.conf 是上传/私密配置入口。
/root/.config/rclone/rclone.conf 是 rclone 默认运行路径。
```

如果 `/root/.config/rclone/rclone.conf` 被误创建成目录，脚本应该直接报错中止。

### 4.4 Cloudflare Tunnel credential ↔ CF_TUNNEL_UUID

强绑定关系：

```text
CF_TUNNEL_UUID
  ↔ /root/<CF_TUNNEL_UUID>.json
  ↔ /root/.cloudflared/<CF_TUNNEL_UUID>.json
  ↔ /root/.cloudflared/config.yml
```

如果 UUID 改了，credential json 也必须对应变化。

### 4.5 CF_HOSTNAME ↔ Cloudflare Access / DNS / Tunnel ingress

强绑定关系：

```text
CF_HOSTNAME
  ↔ Cloudflare DNS
  ↔ Cloudflare Tunnel ingress
  ↔ Cloudflare Access application
```

例如：

```text
comfy.jhinforge.xyz
```

不是单纯改 `.env` 就一定能访问，Cloudflare 侧也必须一致。

### 4.6 COMFYUI_ROOT ↔ R2_REMOTE 内容结构

默认：

```text
COMFYUI_ROOT=/root/ComfyUI
R2_REMOTE=r2-assets:comfyui-assets/ComfyUI
```

R2 远端目录结构应与本地 `/root/ComfyUI` 的资产/状态白名单结构对应。

### 4.7 custom_nodes ↔ auto_deps.py

强绑定关系：

```text
/root/ComfyUI/custom_nodes
  ↔ deps/auto_deps.py
  ↔ custom_nodes.clean.txt
  ↔ custom_nodes.skipped.txt
  ↔ manual_requirements.txt
```

插件变化后，依赖层可能需要：

```bash
python deps/auto_deps.py --rescan
```

如果启动后出现缺模块，再进入 repair 流：

```bash
python deps/auto_deps.py --repair-log /root/ComfyUI/user/comfyui.log --repair-install
```

---

## 5. 可替换边界

### 5.1 可替换：GPU Pod 平台

理论上可以替换：

```text
Vast / RunPod / TensorDock / 其它 GPU Pod
```

前提：

- Linux x86_64
- NVIDIA GPU
- `nvidia-smi` 可用
- CUDA driver 满足对应 profile
- 能访问 GitHub / PyPI / PyTorch wheel / Cloudflare / R2

### 5.2 可替换：ComfyUI core 版本

变量：

```text
COMFYUI_VERSION
```

但改版本后必须检查：

- ComfyUI requirements
- custom_nodes 兼容性
- Manager 数据库/迁移状态
- workflow 是否仍兼容

### 5.3 可替换：R2 remote 名称和路径

变量：

```text
R2_REMOTE
```

可以替换，但必须保持本地与远端结构一致。

### 5.4 可替换：访问域名

变量：

```text
CF_HOSTNAME
```

可以替换，但必须同时改：

- Cloudflare DNS
- Cloudflare Tunnel ingress
- Cloudflare Access application
- `.env`

---

## 6. 不建议随便替换的部分

### 6.1 conda env 命名

变量：

```text
ENV_NAME
```

可以改，但不建议频繁改。

原因：

- `.bashrc` 自动激活会写入 env 名称
- `forge_start.sh`、`start_all.sh` 都依赖它
- 多个 profile 下 env 名称承担隔离作用

### 6.2 Python 主版本

当前主线按 Python 3.10 处理。

不建议直接切 Python 3.11/3.12，因为：

- ComfyUI/custom_nodes 兼容性不一定一致
- 某些依赖 wheel 可能不同
- `tomli` / `tomllib` 行为边界不同

### 6.3 custom_nodes 同步策略

`custom_nodes` 当前是严格同步目录。

不建议随便改成追加式 copy。

原因：

```text
如果 custom_nodes 只 copy，不 sync，被删除的旧插件可能从 R2 复活，导致隐藏冲突。
```

---

## 7. 生命周期分类

### 7.1 一次性恢复阶段

通常在新 Pod 上跑一次：

```text
prepare_private_configs
bootstrap-cu121.sh / bootstrap-cu128.sh
restore_comfyui_core.sh
r2-sync/pull_from_r2.sh
deps/auto_deps.py
```

### 7.2 长期运行阶段

持续存在：

```text
ComfyUI main.py
cloudflared tunnel
```

### 7.3 按需维护阶段

需要时手动运行：

```text
r2-sync/push_incremental.sh
deps/auto_deps.py --rescan
deps/auto_deps.py --repair-log ... --repair-install
start_all.sh restart
start_all.sh status
```

---

## 8. 日志地图

常见日志：

```text
/root/everspark_logs/recovery.log
/root/everspark_logs/start_all.log
/root/everspark_logs/comfyui.log
/root/everspark_logs/tunnel.log
/root/everspark_logs/cloudflared.log
/root/everspark_logs/r2.log
/root/everspark_logs/rclone.log
/root/everspark_logs/auto_deps.log
/root/everspark_logs/bootstrap.log
```

排查顺序建议：

```text
recovery.log
  ↓
bootstrap.log
  ↓
r2.log
  ↓
auto_deps.log
  ↓
comfyui.log
  ↓
cloudflared.log
  ↓
start_all.log
```

---

## 9. 故障定位原则

### 9.1 新 Pod 恢复失败

先看：

```text
/root/everspark_logs/recovery.log
```

因为它记录每个阶段是否通过。

### 9.2 环境失败

看：

```text
/root/everspark_logs/bootstrap.log
/root/bootstrap_env_info.txt
```

重点检查：

- CUDA driver
- TORCH_PROFILE
- Python version
- Torch version
- xformers version
- `torch.cuda.is_available()`

### 9.3 R2 拉取失败

看：

```text
/root/everspark_logs/r2.log
/root/everspark_logs/rclone.log
```

重点检查：

- rclone config 是否存在
- R2_REMOTE 是否正确
- bucket/path 是否正确
- `/root/.config/rclone/rclone.conf` 是否被误建成目录

### 9.4 依赖失败

看：

```text
/root/everspark_logs/auto_deps.log
/root/ComfyUI/user/comfyui.log
```

处理路径：

```bash
python deps/auto_deps.py --repair-log /root/ComfyUI/user/comfyui.log --repair-install
```

### 9.5 ComfyUI 本地正常，但域名打不开

先区分：

```text
本地服务问题？还是 tunnel / Cloudflare 问题？
```

检查：

```bash
curl -I http://127.0.0.1:8188
```

如果本地正常，再看：

```text
/root/everspark_logs/cloudflared.log
```

重点检查：

- cloudflared 是否注册连接
- credential json 是否匹配
- CF_HOSTNAME 是否正确
- Cloudflare Access 是否配置正确

---

## 10. 未来扩展规则

### 10.1 新增 profile

例如未来新增：

```text
cu129
rocm
cpu
```

必须新增或修改：

```text
detect_torch_profile.sh
bootstrap-<profile>.sh
forge_start.sh profile 分发逻辑
ARCHITECTURE.md
```

不能只加 bootstrap 脚本，不接入调度层。

### 10.2 新增 R2 同步目录

必须同时考虑：

```text
pull_from_r2.sh
push_incremental.sh
是否 additive copy
是否 strict sync
是否应该排除日志/缓存/临时文件
```

### 10.3 新增依赖规则

优先顺序：

```text
rules/ 里加通用规则
manual_requirements.txt 加个别补丁
compat_requirements.txt 加兼容性补丁
```

不要把所有异常都塞进主安装逻辑。

### 10.4 新增服务

如果未来接入：

```text
Ollama Forge
Video Forge
Audio Forge
API Gateway
```

建议每个 Forge 都保持自己的：

```text
forge_start.sh
bootstrap 层
data sync 层
dependency 层
service 层
network 层
```

EverSpark Forge Core 再负责跨 Forge 编排。

---

## 11. 当前最重要的系统共识

### 11.1 ComfyUI Forge 的核心不是“安装”

而是：

```text
恢复、复现、修复、启动、暴露入口。
```

### 11.2 R2 保存的是资产/状态，不是所有东西

```text
ComfyUI core：git 恢复
models/custom_nodes/user/input/output2/lora1：R2 恢复
Python/Torch/xformers：bootstrap 恢复
custom_nodes 依赖：auto_deps 恢复
访问入口：Cloudflare Tunnel 恢复
```

### 11.3 forge_start.sh 是总入口，但不是万能脚本

它只负责把正确的人安排到正确的位置。

### 11.4 最危险的问题是隐性耦合

尤其是：

```text
CUDA ↔ Torch ↔ xformers
CF_TUNNEL_UUID ↔ credential json ↔ config.yml
R2_REMOTE ↔ COMFYUI_ROOT
custom_nodes ↔ auto_deps.py ↔ manual_requirements.txt
ComfyUI version ↔ custom_nodes ↔ workflows
```

这些关系必须写在文档里，不能只靠记忆。

---

## 12. 维护检查清单

修改任何模块前，先问：

```text
1. 这个模块属于哪一层？
2. 它的上游是谁？
3. 它的下游是谁？
4. 它有没有强绑定对象？
5. 它失败后应该中止，还是允许继续？
6. 它产生的状态文件在哪里？
7. 它的日志在哪里？
8. 它是否影响新 Pod 恢复？
9. 它是否影响 R2 远端状态？
10. 它是否需要同步更新本文档？
```

---

## 13. 当前一句话蓝图

```text
ComfyUI Forge = GPU Pod 环境锻造器 + ComfyUI 状态恢复器 + 依赖自修复器 + 固定安全入口启动器。
```

或者更短：

```text
让 ComfyUI 不绑定某一台机器，而绑定一套可复现的 Forge 流程。
```
