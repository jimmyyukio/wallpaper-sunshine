---
title: Sunshine 串流联动壁纸（prep-cmd 正确写法）
date: 2026-11-07
tags: [Sunshine, WallpaperEngine, 串流, prep-cmd, Windows]
---

# Sunshine 串流联动壁纸（Windows 实战）

目标：串流开始 → 壁纸播放；串流结束 → 壁纸暂停。无头 Windows 主机已于 2026-11-07 跑通。

## 最终生效配置

`D:\Program Files\Sunshine\config\sunshine.conf` 第 10 行：

```
global_prep_cmd = [{"do":"C:/wl/wallpaper64.exe -control play","undo":"C:/wl/wallpaper64.exe -control pause","elevated":false}]
```

配套：`C:\wl` 是 junction，指向 `D:\Program Files\steam\steamapps\common\wallpaper_engine`，目的是让命令里没有空格。

```
mklink /J C:\wl "D:\Program Files\steam\steamapps\common\wallpaper_engine"
```

**`C:\wl` 别删** —— 配置依赖它。

## 三个坑（都会让方案看起来"根本不可行"）

| 坑 | 现象 | 正解 |
|---|---|---|
| `elevated` 写成字符串 `"false"` | Sunshine **启动即崩**，`0xc0000409`（ucrtbase fail-fast），服务反复重启、端口不监听，Moonlight 连不上 | 必须 JSON 布尔 `false`。源码 `src/config.cpp:1483` 为 `prep_cmd.get_optional<bool>("elevated")` |
| 路径用反斜杠 `C:\\Users\\...` | 同上崩溃：conf 层先解一层转义，JSON 层再解一层，`\U` 变非法转义 | 用正斜杠，并用 junction 消除空格 |
| 命令套 `.cmd` + `start` | 配置正常、服务正常，但壁纸毫无反应（命令执行 exit 0 却无效） | 直接调用 exe，不要包装 |

**曾经误判**：一度认为是"服务在 session 0、壁纸在 session 1，跨会话隔离"。实测 `Sunshine.exe` 本身跑在 **session 1**（只有服务壳 `sunshinesvc.exe` 在 session 0），该结论已作废。

## 验证方法

```powershell
# 1) 看 Sunshine 是否执行了命令
Select-String -Path "D:\Program Files\Sunshine\config\sunshine.log" -Pattern "Executing (Do|Undo) Cmd"
```

实测时间线：

```
00:45:01.857  Executing Do Cmd:   [C:/wl/wallpaper64.exe -control play]
00:45:02.096  New streaming session started
00:46:26.711  CLIENT DISCONNECTED
00:46:26.872  Executing Undo Cmd: [C:/wl/wallpaper64.exe -control pause]
```

→ 命令比会话建立**早 0.24 秒**，第一帧就是壁纸；断开后立即暂停。

```powershell
# 2) 看壁纸进程的 GPU 占用（按 PID 过滤 GPU Engine 计数器）
$p = @(Get-Process wallpaper64); $ids = $p | % { [string]$_.Id }
$rows = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine
$sum = 0.0
foreach ($r in $rows) { foreach ($i in $ids) { if ($r.Name -like "*pid_$i*") { $sum += [double]$r.UtilizationPercentage } } }
$sum
```

正常基线：暂停 ≈ 0%，播放 ≈ 24–36%（780M 核显）。

## 注意

- `wallpaper64.exe -control pause/play` **只在有活动显示器时可验证**。无头主机，没串流时 WE 本来就不渲染，看起来像"命令没生效"，别据此判断失败。
- 改配置后必须重启 `SunshineService` 才生效；重启会断开当前串流。
- 重启验证脚本：`C:\Tools\wallpaper-sunshine\sunshine-restart-probe.ps1`（自动检查服务状态、端口 47984/47989、2 分钟内是否有 1000 事件）。

## 回滚

```
备份：sunshine.conf.bak-prepcmd-20261107-004249
操作：复制回 sunshine.conf → 运行 scripts\restart-sunshine.cmd（提权）
```

## 备选方案：日志监听（B 方案，已停用但保留）

不改配置、不需管理员：用户会话常驻脚本每秒读 `sunshine.log` 末尾，出现 `New streaming session started` 调 play，出现 `CLIENT DISCONNECTED` 等 12 秒调 pause。

| 维度 | A（prep-cmd，当前采用） | B（日志监听） |
|---|---|---|
| 延迟 | 会话开始前 0.2 秒 | 开始后约 1 秒 |
| 断开反应 | 立即 | 12 秒防抖后 |
| 常驻进程 | 无 | 有（约 50–60 MB） |
| 改参数 | 要重启服务 | 随时改 |
| 依赖 | Sunshine 配置格式 | 日志措辞 |

脚本：`scripts\we-stream-watch.ps1`（已停用，自启键已删）。需要时重新挂 `HKCU\...\Run` 即可。

## 2026-11-10 改造：WE 关着时不再卡住串流

### 触发的现象

用户打算日常关掉 Wallpaper Engine。原配置 `C:/wl/wallpaper64.exe -control play` 在 WE 未运行时
不是发空指令，而是**把整个 WE 启动起来并常驻**（实测 wallpaper64 + 6～7 个 wallpaperui，
20 秒不退出，`Get-Process` 能查到全部进程）。Sunshine 执行 global_prep_cmd 是同步无超时等待：

```
src/process.cpp  execute() -> for (prep_cmds) -> wait_for_prep_command() -> child.wait(ec)
src/nvhttp.cpp   1451: auto err = proc::proc.execute((int) appid, launch_session);
```

所以串流启动请求会一直挂着，Moonlight 端转圈到超时。这个坑在我实测之前没被触发，
因为 11-07 验证时 WE 本来就在跑（`-control` 打给已有实例，0.2 秒返回）。

### 改法

新增 `scripts/we-prep.ps1`，行为：

| 状态 | 动作 | 返回 |
|---|---|---|
| `wallpaper64` / `wallpaper32` 都不在 | 写 skip 日志，不启动 WE | `exit 0` |
| WE 在运行 | 发 `-control play` / `-control pause` | `exit 0` |
| 指令 5 秒不返回 | 杀掉本次调用的子进程 | `exit 0` |

Sunshine 配置改成调用脚本（play / pause 分别作为 do / undo），`elevated` 仍为 JSON 布尔 false。

### 实测（2026-11-10，测试机）

- WE 未运行：脚本 0.45 秒返回 0，没有出现任何 WE 进程，日志 `skip (play): wallpaper engine not running`。
- WE 运行：脚本 0.45 秒返回 0，日志 `sent (pause): we_pid=... exit=0`，play/pause 各一次都正常。
- GPU 读数在无头无串流时为 0，不能作为验证依据（沿用 11-07 的结论）。

### 真实串流验证（2026-11-10 16:28～16:32，测试机）

重启 SunshineService 后客户端重连了两次，日志对上：

```
16:28:20.828  Executing Do Cmd:  [...we-prep.ps1 play]      ← WE 在运行
16:28:21      we-prep.log: sent (play): we_pid=23240 exit=0
16:28:22.082  New streaming session started                 ← 1.25 秒后建立

16:31:51.530  Executing Undo Cmd: [...we-prep.ps1 pause]    ← WE 已关闭
16:31:52      we-prep.log: skip (pause): wallpaper engine not running
16:32:00.290  Executing Do Cmd: [...we-prep.ps1 play]
16:32:01      we-prep.log: skip (play): wallpaper engine not running
16:32:01.201  New streaming session started                 ← 0.91 秒后建立
16:32:11.519  Executing Undo Cmd: [...we-prep.ps1 pause] → skip
```

结论：WE 开着走 sent、关着走 skip，两种状态都不阻塞 launch，也没有 `Failed to start`。
代价是首帧比旧的直接调用多 0.6～1 秒（PowerShell 启动开销）。


