# Wallpaper Engine × Sunshine 联动

Sunshine 串流开始时播放 Wallpaper Engine 动态壁纸，结束时暂停。当前方案不要求 WE 常驻：
WE 开着就联动，关着就安静跳过，不影响串流启动。

## 当前方案：条件执行的 global_prep_cmd

`examples/global-prep-cmd.conf` 是从当前生效配置中仅提取的一行；不是完整 sunshine.conf，
不含账号、配对信息、证书或其他个人配置。

```ini
global_prep_cmd = [{"do":"C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:/Tools/wallpaper-sunshine/we-prep.ps1 play","undo":"C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:/Tools/wallpaper-sunshine/we-prep.ps1 pause","elevated":false}]
```

`scripts/we-prep.ps1` 的行为：

- WE 没在运行（`wallpaper64` / `wallpaper32` 都不在）→ 写一行 skip 日志后立刻 `exit 0`，
  不会启动 WE，串流照常。
- WE 在运行 → 发 `-control play` / `-control pause`，正常返回 `exit 0`。
- 指令超过 5 秒不返回（WE 半死）→ 杀掉这次调用的子进程，`exit 0`，串流不会被拖住。

为什么不再直接调 `wallpaper64.exe -control play`：

- WE 未运行时，这条命令会把整个 WE 启动起来并常驻（wallpaper64 + 多个 wallpaperui），
  不会自己退出。
- Sunshine 执行 prep cmd 是同步无超时等待（`src/process.cpp` 的 `child.wait()`），
  启动请求要等它返回才回 200（`src/nvhttp.cpp` 的 `proc.execute` 调用处），
  结果就是串流卡在启动，客户端一直等到超时。
- 所以「WE 关着」这件事必须由脚本自己先判断掉，不能让 Sunshine 执行到 WE 本体。

新命令里 `powershell.exe` 用完整路径（无空格），脚本也放在无空格目录下（示例用 `C:/Tools/wallpaper-sunshine`）。
换机器时改两处：配置里的脚本路径，以及脚本的 `-Exe`（如果 WE 不在 `C:\wl`）。日志默认写在脚本旁边的 `logs\` 里。

部署步骤：

1. 复制 `scripts/we-prep.ps1` 到目标机（当前为 `C:/Tools/wallpaper-sunshine/we-prep.ps1`）。
2. 备份 sunshine.conf，把 `global_prep_cmd` 合并进去，**不要覆盖其他已有命令**。
3. `C:/wl` 是指向 WE 安装目录的目录联接，当前目标为
   `D:/Program Files/steam/steamapps/common/wallpaper_engine`：

```cmd
mklink /J C:\wl "D:\Program Files\steam\steamapps\common\wallpaper_engine"
```

若 `C:\wl` 已存在，先检查它指向哪里，不要覆盖或删除。脚本默认 `-Exe C:\wl\wallpaper64.exe`。

4. 重启 SunshineService 生效，**会中断当前串流**。
   `scripts/restart-sunshine.cmd` 是手动重启工具；`scripts/sunshine-restart-probe.ps1`
   会真实重启服务并检查端口，不是只读诊断。

### 关键约束

- `elevated` 必须是 JSON 布尔 `false`，不能写字符串 `"false"`。
- 命令里用正斜杠；避免带空格的路径（Sunshine 的 prep cmd 分词不接受裸空格路径）。
- 不要把 `start` 之类的包装塞进命令；需要条件逻辑就交给脚本，脚本本身必须快速返回。
- 无头环境没有活动显示器时，不要只凭 GPU 占用判断 pause/play 成败；以日志和真实串流画面为准。

## 备选方案（已停用）：日志监听

`fallback/we-stream-watch.ps1` 每秒读取 Sunshine 日志末尾 300 行，开始时 play，
结束后等 12 秒再 pause；VBS 是隐藏启动器。保留原样，仅供回退参考。
路径是本机路径，迁移前需修改。**不要与当前 prep-cmd 方案同时启用。**

## 文件与验证边界

- `scripts/we-prep.ps1`：当前生效的条件执行脚本。
- `scripts/`：另有手动重启及重启后检查工具。
- `fallback/`：停用的日志监听脚本及启动器。
- `examples/`：仅当前的 global_prep_cmd 片段。
- `DESIGN.md`：实施记录，含历史实测、2026-11-10 的改造原因与验证结果。

## 卸载联动

从 Sunshine 的 `global_prep_cmd` 中只移除这组 play/pause 命令（保留其他命令），
再择空闲时重启服务。若曾启用 fallback，另移除对应自启入口并停止该脚本。
不需要卸载 Sunshine 或 Wallpaper Engine。
