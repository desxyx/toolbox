# read — Handoff

## 是什么

把一个目录扫成单个 Markdown 文件，给 AI 看完整代码库用。
格式对标 `read.py`（H.E.L.M council 工作流）。

## Windows 状态 ✅ 完成

`win/read_gui.exe` — 静态编译，无任何 DLL 依赖，双击即用。

**功能：**
- GUI：选 Scan 目录 + Output 文件，点 Run
- 选完目录自动填 Output 为同级 `<目录名>.md`
- ASCII 树（`├──` / `└──`）
- Top 15 大文件统计
- 所有文本/代码文件完整 dump，`===== BEGIN/END FILE =====` 标记
- 跳过：`.git` / `node_modules` / 图片 / 二进制 / 字体等

**重新编译（需要 MSYS2 MinGW64）：**
```bat
win\build.bat
```
> ⚠️ 系统 `C:\Windows\System32\zlib1.dll` 版本太旧会导致 cc1plus.exe 崩溃。
> 已通过把 MSYS2 的 `zlib1.dll` 复制到 cc1plus / as 同级目录解决，build.bat 里 PATH 已修复。

---

## Mac 任务 — 待完成

`mac/main.cpp` — POSIX CLI，逻辑和 Windows 版完全一致。

**编译：**
```bash
cd mac
chmod +x build.sh
./build.sh
```
需要系统自带 `c++`（Xcode Command Line Tools）即可，无其他依赖。

**用法：**
```bash
./read <folder> [output.md]
```
- 不指定 output 时，写入 `<folder同级>/<目录名>.md`（和 Windows GUI 行为一致）
- 5 MB 以上的单文件跳过 dump

**测试一下：**
```bash
./read ~/Desktop/some-repo
```

---

## 扫描规则（Windows / Mac 保持同步）

| 类型 | 内容 |
|---|---|
| **跳过目录** | `.git` `.vscode` `node_modules` `dist` `build` `target` `bin` `obj` `.venv` `venv` `.cache` `.next` `.gradle` 等 |
| **跳过文件** | `.png` `.jpg` `.gif` `.pdf` `.mp4` `.dll` `.exe` `.zip` `.db` `.ttf` 等二进制 |
| **Dump 文本** | `.md` `.py` `.js` `.ts` `.tsx` `.jsx` `.vue` `.svelte` `.html` `.css` `.json` `.yml` `.yaml` `.toml` `.go` `.rs` `.java` `.cs` `.php` `.rb` `.cpp` `.c` `.h` `.sh` `.ps1` `.lua` `.swift` `.dart` `.svg` `.env` `.lock` `.tf` `.proto` 等 |

> `.sql` 不在 dump 列表（可能超大）。
