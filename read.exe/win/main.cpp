#define UNICODE
#define _UNICODE
#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <commdlg.h>
#include <shlobj.h>
#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <algorithm>

// Control IDs
#define ID_INPUT_EDIT    101
#define ID_INPUT_BROWSE  102
#define ID_OUTPUT_EDIT   103
#define ID_OUTPUT_BROWSE 104
#define ID_RUN_BTN       105
#define ID_LOG_EDIT      106
#define ID_LABEL_INPUT   107
#define ID_LABEL_OUTPUT  108

HWND hInputEdit, hOutputEdit, hLogEdit, hRunBtn;
HFONT hFont;

// ── helpers ──────────────────────────────────────────────────────────────────

std::wstring BrowseFolder(HWND owner)
{
    IFileDialog* pfd = nullptr;
    std::wstring result;

    if (SUCCEEDED(CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                   CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&pfd))))
    {
        DWORD opts;
        pfd->GetOptions(&opts);
        pfd->SetOptions(opts | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM);
        pfd->SetTitle(L"Select folder to scan");

        if (SUCCEEDED(pfd->Show(owner)))
        {
            IShellItem* psi = nullptr;
            if (SUCCEEDED(pfd->GetResult(&psi)))
            {
                PWSTR path = nullptr;
                if (SUCCEEDED(psi->GetDisplayName(SIGDN_FILESYSPATH, &path)))
                {
                    result = path;
                    CoTaskMemFree(path);
                }
                psi->Release();
            }
        }
        pfd->Release();
    }
    return result;
}

std::wstring BrowseOutputFile(HWND owner, const std::wstring& defaultDir)
{
    wchar_t buf[MAX_PATH] = L"snapshot.md";
    OPENFILENAMEW ofn = {};
    ofn.lStructSize  = sizeof(ofn);
    ofn.hwndOwner    = owner;
    ofn.lpstrFilter  = L"Markdown (*.md)\0*.md\0Text (*.txt)\0*.txt\0All files\0*.*\0";
    ofn.lpstrFile    = buf;
    ofn.nMaxFile     = MAX_PATH;
    ofn.lpstrTitle   = L"Choose output file";
    ofn.Flags        = OFN_OVERWRITEPROMPT | OFN_PATHMUSTEXIST;

    if (!defaultDir.empty())
        ofn.lpstrInitialDir = defaultDir.c_str();

    if (GetSaveFileNameW(&ofn))
        return buf;
    return {};
}

void Log(const std::wstring& msg)
{
    int len = GetWindowTextLengthW(hLogEdit);
    SendMessageW(hLogEdit, EM_SETSEL, len, len);
    SendMessageW(hLogEdit, EM_REPLACESEL, FALSE, (LPARAM)(msg + L"\r\n").c_str());
}

// ── layout ───────────────────────────────────────────────────────────────────

void LayoutControls(HWND hwnd)
{
    RECT rc;
    GetClientRect(hwnd, &rc);
    int W = rc.right, pad = 16;
    int editH = 28, btnW = 90, labelH = 18, rowGap = 10;

    int y = pad;

    // --- Scan folder row ---
    MoveWindow(GetDlgItem(hwnd, ID_LABEL_INPUT), pad, y, W - pad*2, labelH, TRUE);
    y += labelH + 4;
    MoveWindow(hInputEdit,  pad,         y, W - pad*2 - btnW - 8, editH, TRUE);
    MoveWindow(GetDlgItem(hwnd, ID_INPUT_BROWSE),
               W - pad - btnW, y, btnW, editH, TRUE);
    y += editH + rowGap;

    // --- Output file row ---
    MoveWindow(GetDlgItem(hwnd, ID_LABEL_OUTPUT), pad, y, W - pad*2, labelH, TRUE);
    y += labelH + 4;
    MoveWindow(hOutputEdit, pad,         y, W - pad*2 - btnW - 8, editH, TRUE);
    MoveWindow(GetDlgItem(hwnd, ID_OUTPUT_BROWSE),
               W - pad - btnW, y, btnW, editH, TRUE);
    y += editH + rowGap;

    // --- Run button ---
    int runW = 120, runH = 34;
    MoveWindow(hRunBtn, W - pad - runW, y, runW, runH, TRUE);
    y += runH + rowGap;

    // --- Log ---
    MoveWindow(hLogEdit, pad, y, W - pad*2, rc.bottom - y - pad, TRUE);
}

// ── snapshot logic ───────────────────────────────────────────────────────────

// UTF-8 box-drawing chars
#define BRANCH_MID "\xe2\x94\x9c\xe2\x94\x80\xe2\x94\x80 "   // ├──
#define BRANCH_END "\xe2\x94\x94\xe2\x94\x80\xe2\x94\x80 "   // └──
#define PIPE_CONT  "\xe2\x94\x82   "                           // │
#define PIPE_SPACE "    "

#define MAX_DUMP_BYTES (5LL * 1024 * 1024)  // 5 MB

// ---- ignore lists ----
static bool NameInList(const wchar_t* const* list, const std::wstring& name)
{
    for (int i = 0; list[i]; ++i)
        if (_wcsicmp(list[i], name.c_str()) == 0) return true;
    return false;
}

static const wchar_t* s_ignoreDirs[] = {
    L".git", L".idea", L".vscode", L"__pycache__", L".pytest_cache",
    L".mypy_cache", L"node_modules", L"dist", L"build", L"target",
    L"bin", L"obj", L".venv", L"venv", L".cache", L".tox",
    L".gradle", L".svelte-kit", L".next", L"browser-profiles", nullptr
};

static const wchar_t* s_binaryExts[] = {
    L".dll", L".so", L".dylib", L".a", L".lib", L".exe",
    L".zip", L".tar", L".gz", L".7z", L".rar",
    L".png", L".jpg", L".jpeg", L".gif", L".webp", L".ico", L".bmp",
    L".pdf", L".mp4", L".mov", L".mp3", L".wav", L".avi",
    L".db", L".sqlite", L".sqlite3", L".wal", L".ldb",
    L".pak", L".dat", L".bin",
    L".woff", L".woff2", L".ttf", L".otf",
    nullptr
};

static const wchar_t* s_textExts[] = {
    L".txt", L".md", L".py", L".json", L".yml", L".yaml",
    L".ini", L".cfg", L".toml", L".csv", L".xml",
    L".html", L".htm", L".css", L".js", L".ts", L".tsx", L".jsx",
    L".c", L".h", L".cpp", L".hpp", L".cs", L".java",
    L".kt", L".go", L".rs", L".rb", L".php",
    L".sh", L".bash", L".zsh", L".ps1",
    L".r", L".swift", L".pl", L".lua",
    L".dart", L".scala", L".hs", L".inc", L".vue", L".svelte", L".svg",
    L".env", L".lock", L".mod", L".sum", L".tf", L".hcl", L".proto",
    nullptr
};

static const wchar_t* s_textNames[] = {
    L"Dockerfile", L"Makefile", L"README", L"LICENSE", L".gitignore",
    L".npmrc", L".editorconfig", nullptr
};

static std::wstring ExtOf(const std::wstring& name)
{
    size_t dot = name.rfind(L'.');
    if (dot == std::wstring::npos || dot == 0) return L"";
    std::wstring ext = name.substr(dot);
    for (auto& c : ext) c = towlower(c);
    return ext;
}

static bool IsIgnoreDir(const std::wstring& n)  { return NameInList(s_ignoreDirs,  n); }
static bool IsBinaryFile(const std::wstring& n)
{
    std::wstring ext = ExtOf(n);
    return !ext.empty() && NameInList(s_binaryExts, ext);
}
static bool IsTextFile(const std::wstring& name)
{
    std::wstring ext = ExtOf(name);
    if (!ext.empty() && NameInList(s_textExts, ext)) return true;
    return NameInList(s_textNames, name);
}

// ---- helpers ----
static std::string WtoU8(const std::wstring& w)
{
    if (w.empty()) return {};
    int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, nullptr, 0, nullptr, nullptr);
    std::string s(n - 1, '\0');
    WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, &s[0], n, nullptr, nullptr);
    return s;
}

static std::string FormatSize(long long b)
{
    char buf[32];
    if      (b < 1024LL)              snprintf(buf, sizeof(buf), "%.1fB",  (double)b);
    else if (b < 1024LL*1024)        snprintf(buf, sizeof(buf), "%.1fKB", b/1024.0);
    else if (b < 1024LL*1024*1024)   snprintf(buf, sizeof(buf), "%.1fMB", b/(1024.0*1024));
    else                              snprintf(buf, sizeof(buf), "%.1fGB", b/(1024.0*1024*1024));
    return buf;
}

static std::string GetTimestamp()
{
    SYSTEMTIME st; GetLocalTime(&st);
    TIME_ZONE_INFORMATION tzi; GetTimeZoneInformation(&tzi);
    int bias = -(int)tzi.Bias;
    char buf[64];
    snprintf(buf, sizeof(buf), "%04d-%02d-%02dT%02d:%02d:%02d%+03d:%02d",
        st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond,
        bias/60, abs(bias%60));
    return buf;
}

static std::string MtimeStr(const WIN32_FIND_DATAW& fd)
{
    FILETIME local; FileTimeToLocalFileTime(&fd.ftLastWriteTime, &local);
    SYSTEMTIME st;  FileTimeToSystemTime(&local, &st);
    char buf[32];
    snprintf(buf, sizeof(buf), "%04d-%02d-%02d %02d:%02d:%02d",
        st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);
    return buf;
}

// ---- file stats ----
struct FileStat {
    std::wstring relPath;   // relative, backslash-separated
    std::wstring fullPath;
    long long    size  = 0;
    long long    lines = -1;
    std::string  mtime;
};

// ---- list one dir (visible entries, sorted dirs-first alpha) ----
struct RawEntry { std::wstring name; bool isDir; long long size; std::string mtime; };
static std::vector<RawEntry> ListVisible(const std::wstring& dir,
                                         const std::wstring& skipFull)
{
    std::vector<RawEntry> out;
    WIN32_FIND_DATAW fd;
    HANDLE h = FindFirstFileW((dir + L"\\*").c_str(), &fd);
    if (h == INVALID_HANDLE_VALUE) return out;
    do {
        std::wstring name = fd.cFileName;
        if (name == L"." || name == L"..") continue;
        bool isDir = (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
        std::wstring full = dir + L"\\" + name;
        if (!skipFull.empty() && full == skipFull) continue;
        if (isDir  && IsIgnoreDir(name))   continue;
        if (!isDir && IsBinaryFile(name))  continue;
        ULARGE_INTEGER sz; sz.HighPart = fd.nFileSizeHigh; sz.LowPart = fd.nFileSizeLow;
        out.push_back({name, isDir, (long long)sz.QuadPart, isDir ? "" : MtimeStr(fd)});
    } while (FindNextFileW(h, &fd));
    FindClose(h);
    std::sort(out.begin(), out.end(), [](const RawEntry& a, const RawEntry& b){
        if (a.isDir != b.isDir) return (int)a.isDir > (int)b.isDir;
        return _wcsicmp(a.name.c_str(), b.name.c_str()) < 0;
    });
    return out;
}

// ---- recursive tree + stat collector ----
static void WalkTree(const std::wstring& dir, const std::wstring& rel,
                     const std::string& prefix,
                     const std::wstring& skipFull,
                     std::vector<std::string>& treeLines,
                     std::vector<FileStat>&    stats)
{
    auto entries = ListVisible(dir, skipFull);
    for (size_t i = 0; i < entries.size(); ++i) {
        bool last = (i == entries.size() - 1);
        const auto& e = entries[i];
        std::string branch = last ? BRANCH_END : BRANCH_MID;
        std::string label  = WtoU8(e.name) + (e.isDir ? "/" : "");
        treeLines.push_back(prefix + branch + label);

        std::wstring childFull = dir + L"\\" + e.name;
        std::wstring childRel  = rel.empty() ? e.name : rel + L"\\" + e.name;

        if (e.isDir) {
            WalkTree(childFull, childRel,
                     prefix + (last ? PIPE_SPACE : PIPE_CONT),
                     skipFull, treeLines, stats);
        } else {
            FileStat fs;
            fs.relPath  = childRel;
            fs.fullPath = childFull;
            fs.size     = e.size;
            fs.mtime    = e.mtime;
            stats.push_back(std::move(fs));
        }
    }
}

// ---- count newlines ----
static long long CountLines(const std::wstring& path)
{
    HANDLE h = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ,
                           nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return -1;
    char buf[65536]; DWORD rd; long long n = 0; bool sawAny = false; char last = 0;
    while (ReadFile(h, buf, sizeof(buf), &rd, nullptr) && rd) {
        sawAny = true;
        for (DWORD i = 0; i < rd; ++i) if (buf[i] == '\n') ++n;
        last = buf[rd-1];
    }
    CloseHandle(h);
    if (sawAny && last != '\n') ++n;
    return n;
}

// ---- read file as UTF-8 string (strips BOM, converts UTF-16) ----
static std::string ReadAsUtf8(const std::wstring& path, long long size)
{
    if (size <= 0 || size > MAX_DUMP_BYTES) return "";
    HANDLE h = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ,
                           nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return "";
    std::string raw((size_t)size, '\0');
    DWORD rd = 0;
    ReadFile(h, &raw[0], (DWORD)size, &rd, nullptr);
    CloseHandle(h);
    raw.resize(rd);
    if (rd < 2) return raw;

    // UTF-16 LE BOM
    if ((unsigned char)raw[0]==0xFF && (unsigned char)raw[1]==0xFE) {
        int n = WideCharToMultiByte(CP_UTF8, 0, (LPCWCH)raw.data(), (int)rd/2,
                                    nullptr, 0, nullptr, nullptr);
        std::string u8(n, '\0');
        WideCharToMultiByte(CP_UTF8, 0, (LPCWCH)raw.data(), (int)rd/2,
                            &u8[0], n, nullptr, nullptr);
        return u8;
    }
    // UTF-8 BOM
    if (rd>=3 && (unsigned char)raw[0]==0xEF &&
                 (unsigned char)raw[1]==0xBB &&
                 (unsigned char)raw[2]==0xBF)
        return raw.substr(3);
    // Null bytes → binary
    if (raw.find('\0') != std::string::npos) return "";
    return raw;
}

// ── main snapshot entry ──────────────────────────────────────────────────────
static bool RunSnapshot(const std::wstring& rootDir, const std::wstring& outPath,
                        HWND /*logWnd*/)
{
    // Normalise paths
    wchar_t normRoot[MAX_PATH], normOut[MAX_PATH];
    GetFullPathNameW(rootDir.c_str(), MAX_PATH, normRoot, nullptr);
    GetFullPathNameW(outPath.c_str(),  MAX_PATH, normOut,  nullptr);

    // Root display name
    std::wstring rootName;
    { size_t s = std::wstring(normRoot).rfind(L'\\');
      rootName = (s==std::wstring::npos) ? normRoot : std::wstring(normRoot).substr(s+1); }

    // ---- Walk ----
    std::vector<std::string> treeLines;
    std::vector<FileStat>    stats;
    treeLines.push_back(WtoU8(rootName) + "/");
    WalkTree(normRoot, L"", "", normOut, treeLines, stats);

    // ---- Count lines for text files ----
    long long totalLines = 0;
    for (auto& fs : stats) {
        std::wstring name = fs.relPath.substr(
            fs.relPath.rfind(L'\\') == std::wstring::npos ? 0
                                                          : fs.relPath.rfind(L'\\')+1);
        if (IsTextFile(name) && fs.size <= MAX_DUMP_BYTES) {
            fs.lines = CountLines(fs.fullPath);
            if (fs.lines > 0) totalLines += fs.lines;
        }
    }

    int       fileCount  = (int)stats.size();
    long long totalBytes = 0;
    for (auto& fs : stats) totalBytes += fs.size;

    // ---- Top-15 largest ----
    std::vector<const FileStat*> bySize;
    for (auto& fs : stats) bySize.push_back(&fs);
    std::sort(bySize.begin(), bySize.end(),
              [](const FileStat* a, const FileStat* b){ return a->size > b->size; });
    int topN = (int)std::min((int)bySize.size(), 15);

    // ---- Build output ----
    std::ostringstream md;

    // Header
    md << "✅ Export complete.\n";
    md << "   Output: "          << WtoU8(normOut) << "\n";
    md << "   Files exported: "  << fileCount      << "\n";
    md << "   Lines written : "  << totalLines     << "\n";
    md << "   Bytes (source): "  << totalBytes     << "\n";
    md << "\n";

    // Environment
    md << "# Environment\n";
    md << "- Scanned Dir: " << WtoU8(normRoot)  << "\n";
    md << "- Timestamp:   " << GetTimestamp()   << "\n";
    md << "- OS:          Windows 10 (x86_64)\n";
    md << "- Tool:        read.exe\n";
    md << "\n";

    // Directory Tree
    md << "# Directory Tree\n";
    for (auto& l : treeLines) md << l << "\n";
    md << "\n";

    // File List & Stats
    md << "# File List & Stats\n";
    md << std::string(100, '-') << "\n";
    char hdr[256];
    snprintf(hdr, sizeof(hdr), "%-60s  %10s  %7s  %20s",
             "Path", "Size", "Lines", "Modified (local)");
    md << hdr << "\n";
    md << std::string(100, '-') << "\n";
    md << "** BRIEF MODE: details omitted; see Top-N below **\n\n";
    md << "Top " << topN << " largest files:\n";
    for (int i = 0; i < topN; ++i) {
        const auto* fs = bySize[i];
        char row[256];
        snprintf(row, sizeof(row), "%-60s  %10s",
                 WtoU8(fs->relPath).c_str(), FormatSize(fs->size).c_str());
        md << row << "\n";
    }
    md << std::string(100, '-') << "\n";
    {
        char tot[256];
        snprintf(tot, sizeof(tot), "%-60s  %10s  %7lld  %20s",
                 "TOTALS", FormatSize(totalBytes).c_str(),
                 totalLines, ("files:"+std::to_string(fileCount)).c_str());
        md << tot << "\n";
    }
    md << "\n";

    // Concatenated File Contents
    md << "# Concatenated File Contents\n";
    for (auto& fs : stats) {
        std::wstring name = fs.relPath.substr(
            fs.relPath.rfind(L'\\') == std::wstring::npos ? 0
                                                          : fs.relPath.rfind(L'\\')+1);
        if (!IsTextFile(name)) continue;

        std::string rel = WtoU8(fs.relPath);
        md << "\n===== BEGIN FILE: " << rel << " =====\n";
        std::string content = ReadAsUtf8(fs.fullPath, fs.size);
        if (content.empty()) {
            md << "[SKIPPED] Non-text or too large.\n";
        } else {
            // Strip trailing whitespace
            while (!content.empty() && (content.back()=='\n' || content.back()=='\r'))
                content.pop_back();
            md << content << "\n";
        }
        md << "===== END FILE: " << rel << " =====\n\n";
    }

    md << "\n_Generated by read.exe for " << WtoU8(normRoot) << "_\n";

    // Write UTF-8 (no BOM — matches Python read.py output)
    std::ofstream f(outPath.c_str(), std::ios::binary);
    if (!f) return false;
    f << md.str();
    return f.good();
}

// ── window proc ──────────────────────────────────────────────────────────────

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    switch (msg)
    {
    case WM_CREATE:
    {
        hFont = CreateFontW(16, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                            CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                            DEFAULT_PITCH | FF_SWISS, L"Segoe UI");

        auto mkLabel = [&](int id, const wchar_t* text) {
            HWND h = CreateWindowExW(0, L"STATIC", text,
                WS_CHILD | WS_VISIBLE | SS_LEFT,
                0, 0, 0, 0, hwnd, (HMENU)(INT_PTR)id, nullptr, nullptr);
            SendMessageW(h, WM_SETFONT, (WPARAM)hFont, TRUE);
            return h;
        };
        auto mkEdit = [&](int id, const wchar_t* hint) {
            HWND h = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", hint,
                WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
                0, 0, 0, 0, hwnd, (HMENU)(INT_PTR)id, nullptr, nullptr);
            SendMessageW(h, WM_SETFONT, (WPARAM)hFont, TRUE);
            return h;
        };
        auto mkBtn = [&](int id, const wchar_t* text) {
            HWND h = CreateWindowExW(0, L"BUTTON", text,
                WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                0, 0, 0, 0, hwnd, (HMENU)(INT_PTR)id, nullptr, nullptr);
            SendMessageW(h, WM_SETFONT, (WPARAM)hFont, TRUE);
            return h;
        };

        mkLabel(ID_LABEL_INPUT,  L"Scan folder");
        hInputEdit = mkEdit(ID_INPUT_EDIT, L"");
        mkBtn(ID_INPUT_BROWSE,  L"Browse…");

        mkLabel(ID_LABEL_OUTPUT, L"Output file");
        hOutputEdit = mkEdit(ID_OUTPUT_EDIT, L"");
        mkBtn(ID_OUTPUT_BROWSE, L"Browse…");

        hRunBtn = mkBtn(ID_RUN_BTN, L"▶  Run");

        hLogEdit = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
            WS_CHILD | WS_VISIBLE | WS_VSCROLL |
            ES_MULTILINE | ES_READONLY | ES_AUTOVSCROLL,
            0, 0, 0, 0, hwnd, (HMENU)ID_LOG_EDIT, nullptr, nullptr);
        SendMessageW(hLogEdit, WM_SETFONT, (WPARAM)hFont, TRUE);

        Log(L"Ready. Select a folder and output path, then click Run.");
        break;
    }

    case WM_SIZE:
        LayoutControls(hwnd);
        break;

    case WM_COMMAND:
        switch (LOWORD(wp))
        {
        case ID_INPUT_BROWSE:
        {
            std::wstring path = BrowseFolder(hwnd);
            if (!path.empty())
            {
                SetWindowTextW(hInputEdit, path.c_str());
                // auto-fill output: sibling of selected folder, named <folder>.md
                {
                    size_t slash = path.rfind(L'\\');
                    std::wstring parent  = (slash != std::wstring::npos) ? path.substr(0, slash) : path;
                    std::wstring folderName = (slash != std::wstring::npos) ? path.substr(slash + 1) : path;
                    std::wstring def = parent + L"\\" + folderName + L".md";
                    SetWindowTextW(hOutputEdit, def.c_str());
                }
            }
            break;
        }
        case ID_OUTPUT_BROWSE:
        {
            wchar_t inputBuf[MAX_PATH] = {};
            GetWindowTextW(hInputEdit, inputBuf, MAX_PATH);
            std::wstring path = BrowseOutputFile(hwnd, inputBuf);
            if (!path.empty())
                SetWindowTextW(hOutputEdit, path.c_str());
            break;
        }
        case ID_RUN_BTN:
        {
            wchar_t inBuf[MAX_PATH] = {}, outBuf[MAX_PATH] = {};
            GetWindowTextW(hInputEdit,  inBuf,  MAX_PATH);
            GetWindowTextW(hOutputEdit, outBuf, MAX_PATH);

            if (wcslen(inBuf) == 0) {
                Log(L"[!] Please select a folder to scan.");
                break;
            }
            if (wcslen(outBuf) == 0) {
                Log(L"[!] Please choose an output file.");
                break;
            }

            Log(std::wstring(L"[→] Scan:   ") + inBuf);
            Log(std::wstring(L"[→] Output: ") + outBuf);
            EnableWindow(hRunBtn, FALSE);
            Log(L"[…] Scanning…");

            if (RunSnapshot(inBuf, outBuf, hwnd)) {
                Log(L"[OK] Snapshot written.");
            } else {
                Log(L"[!] Failed to write output file.");
            }
            EnableWindow(hRunBtn, TRUE);
            break;
        }
        }
        break;

    case WM_CTLCOLORSTATIC:
    {
        HDC hdc = (HDC)wp;
        SetBkColor(hdc, GetSysColor(COLOR_WINDOW));
        return (LRESULT)GetSysColorBrush(COLOR_WINDOW);
    }

    case WM_DESTROY:
        DeleteObject(hFont);
        PostQuitMessage(0);
        break;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

// ── entry point ──────────────────────────────────────────────────────────────

int WINAPI wWinMain(HINSTANCE hInst, HINSTANCE, LPWSTR, int nCmdShow)
{
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);

    WNDCLASSEXW wc = {};
    wc.cbSize        = sizeof(wc);
    wc.lpfnWndProc   = WndProc;
    wc.hInstance     = hInst;
    wc.hCursor       = LoadCursorW(nullptr, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    wc.lpszClassName = L"ReadExeWnd";
    wc.hIcon         = LoadIconW(nullptr, IDI_APPLICATION);
    RegisterClassExW(&wc);

    HWND hwnd = CreateWindowExW(0, L"ReadExeWnd", L"read.exe",
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, CW_USEDEFAULT, 640, 480,
        nullptr, nullptr, hInst, nullptr);

    ShowWindow(hwnd, nCmdShow);
    UpdateWindow(hwnd);

    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0))
    {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    CoUninitialize();
    return (int)msg.wParam;
}
