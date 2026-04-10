// main_gui.mm — macOS GUI for the "read" directory scanner
// Packages into read.app — double-click to open.
// Build: bash build_gui.sh

#import <Cocoa/Cocoa.h>
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

// ── constants (keep in sync with main.cpp / win/main.cpp) ─────────────────

#define MAX_DUMP_BYTES (5LL * 1024 * 1024)
#define BRANCH_MID "\xe2\x94\x9c\xe2\x94\x80\xe2\x94\x80 "
#define BRANCH_END "\xe2\x94\x94\xe2\x94\x80\xe2\x94\x80 "
#define PIPE_CONT  "\xe2\x94\x82   "
#define PIPE_SPACE "    "

static const char* s_ignoreDirs[] = {
    // version control
    ".git",
    // editors / IDEs
    ".idea", ".vscode",
    // Python
    "__pycache__", ".pytest_cache", ".mypy_cache", ".tox", ".hypothesis", "htmlcov",
    // JavaScript / Node
    "node_modules", "bower_components", ".parcel-cache", ".turbo", ".nyc_output",
    // build outputs
    "dist", "build", "out", "target", "bin", "obj",
    // virtual envs
    ".venv", "venv",
    // caches
    ".cache",
    // Java / Kotlin / Android
    ".gradle",
    // frontend frameworks
    ".svelte-kit", ".next", ".expo", ".nuxt",
    // iOS / macOS
    "Pods", "Carthage", "DerivedData",
    // Swift Package Manager
    ".build",
    // Go / PHP / Ruby vendoring
    "vendor",
    // Dart / Flutter
    ".dart_tool",
    // test coverage
    "coverage",
    // misc
    "browser-profiles", "tmp", "temp",
    nullptr
};

static const char* s_binaryExts[] = {
    // compiled / linked
    ".dll", ".so", ".dylib", ".a", ".lib", ".exe", ".o",
    ".pyc", ".pyo", ".class", ".jar", ".war", ".wasm",
    // archives
    ".zip", ".tar", ".gz", ".tgz", ".bz2", ".xz", ".7z", ".rar",
    // images
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".bmp", ".tiff", ".tif",
    // documents
    ".pdf",
    // video / audio
    ".mp4", ".mov", ".avi", ".mkv", ".mp3", ".wav", ".flac", ".aac",
    // databases
    ".db", ".sqlite", ".sqlite3", ".wal", ".ldb",
    // data / binary blobs
    ".pak", ".dat", ".bin",
    // fonts
    ".woff", ".woff2", ".ttf", ".otf",
    // mobile / desktop packages
    ".apk", ".ipa", ".dmg", ".pkg", ".msi", ".deb", ".rpm",
    // editor swap files
    ".swp", ".swo",
    nullptr
};

static const char* s_textExts[] = {
    // plain text / docs
    ".txt", ".md", ".mdx", ".rst",
    // Python
    ".py", ".pyi",
    // data / config
    ".json", ".jsonc", ".yml", ".yaml", ".ini", ".cfg", ".toml",
    ".csv", ".xml", ".conf", ".properties", ".plist",
    // web
    ".html", ".htm", ".css", ".js", ".ts", ".tsx", ".jsx",
    ".cjs", ".mjs", ".vue", ".svelte", ".svg",
    // C family
    ".c", ".h", ".cpp", ".hpp", ".mm", ".m",
    // JVM
    ".cs", ".java", ".kt", ".kts", ".scala",
    // systems
    ".go", ".rs",
    // scripting
    ".rb", ".php", ".pl", ".lua", ".r",
    // shell
    ".sh", ".bash", ".zsh", ".fish", ".ps1", ".bat", ".cmd",
    // mobile / desktop
    ".swift", ".dart",
    // functional / other
    ".hs", ".ex", ".exs", ".erl", ".clj", ".ml",
    // infra / schemas
    ".tf", ".hcl", ".proto", ".graphql", ".gql", ".prisma", ".sol",
    // misc
    ".env", ".lock", ".mod", ".sum", ".inc", ".feature",
    nullptr
};

static const char* s_textNames[] = {
    "Dockerfile", ".dockerignore",
    "Makefile", "Procfile",
    "README", "LICENSE", "CHANGELOG",
    ".gitignore", ".gitattributes",
    ".npmrc", ".nvmrc", ".node-version",
    ".editorconfig", ".prettierrc", ".eslintrc", ".babelrc",
    nullptr
};

// ── helpers ────────────────────────────────────────────────────────────────

static bool nameInList(const char* const* list, const char* name) {
    for (int i = 0; list[i]; ++i)
        if (strcasecmp(list[i], name) == 0) return true;
    return false;
}

static std::string extOf(const std::string& name) {
    size_t dot = name.rfind('.');
    if (dot == std::string::npos || dot == 0) return "";
    std::string ext = name.substr(dot);
    for (auto& c : ext) c = (char)tolower((unsigned char)c);
    return ext;
}

static bool isIgnoreDir (const std::string& n) { return nameInList(s_ignoreDirs, n.c_str()); }
static bool isBinaryFile(const std::string& n) {
    std::string e = extOf(n);
    return !e.empty() && nameInList(s_binaryExts, e.c_str());
}
static bool isTextFile(const std::string& name) {
    std::string e = extOf(name);
    if (!e.empty() && nameInList(s_textExts, e.c_str())) return true;
    return nameInList(s_textNames, name.c_str());
}

static std::string formatSize(long long b) {
    char buf[32];
    if      (b < 1024LL)           snprintf(buf, sizeof(buf), "%.1fB",  (double)b);
    else if (b < 1024LL*1024)      snprintf(buf, sizeof(buf), "%.1fKB", b/1024.0);
    else if (b < 1024LL*1024*1024) snprintf(buf, sizeof(buf), "%.1fMB", b/(1024.0*1024));
    else                           snprintf(buf, sizeof(buf), "%.1fGB", b/(1024.0*1024*1024));
    return buf;
}

static std::string getTimestamp() {
    time_t now = time(nullptr);
    struct tm* lt = localtime(&now);
    char buf[64];
    strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%S%z", lt);
    std::string s = buf;
    if (s.size() >= 5) {
        size_t tzpos = s.size() - 4;
        if (s[tzpos-1] == '+' || s[tzpos-1] == '-')
            s.insert(tzpos + 2, ":");
    }
    return s;
}

static std::string mtimeStr(time_t t) {
    struct tm* lt = localtime(&t);
    char buf[32];
    strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", lt);
    return buf;
}

// ── data structures ────────────────────────────────────────────────────────

struct FileStat {
    std::string relPath, fullPath, mtime;
    long long   size = 0, lines = -1;
};

struct RawEntry {
    std::string name, mtime;
    bool        isDir;
    long long   size;
};

// ── directory listing ──────────────────────────────────────────────────────

static std::vector<RawEntry> listVisible(const std::string& dir,
                                          const std::string& skipFull) {
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
        if (isDir  && isIgnoreDir(name))  continue;
        if (!isDir && isBinaryFile(name)) continue;
        long long sz = isDir ? 0 : (long long)st.st_size;
        out.push_back({name, isDir ? "" : mtimeStr(st.st_mtime), isDir, sz});
    }
    closedir(d);
    std::sort(out.begin(), out.end(), [](const RawEntry& a, const RawEntry& b) {
        if (a.isDir != b.isDir) return (int)a.isDir > (int)b.isDir;
        return strcasecmp(a.name.c_str(), b.name.c_str()) < 0;
    });
    return out;
}

// ── recursive walk ─────────────────────────────────────────────────────────

static void walkTree(const std::string& dir, const std::string& rel,
                     const std::string& prefix, const std::string& skipFull,
                     std::vector<std::string>& treeLines,
                     std::vector<FileStat>& stats) {
    auto entries = listVisible(dir, skipFull);
    for (size_t i = 0; i < entries.size(); ++i) {
        bool last = (i == entries.size() - 1);
        const auto& e = entries[i];
        treeLines.push_back(prefix + (last ? BRANCH_END : BRANCH_MID)
                            + e.name + (e.isDir ? "/" : ""));
        std::string childFull = dir + "/" + e.name;
        std::string childRel  = rel.empty() ? e.name : rel + "/" + e.name;
        if (e.isDir)
            walkTree(childFull, childRel,
                     prefix + (last ? PIPE_SPACE : PIPE_CONT),
                     skipFull, treeLines, stats);
        else
            stats.push_back({childRel, childFull, e.mtime, e.size, -1});
    }
}

static long long countLines(const std::string& path) {
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

static std::string readAsUtf8(const std::string& path, long long size) {
    if (size <= 0 || size > MAX_DUMP_BYTES) return "";
    FILE* f = fopen(path.c_str(), "rb");
    if (!f) return "";
    std::string raw((size_t)size, '\0');
    size_t rd = fread(&raw[0], 1, (size_t)size, f);
    fclose(f);
    raw.resize(rd);
    if (raw.find('\0') != std::string::npos) return "";
    if (rd >= 3 &&
        (unsigned char)raw[0] == 0xEF &&
        (unsigned char)raw[1] == 0xBB &&
        (unsigned char)raw[2] == 0xBF)
        return raw.substr(3);
    return raw;
}

// ── core scan — returns {summary shown in GUI, ok, outPath} ───────────────

struct ScanResult { std::string summary, outPath; bool ok; };

static ScanResult doScan(const std::string& rootDir) {
    // Determine paths
    char resolved[PATH_MAX];
    std::string root = rootDir;
    if (realpath(root.c_str(), resolved)) root = resolved;

    size_t sl = root.rfind('/');
    std::string rootName   = (sl != std::string::npos) ? root.substr(sl+1) : root;
    std::string rootParent = (sl != std::string::npos) ? root.substr(0, sl) : ".";
    std::string outPath    = rootParent + "/" + rootName + ".md";

    char resolvedOut[PATH_MAX];
    std::string skipFull;
    if (realpath(outPath.c_str(), resolvedOut)) skipFull = resolvedOut;
    else                                         skipFull = outPath;

    // Walk
    std::vector<std::string> treeLines;
    std::vector<FileStat>    stats;
    treeLines.push_back(rootName + "/");
    walkTree(root, "", "", skipFull, treeLines, stats);

    // Count lines
    long long totalLines = 0;
    for (auto& fs : stats) {
        size_t s = fs.relPath.rfind('/');
        std::string name = (s != std::string::npos) ? fs.relPath.substr(s+1) : fs.relPath;
        if (isTextFile(name) && fs.size <= MAX_DUMP_BYTES) {
            fs.lines = countLines(fs.fullPath);
            if (fs.lines > 0) totalLines += fs.lines;
        }
    }

    int fileCount = (int)stats.size();
    long long totalBytes = 0;
    for (auto& fs : stats) totalBytes += fs.size;

    // Top-15 largest
    std::vector<const FileStat*> bySize;
    for (auto& fs : stats) bySize.push_back(&fs);
    std::sort(bySize.begin(), bySize.end(),
              [](const FileStat* a, const FileStat* b){ return a->size > b->size; });
    int topN = (int)std::min((int)bySize.size(), 15);

    // Build markdown
    std::ostringstream md;
    md << "# Environment\n"
       << "- Scanned Dir: " << root          << "\n"
       << "- Timestamp:   " << getTimestamp()<< "\n"
       << "- OS:          macOS\n"
       << "- Tool:        read (C++ GUI)\n\n";

    md << "# Directory Tree\n";
    for (auto& l : treeLines) md << l << "\n";
    md << "\n";

    md << "# File List & Stats\n"
       << std::string(100, '-') << "\n";
    char hdr[256];
    snprintf(hdr, sizeof(hdr), "%-60s  %10s  %7s  %20s",
             "Path", "Size", "Lines", "Modified (local)");
    md << hdr << "\n" << std::string(100, '-') << "\n"
       << "** BRIEF MODE: details omitted; see Top-N below **\n\n"
       << "Top " << topN << " largest files:\n";
    for (int i = 0; i < topN; ++i) {
        char row[256];
        snprintf(row, sizeof(row), "%-60s  %10s",
                 bySize[i]->relPath.c_str(), formatSize(bySize[i]->size).c_str());
        md << row << "\n";
    }
    md << std::string(100, '-') << "\n";
    {
        char tot[256];
        snprintf(tot, sizeof(tot), "%-60s  %10s  %7lld  %20s",
                 "TOTALS", formatSize(totalBytes).c_str(),
                 totalLines, ("files:"+std::to_string(fileCount)).c_str());
        md << tot << "\n\n";
    }

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
    md << "\n_Generated by read for " << root << "_\n";

    // Write file
    std::ofstream f(outPath);
    if (!f || !f.good())
        return {"Error: cannot write to " + outPath, outPath, false};
    f << md.str();
    if (!f.good())
        return {"Error: write failed (disk full?)", outPath, false};

    // Summary for GUI
    std::ostringstream sum;
    sum << "Done.\n\n"
        << "Output:  " << outPath << "\n"
        << "Files:   " << fileCount << "\n"
        << "Lines:   " << totalLines << "\n"
        << "Size:    " << formatSize(totalBytes) << "\n";
    if (topN > 0) {
        sum << "\nTop " << topN << " largest files:\n";
        for (int i = 0; i < topN; ++i)
            sum << "  " << bySize[i]->relPath
                << "  (" << formatSize(bySize[i]->size) << ")\n";
    }
    return {sum.str(), outPath, true};
}

// ── AppDelegate ────────────────────────────────────────────────────────────

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSWindow             *window;
@property (strong) NSTextField          *pathLabel;
@property (strong) NSButton             *selectBtn;
@property (strong) NSTextField          *outLabel;
@property (strong) NSButton             *runBtn;
@property (strong) NSProgressIndicator  *spinner;
@property (strong) NSButton             *showBtn;   // "在 Finder 中显示"
@property (strong) NSTextView           *logView;
@property (copy)   NSString             *selectedPath;
@property (copy)   NSString             *lastOutPath;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notif {
    // ── Window ──────────────────────────────────────────────────────────────
    NSRect frame = NSMakeRect(0, 0, 640, 480);
    self.window = [[NSWindow alloc]
        initWithContentRect:frame
        styleMask: NSWindowStyleMaskTitled
                  | NSWindowStyleMaskClosable
                  | NSWindowStyleMaskMiniaturizable
        backing:NSBackingStoreBuffered
        defer:NO];
    self.window.title = @"read — Directory Snapshot";
    [self.window center];
    NSView *cv = self.window.contentView;

    // ── Row 1: path label + select button (y=432) ───────────────────────────
    self.pathLabel = [NSTextField labelWithString:@"No folder selected"];
    self.pathLabel.frame = NSMakeRect(16, 432, 472, 24);
    self.pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.pathLabel.textColor = [NSColor secondaryLabelColor];
    [cv addSubview:self.pathLabel];

    self.selectBtn = [NSButton buttonWithTitle:@"Choose Folder…"
                                        target:self
                                        action:@selector(selectFolder:)];
    self.selectBtn.frame = NSMakeRect(500, 428, 124, 32);
    [cv addSubview:self.selectBtn];

    // ── Row 2: output path hint (y=406) ─────────────────────────────────────
    self.outLabel = [NSTextField labelWithString:@""];
    self.outLabel.frame = NSMakeRect(16, 406, 608, 18);
    self.outLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.outLabel.textColor = [NSColor tertiaryLabelColor];
    self.outLabel.font = [NSFont systemFontOfSize:11];
    [cv addSubview:self.outLabel];

    // ── Row 3: run button + spinner + show-in-finder (y=366) ────────────────
    self.runBtn = [NSButton buttonWithTitle:@"Scan"
                                     target:self
                                     action:@selector(startScan:)];
    self.runBtn.frame = NSMakeRect(16, 366, 96, 32);
    self.runBtn.enabled = NO;
    [cv addSubview:self.runBtn];

    self.spinner = [[NSProgressIndicator alloc]
                    initWithFrame:NSMakeRect(120, 370, 24, 24)];
    self.spinner.style = NSProgressIndicatorStyleSpinning;
    self.spinner.hidden = YES;
    [cv addSubview:self.spinner];

    self.showBtn = [NSButton buttonWithTitle:@"Show in Finder"
                                      target:self
                                      action:@selector(showInFinder:)];
    self.showBtn.frame = NSMakeRect(152, 366, 140, 32);
    self.showBtn.hidden = YES;
    [cv addSubview:self.showBtn];

    // ── Log view (y=16, h=342) ───────────────────────────────────────────────
    NSScrollView *scroll = [[NSScrollView alloc]
                            initWithFrame:NSMakeRect(16, 16, 608, 342)];
    scroll.hasVerticalScroller   = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.borderType = NSBezelBorder;
    scroll.autohidesScrollers = YES;

    self.logView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 608, 342)];
    self.logView.editable   = NO;
    self.logView.selectable = YES;
    self.logView.font = [NSFont monospacedSystemFontOfSize:12
                                                    weight:NSFontWeightRegular];
    self.logView.textColor       = [NSColor labelColor];
    self.logView.backgroundColor = [NSColor textBackgroundColor];
    self.logView.string = @"Choose a folder, then click Scan.\n"
                           "The output .md file will be created next to the selected folder.";
    [scroll setDocumentView:self.logView];
    [cv addSubview:scroll];

    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)selectFolder:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles          = NO;
    panel.canChooseDirectories    = YES;
    panel.allowsMultipleSelection = NO;
    panel.title  = @"Choose a folder to scan";
    panel.prompt = @"Choose";

    if ([panel runModal] != NSModalResponseOK) return;

    self.selectedPath = panel.URL.path;
    self.pathLabel.stringValue = self.selectedPath;
    self.pathLabel.textColor   = [NSColor labelColor];

    NSString *folderName = panel.URL.lastPathComponent;
    NSString *parentDir  = panel.URL.URLByDeletingLastPathComponent.path;
    NSString *outPath    = [parentDir stringByAppendingPathComponent:
                            [folderName stringByAppendingString:@".md"]];
    self.outLabel.stringValue = [NSString stringWithFormat:@"Output → %@", outPath];

    self.runBtn.enabled  = YES;
    self.showBtn.hidden  = YES;
    self.lastOutPath     = nil;
}

- (void)startScan:(id)sender {
    if (!self.selectedPath) return;

    self.runBtn.enabled    = NO;
    self.selectBtn.enabled = NO;
    self.showBtn.hidden    = YES;
    self.spinner.hidden    = NO;
    [self.spinner startAnimation:nil];
    self.logView.string = @"Scanning…\n";

    NSString *rootPath = self.selectedPath;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        ScanResult result = doScan(rootPath.UTF8String);
        NSString *summary = [NSString stringWithUTF8String:result.summary.c_str()];
        NSString *outPath = [NSString stringWithUTF8String:result.outPath.c_str()];
        bool ok = result.ok;

        dispatch_async(dispatch_get_main_queue(), ^{
            self.logView.string    = summary;
            self.spinner.hidden    = YES;
            [self.spinner stopAnimation:nil];
            self.runBtn.enabled    = YES;
            self.selectBtn.enabled = YES;
            if (ok) {
                self.lastOutPath    = outPath;
                self.showBtn.hidden = NO;
            }
        });
    });
}

- (void)showInFinder:(id)sender {
    if (!self.lastOutPath) return;
    [[NSWorkspace sharedWorkspace]
     selectFile:self.lastOutPath
     inFileViewerRootedAtPath:@""];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
    return YES;
}

@end

// ── entry point ────────────────────────────────────────────────────────────

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyRegular;
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
