// read — macOS/Linux CLI
// Usage: ./read <folder> [output.md]
// If output is omitted, writes <foldername>.md next to the scanned folder.
// Output format is identical to the Windows GUI version (win/read_gui.exe).

#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <algorithm>
#include <cstring>
#include <cstdio>
#include <ctime>
#include <climits>
#include <sys/stat.h>
#include <sys/types.h>
#include <dirent.h>
#include <unistd.h>

#define MAX_DUMP_BYTES (5LL * 1024 * 1024)
#define BRANCH_MID "\xe2\x94\x9c\xe2\x94\x80\xe2\x94\x80 "
#define BRANCH_END "\xe2\x94\x94\xe2\x94\x80\xe2\x94\x80 "
#define PIPE_CONT  "\xe2\x94\x82   "
#define PIPE_SPACE "    "

// ── ignore / text lists (keep in sync with win/main.cpp) ────────────────────

static const char* s_ignoreDirs[] = {
    ".git", ".idea", ".vscode", "__pycache__", ".pytest_cache",
    ".mypy_cache", "node_modules", "dist", "build", "target",
    "bin", "obj", ".venv", "venv", ".cache", ".tox",
    ".gradle", ".svelte-kit", ".next", "browser-profiles", nullptr
};

static const char* s_binaryExts[] = {
    ".dll", ".so", ".dylib", ".a", ".lib", ".exe",
    ".zip", ".tar", ".gz", ".7z", ".rar",
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".bmp",
    ".pdf", ".mp4", ".mov", ".mp3", ".wav", ".avi",
    ".db", ".sqlite", ".sqlite3", ".wal", ".ldb",
    ".pak", ".dat", ".bin",
    ".woff", ".woff2", ".ttf", ".otf",
    nullptr
};

static const char* s_textExts[] = {
    ".txt", ".md", ".py", ".json", ".yml", ".yaml",
    ".ini", ".cfg", ".toml", ".csv", ".xml",
    ".html", ".htm", ".css", ".js", ".ts", ".tsx", ".jsx",
    ".c", ".h", ".cpp", ".hpp", ".cs", ".java",
    ".kt", ".go", ".rs", ".rb", ".php",
    ".sh", ".bash", ".zsh", ".ps1",
    ".r", ".swift", ".pl", ".lua",
    ".dart", ".scala", ".hs", ".inc", ".vue", ".svelte", ".svg",
    ".env", ".lock", ".mod", ".sum", ".tf", ".hcl", ".proto",
    nullptr
};

static const char* s_textNames[] = {
    "Dockerfile", "Makefile", "README", "LICENSE", ".gitignore",
    ".npmrc", ".editorconfig", nullptr
};

// ── helpers ──────────────────────────────────────────────────────────────────

static bool nameInList(const char* const* list, const char* name)
{
    for (int i = 0; list[i]; ++i)
        if (strcasecmp(list[i], name) == 0) return true;
    return false;
}

static std::string extOf(const std::string& name)
{
    size_t dot = name.rfind('.');
    if (dot == std::string::npos || dot == 0) return "";
    std::string ext = name.substr(dot);
    for (auto& c : ext) c = (char)tolower((unsigned char)c);
    return ext;
}

static bool isIgnoreDir (const std::string& n) { return nameInList(s_ignoreDirs,  n.c_str()); }
static bool isBinaryFile(const std::string& n)
{
    std::string ext = extOf(n);
    return !ext.empty() && nameInList(s_binaryExts, ext.c_str());
}
static bool isTextFile(const std::string& name)
{
    std::string ext = extOf(name);
    if (!ext.empty() && nameInList(s_textExts, ext.c_str())) return true;
    return nameInList(s_textNames, name.c_str());
}

static std::string formatSize(long long b)
{
    char buf[32];
    if      (b < 1024LL)            snprintf(buf, sizeof(buf), "%.1fB",  (double)b);
    else if (b < 1024LL*1024)       snprintf(buf, sizeof(buf), "%.1fKB", b/1024.0);
    else if (b < 1024LL*1024*1024)  snprintf(buf, sizeof(buf), "%.1fMB", b/(1024.0*1024));
    else                            snprintf(buf, sizeof(buf), "%.1fGB", b/(1024.0*1024*1024));
    return buf;
}

static std::string getTimestamp()
{
    time_t now = time(nullptr);
    struct tm* lt = localtime(&now);
    char buf[64];
    strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%S%z", lt);
    // insert colon in timezone offset: +1000 → +10:00
    std::string s = buf;
    if (s.size() >= 5) {
        size_t tzpos = s.size() - 4;
        if (s[tzpos-1] == '+' || s[tzpos-1] == '-')
            s.insert(tzpos + 2, ":");
    }
    return s;
}

static std::string mtimeStr(time_t t)
{
    struct tm* lt = localtime(&t);
    char buf[32];
    strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", lt);
    return buf;
}

// ── file stats ───────────────────────────────────────────────────────────────

struct FileStat {
    std::string relPath;
    std::string fullPath;
    long long   size  = 0;
    long long   lines = -1;
    std::string mtime;
};

// ── directory entry (for sorted listing) ────────────────────────────────────

struct RawEntry {
    std::string name;
    bool        isDir;
    long long   size;
    std::string mtime;
};

static std::vector<RawEntry> listVisible(const std::string& dir,
                                          const std::string& skipFull)
{
    std::vector<RawEntry> out;
    DIR* d = opendir(dir.c_str());
    if (!d) return out;

    struct dirent* ent;
    while ((ent = readdir(d)) != nullptr) {
        std::string name = ent->d_name;
        if (name == "." || name == "..") continue;

        std::string full = dir + "/" + name;
        if (!skipFull.empty() && full == skipFull) continue;

        struct stat st;
        if (lstat(full.c_str(), &st) != 0) continue;

        bool isDir = S_ISDIR(st.st_mode);
        if (isDir  && isIgnoreDir(name))   continue;
        if (!isDir && isBinaryFile(name))  continue;

        long long sz = isDir ? 0 : (long long)st.st_size;
        out.push_back({name, isDir, sz, isDir ? "" : mtimeStr(st.st_mtime)});
    }
    closedir(d);

    std::sort(out.begin(), out.end(), [](const RawEntry& a, const RawEntry& b) {
        if (a.isDir != b.isDir) return (int)a.isDir > (int)b.isDir;
        return strcasecmp(a.name.c_str(), b.name.c_str()) < 0;
    });
    return out;
}

// ── recursive tree + stat collector ─────────────────────────────────────────

static void walkTree(const std::string& dir, const std::string& rel,
                     const std::string& prefix,
                     const std::string& skipFull,
                     std::vector<std::string>& treeLines,
                     std::vector<FileStat>&    stats)
{
    auto entries = listVisible(dir, skipFull);
    for (size_t i = 0; i < entries.size(); ++i) {
        bool last = (i == entries.size() - 1);
        const auto& e = entries[i];
        std::string branch = last ? BRANCH_END : BRANCH_MID;
        treeLines.push_back(prefix + branch + e.name + (e.isDir ? "/" : ""));

        std::string childFull = dir + "/" + e.name;
        std::string childRel  = rel.empty() ? e.name : rel + "/" + e.name;

        if (e.isDir) {
            walkTree(childFull, childRel,
                     prefix + (last ? PIPE_SPACE : PIPE_CONT),
                     skipFull, treeLines, stats);
        } else {
            stats.push_back({childRel, childFull, e.size, -1, e.mtime});
        }
    }
}

// ── count lines ──────────────────────────────────────────────────────────────

static long long countLines(const std::string& path)
{
    FILE* f = fopen(path.c_str(), "rb");
    if (!f) return -1;
    char buf[65536]; size_t rd;
    long long n = 0; bool sawAny = false; char last = 0;
    while ((rd = fread(buf, 1, sizeof(buf), f)) > 0) {
        sawAny = true;
        for (size_t i = 0; i < rd; ++i) if (buf[i] == '\n') ++n;
        last = buf[rd-1];
    }
    fclose(f);
    if (sawAny && last != '\n') ++n;
    return n;
}

// ── read file as UTF-8 ───────────────────────────────────────────────────────

static std::string readAsUtf8(const std::string& path, long long size)
{
    if (size <= 0 || size > MAX_DUMP_BYTES) return "";
    FILE* f = fopen(path.c_str(), "rb");
    if (!f) return "";
    std::string raw((size_t)size, '\0');
    size_t rd = fread(&raw[0], 1, (size_t)size, f);
    fclose(f);
    raw.resize(rd);
    if (raw.find('\0') != std::string::npos) return ""; // binary
    // Strip UTF-8 BOM
    if (rd >= 3 &&
        (unsigned char)raw[0] == 0xEF &&
        (unsigned char)raw[1] == 0xBB &&
        (unsigned char)raw[2] == 0xBF)
        return raw.substr(3);
    return raw;
}

// ── entry point ──────────────────────────────────────────────────────────────

int main(int argc, char* argv[])
{
    if (argc < 2) {
        std::cerr << "Usage: read <folder> [output.md]\n";
        return 1;
    }

    // Resolve root path
    char resolvedRoot[PATH_MAX];
    if (!realpath(argv[1], resolvedRoot)) {
        std::cerr << "Error: cannot resolve path: " << argv[1] << "\n";
        return 1;
    }
    std::string rootDir = resolvedRoot;

    // Determine root name and parent
    size_t slash = rootDir.rfind('/');
    std::string rootName   = (slash != std::string::npos) ? rootDir.substr(slash + 1) : rootDir;
    std::string rootParent = (slash != std::string::npos) ? rootDir.substr(0, slash)  : ".";

    // Determine output path
    std::string outPath;
    if (argc >= 3) {
        outPath = argv[2];
    } else {
        outPath = rootParent + "/" + rootName + ".md";
    }

    // Resolve output path so we can exclude it from the scan
    char resolvedOut[PATH_MAX];
    std::string skipFull;
    if (realpath(outPath.c_str(), resolvedOut))
        skipFull = resolvedOut;
    else
        skipFull = outPath; // not yet existing — compare by constructed path

    // ── Walk ────────────────────────────────────────────────────────────────
    std::vector<std::string> treeLines;
    std::vector<FileStat>    stats;
    treeLines.push_back(rootName + "/");
    walkTree(rootDir, "", "", skipFull, treeLines, stats);

    // ── Count lines for text files ───────────────────────────────────────────
    long long totalLines = 0;
    for (auto& fs : stats) {
        size_t s = fs.relPath.rfind('/');
        std::string name = (s != std::string::npos) ? fs.relPath.substr(s+1) : fs.relPath;
        if (isTextFile(name) && fs.size <= MAX_DUMP_BYTES) {
            fs.lines = countLines(fs.fullPath);
            if (fs.lines > 0) totalLines += fs.lines;
        }
    }

    int       fileCount  = (int)stats.size();
    long long totalBytes = 0;
    for (auto& fs : stats) totalBytes += fs.size;

    // ── Top-15 largest ───────────────────────────────────────────────────────
    std::vector<const FileStat*> bySize;
    for (auto& fs : stats) bySize.push_back(&fs);
    std::sort(bySize.begin(), bySize.end(),
              [](const FileStat* a, const FileStat* b){ return a->size > b->size; });
    int topN = (int)std::min((int)bySize.size(), 15);

    // ── Build output ─────────────────────────────────────────────────────────
    std::ostringstream md;

    md << "✅ Export complete.\n";
    md << "   Output: "         << outPath    << "\n";
    md << "   Files exported: " << fileCount  << "\n";
    md << "   Lines written : " << totalLines << "\n";
    md << "   Bytes (source): " << totalBytes << "\n";
    md << "\n";

    md << "# Environment\n";
    md << "- Scanned Dir: " << rootDir        << "\n";
    md << "- Timestamp:   " << getTimestamp() << "\n";
#ifdef __APPLE__
    md << "- OS:          macOS (arm64/x86_64)\n";
#else
    md << "- OS:          Linux\n";
#endif
    md << "- Tool:        read (C++ CLI)\n";
    md << "\n";

    md << "# Directory Tree\n";
    for (auto& l : treeLines) md << l << "\n";
    md << "\n";

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
                 fs->relPath.c_str(), formatSize(fs->size).c_str());
        md << row << "\n";
    }
    md << std::string(100, '-') << "\n";
    {
        char tot[256];
        snprintf(tot, sizeof(tot), "%-60s  %10s  %7lld  %20s",
                 "TOTALS", formatSize(totalBytes).c_str(),
                 totalLines, ("files:"+std::to_string(fileCount)).c_str());
        md << tot << "\n";
    }
    md << "\n";

    md << "# Concatenated File Contents\n";
    for (auto& fs : stats) {
        size_t s = fs.relPath.rfind('/');
        std::string name = (s != std::string::npos) ? fs.relPath.substr(s+1) : fs.relPath;
        if (!isTextFile(name)) continue;

        md << "\n===== BEGIN FILE: " << fs.relPath << " =====\n";
        std::string content = readAsUtf8(fs.fullPath, fs.size);
        if (content.empty()) {
            md << "[SKIPPED] Non-text or too large.\n";
        } else {
            while (!content.empty() && (content.back()=='\n' || content.back()=='\r'))
                content.pop_back();
            md << content << "\n";
        }
        md << "===== END FILE: " << fs.relPath << " =====\n\n";
    }

    md << "\n_Generated by read for " << rootDir << "_\n";

    // ── Write ────────────────────────────────────────────────────────────────
    std::ofstream f(outPath);
    if (!f) {
        std::cerr << "Error: cannot write to " << outPath << "\n";
        return 1;
    }
    f << md.str();
    if (!f.good()) {
        std::cerr << "Error: write failed\n";
        return 1;
    }

    std::cout << "[OK] Wrote snapshot to: " << outPath << "\n";
    std::cout << "     Files: " << fileCount
              << "  Lines: " << totalLines
              << "  Size: " << formatSize(totalBytes) << "\n";
    return 0;
}
