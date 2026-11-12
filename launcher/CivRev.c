/* CivRev.exe -- double-clickable launcher for the Civ Rev port.
 *
 * Does the same job as run.bat, without a console window:
 *   - checks the game files are in ..\civrev-gamefiles
 *   - refuses to start a second copy of civrev.exe
 *   - rebuilds civrev.exe (build.ps1, in a visible window) when the ps3recomp
 *     runtime library is newer than it
 *   - sets PS3_VFS_ROOT, RSX_LIVE_DRAW=1, PS3_VERBOSE=0 (last two only if unset)
 *   - keeps the logs of the last 10 runs in logs\, writes run.log / run.err.log
 *   - gives the game window this launcher's icon and taskbar identity
 *   - reads CivRev.ini (made on first run): vibration=on/off -> PAD_RUMBLE
 *   - shows the [CRASH]/[ABORT]/[STACKOVERFLOW] lines if the game exits badly
 *
 * Keep CivRev.exe in the civrev-port folder (it finds everything relative to
 * itself); put a shortcut to it wherever you like. Build: build_launcher.ps1.
 */
#define WIN32_LEAN_AND_MEAN
#ifndef UNICODE
#define UNICODE
#endif
#include <windows.h>
#include <tlhelp32.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#define TITLE L"Civilization Revolution"
#define PATHN 1024
#define KEEP_LOGS 10

static wchar_t g_here[PATHN]; /* folder of this exe, ends with a backslash */

static void msg(UINT icon, const wchar_t *fmt, ...)
{
    wchar_t buf[4096];
    va_list ap;
    va_start(ap, fmt);
    _vsnwprintf_s(buf, PATHN * 4, _TRUNCATE, fmt, ap);
    va_end(ap);
    MessageBoxW(NULL, buf, TITLE, MB_OK | icon);
}

/* out = full, normalised path of g_here + rel */
static void here_path(wchar_t *out, const wchar_t *rel)
{
    wchar_t tmp[PATHN];
    _snwprintf_s(tmp, PATHN, _TRUNCATE, L"%s%s", g_here, rel);
    if (!GetFullPathNameW(tmp, PATHN, out, NULL))
        wcscpy_s(out, PATHN, tmp);
}

static int exists(const wchar_t *p)
{
    return GetFileAttributesW(p) != INVALID_FILE_ATTRIBUTES;
}

static int mtime(const wchar_t *p, ULONGLONG *t)
{
    WIN32_FILE_ATTRIBUTE_DATA a;
    if (!GetFileAttributesExW(p, GetFileExInfoStandard, &a))
        return 0;
    *t = ((ULONGLONG)a.ftLastWriteTime.dwHighDateTime << 32) | a.ftLastWriteTime.dwLowDateTime;
    return 1;
}

/* Names compare case-insensitively, so this launcher (CivRev.exe) matches
 * too: skip our own process. Another launcher copy counts as "running". */
static int game_running(void)
{
    int found = 0;
    DWORD self = GetCurrentProcessId();
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE)
        return 0;
    PROCESSENTRY32W pe = {sizeof pe};
    for (BOOL ok = Process32FirstW(snap, &pe); ok && !found; ok = Process32NextW(snap, &pe))
        found = pe.th32ProcessID != self && _wcsicmp(pe.szExeFile, L"civrev.exe") == 0;
    CloseHandle(snap);
    return found;
}

/* Run a command line, wait for it, return its exit code (-1 if it can't start). */
static long run_and_wait(wchar_t *cmd, DWORD flags)
{
    STARTUPINFOW si = {sizeof si};
    PROCESS_INFORMATION pi;
    if (!CreateProcessW(NULL, cmd, NULL, NULL, FALSE, flags, NULL, g_here, &si, &pi))
        return -1;
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD rc = 1;
    GetExitCodeProcess(pi.hProcess, &rc);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return (long)rc;
}

/* Relink civrev.exe when the ps3recomp runtime is newer (same rule as run.bat). */
static int rebuild_if_needed(const wchar_t *exe)
{
    wchar_t lib[PATHN], dir[PATHN];
    if (GetEnvironmentVariableW(L"PS3RECOMP_DIR", dir, PATHN)) {
        _snwprintf_s(lib, PATHN, _TRUNCATE, L"%s\\build-release\\ps3recomp_runtime.lib", dir);
    } else {
        here_path(lib, L"..\\ps3recomp\\build-release\\ps3recomp_runtime.lib");
    }
    ULONGLONG te = 0, tl = 0;
    int have_exe = mtime(exe, &te);
    if (have_exe && !(mtime(lib, &tl) && tl > te))
        return 1;

    /* build.ps1 path inside a single-quoted PowerShell string: double any ' */
    wchar_t script[PATHN], quoted[PATHN * 2];
    here_path(script, L"build.ps1");
    size_t q = 0;
    for (const wchar_t *s = script; *s && q < PATHN * 2 - 2; s++) {
        if (*s == L'\'')
            quoted[q++] = L'\'';
        quoted[q++] = *s;
    }
    quoted[q] = 0;

    wchar_t cmd[PATHN * 4];
    _snwprintf_s(cmd, PATHN * 4, _TRUNCATE,
        L"powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \""
        L"$host.UI.RawUI.WindowTitle='Rebuilding civrev.exe'; "
        L"Write-Host 'civrev.exe is older than the ps3recomp runtime - rebuilding, about a minute...'; "
        L"try { & '%s'; $c=$LASTEXITCODE } catch { Write-Host $_; $c=1 }; "
        L"if ($c -eq $null) { $c=0 }; "
        L"if ($c -ne 0) { Write-Host 'Build failed - see the messages above.'; Read-Host 'Press Enter to close' }; "
        L"exit $c\"",
        quoted);
    long rc = run_and_wait(cmd, CREATE_NEW_CONSOLE);
    if (rc != 0 || !exists(exe)) {
        msg(MB_ICONERROR, L"Rebuilding civrev.exe failed (code %ld).\n\n"
                          L"Try running build.ps1 in:\n%s", rc, g_here);
        return 0;
    }
    return 1;
}

static int cmp_desc(const void *a, const void *b)
{
    return -wcscmp((const wchar_t *)a, (const wchar_t *)b);
}

/* Move the previous run.err.log / run.log into logs\run_<time>.*, keep the newest 10. */
static void rotate_logs(void)
{
    wchar_t err[PATHN], out[PATHN], dir[PATHN], dst[PATHN];
    here_path(err, L"run.err.log");
    here_path(out, L"run.log");
    here_path(dir, L"logs");
    WIN32_FILE_ATTRIBUTE_DATA a;
    if (!GetFileAttributesExW(err, GetFileExInfoStandard, &a))
        return;

    FILETIME lft;
    SYSTEMTIME st;
    FileTimeToLocalFileTime(&a.ftLastWriteTime, &lft);
    FileTimeToSystemTime(&lft, &st);
    wchar_t stamp[64];
    _snwprintf_s(stamp, 64, _TRUNCATE, L"%04u-%02u-%02u_%02u-%02u-%02u",
                 st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);

    CreateDirectoryW(dir, NULL);
    _snwprintf_s(dst, PATHN, _TRUNCATE, L"%s\\run_%s.err.log", dir, stamp);
    MoveFileExW(err, dst, MOVEFILE_REPLACE_EXISTING | MOVEFILE_COPY_ALLOWED);
    if (exists(out)) {
        _snwprintf_s(dst, PATHN, _TRUNCATE, L"%s\\run_%s.log", dir, stamp);
        MoveFileExW(out, dst, MOVEFILE_REPLACE_EXISTING | MOVEFILE_COPY_ALLOWED);
    }

    enum { MAXN = 1024, NAMEN = 260 };
    static wchar_t names[MAXN][NAMEN];
    int n = 0;
    wchar_t pat[PATHN];
    _snwprintf_s(pat, PATHN, _TRUNCATE, L"%s\\run_*.err.log", dir);
    WIN32_FIND_DATAW fd;
    HANDLE h = FindFirstFileW(pat, &fd);
    if (h == INVALID_HANDLE_VALUE)
        return;
    do {
        if (n < MAXN)
            wcscpy_s(names[n++], NAMEN, fd.cFileName);
    } while (FindNextFileW(h, &fd));
    FindClose(h);
    qsort(names, n, sizeof names[0], cmp_desc);
    for (int i = KEEP_LOGS; i < n; i++) {
        _snwprintf_s(dst, PATHN, _TRUNCATE, L"%s\\%s", dir, names[i]);
        DeleteFileW(dst);
        size_t len = wcslen(dst);
        if (len > 8 && _wcsicmp(dst + len - 8, L".err.log") == 0) {
            wcscpy_s(dst + len - 8, PATHN - (len - 8), L".log");
            DeleteFileW(dst);
        }
    }
}

static void set_default(const wchar_t *name, const wchar_t *value)
{
    wchar_t cur[8];
    if (!GetEnvironmentVariableW(name, cur, 8) && GetLastError() == ERROR_ENVVAR_NOT_FOUND)
        SetEnvironmentVariableW(name, value);
}

/* ---- settings: CivRev.ini next to this exe ------------------------------ */
static const char k_default_ini[] =
    "; Civilization Revolution launcher settings. Edit with Notepad, save,\r\n"
    "; then start the game again.\r\n"
    "[game]\r\n"
    "; Controller vibration: on or off\r\n"
    "vibration=on\r\n";

static void apply_settings(void)
{
    wchar_t ini[PATHN], v[32];
    here_path(ini, L"CivRev.ini");
    if (!exists(ini)) {
        HANDLE f = CreateFileW(ini, GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
        if (f != INVALID_HANDLE_VALUE) {
            DWORD w;
            WriteFile(f, k_default_ini, (DWORD)(sizeof k_default_ini - 1), &w, NULL);
            CloseHandle(f);
        }
    }
    GetPrivateProfileStringW(L"game", L"vibration", L"on", v, 32, ini);
    const int off = !_wcsicmp(v, L"off") || !_wcsicmp(v, L"0") || !_wcsicmp(v, L"no") ||
                    !_wcsicmp(v, L"false");
    /* ps3recomp cellPad.c: PAD_RUMBLE=0 = no vibration. */
    SetEnvironmentVariableW(L"PAD_RUMBLE", off ? L"0" : L"1");
}

/* ---- game window icon ------------------------------------------------- */
typedef struct { DWORD pid; HICON big, small; int set; } icon_ctx;

static BOOL CALLBACK icon_cb(HWND w, LPARAM lp)
{
    icon_ctx *c = (icon_ctx *)lp;
    DWORD pid = 0;
    GetWindowThreadProcessId(w, &pid);
    if (pid != c->pid || !IsWindowVisible(w) || GetWindow(w, GW_OWNER))
        return TRUE;
    DWORD_PTR cur = 0;
    if (!SendMessageTimeoutW(w, WM_GETICON, ICON_BIG, 0, SMTO_ABORTIFHUNG, 200, &cur))
        return TRUE;
    if ((HICON)cur != c->big) {
        SendMessageTimeoutW(w, WM_SETICON, ICON_BIG, (LPARAM)c->big, SMTO_ABORTIFHUNG, 200, NULL);
        SendMessageTimeoutW(w, WM_SETICON, ICON_SMALL, (LPARAM)c->small, SMTO_ABORTIFHUNG, 200, NULL);
    }
    c->set = 1;
    return TRUE;
}

/* ---- crash report ----------------------------------------------------- */
static void report_crash(DWORD code, const wchar_t *errlog)
{
    char lines[3000] = "";
    size_t used = 0;
    int shown = 0;
    HANDLE f = CreateFileW(errlog, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
                           OPEN_EXISTING, 0, NULL);
    if (f != INVALID_HANDLE_VALUE) {
        LARGE_INTEGER size = {0};
        GetFileSizeEx(f, &size);
        const LONGLONG cap = 64ll << 20; /* read at most the last 64 MB */
        LONGLONG start = size.QuadPart > cap ? size.QuadPart - cap : 0;
        DWORD len = (DWORD)(size.QuadPart - start);
        char *buf = (char *)malloc((size_t)len + 1);
        DWORD got = 0;
        LARGE_INTEGER pos;
        pos.QuadPart = start;
        if (buf && SetFilePointerEx(f, pos, NULL, FILE_BEGIN) && ReadFile(f, buf, len, &got, NULL)) {
            buf[got] = 0;
            for (char *line = buf; line && *line && shown < 12;) {
                char *next = strchr(line, '\n');
                if (next)
                    *next++ = 0;
                if (!strncmp(line, "[CRASH]", 7) || !strncmp(line, "[ABORT]", 7) ||
                    !strncmp(line, "[STACKOVERFLOW]", 15)) {
                    size_t l = strcspn(line, "\r");
                    if (l > 200)
                        l = 200;
                    if (used + l + 2 < sizeof lines) {
                        memcpy(lines + used, line, l);
                        used += l;
                        lines[used++] = '\n';
                        lines[used] = 0;
                        shown++;
                    }
                }
                line = next;
            }
        }
        free(buf);
        CloseHandle(f);
    }
    wchar_t wlines[3000];
    MultiByteToWideChar(CP_UTF8, 0, lines, -1, wlines, 3000);
    msg(MB_ICONERROR,
        L"The game did not close normally (exit code 0x%08lX) - it probably crashed.\n\n"
        L"%s%s"
        L"Please send run.err.log from this folder:\n%s\n"
        L"(The next launch moves it into the logs folder.)",
        (unsigned long)code, shown ? wlines : L"", shown ? L"\n" : L"", g_here);
}

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE prev, PWSTR args, int show)
{
    (void)prev;
    (void)show;
    DWORD n = GetModuleFileNameW(NULL, g_here, PATHN);
    if (!n || n >= PATHN)
        return 1;
    wchar_t *slash = wcsrchr(g_here, L'\\');
    if (slash)
        slash[1] = 0;

    wchar_t game[PATHN], eboot[PATHN], sfo[PATHN], exe[PATHN], vfs[PATHN];
    here_path(game, L"..\\civrev-gamefiles");
    _snwprintf_s(eboot, PATHN, _TRUNCATE, L"%s\\EBOOT.elf", game);
    _snwprintf_s(sfo, PATHN, _TRUNCATE, L"%s\\vfs\\PS3_GAME\\PARAM.SFO", game);
    _snwprintf_s(vfs, PATHN, _TRUNCATE, L"%s\\vfs", game);
    here_path(exe, L"build\\civrev.exe");

    if (!exists(eboot)) {
        msg(MB_ICONERROR, L"Decrypted EBOOT not found:\n%s\n\n"
                          L"CivRev.exe must stay in the civrev-port folder, next to civrev-gamefiles.", eboot);
        return 1;
    }
    if (!exists(sfo)) {
        msg(MB_ICONERROR, L"Disc contents not found:\n%s", sfo);
        return 1;
    }
    /* A running civrev.exe can't be replaced by a rebuild, and two copies
     * would share one save folder. */
    if (game_running()) {
        msg(MB_ICONWARNING, L"The game is already running.\nClose it first, then start it again.");
        return 1;
    }
    if (!rebuild_if_needed(exe))
        return 1;

    SetEnvironmentVariableW(L"PS3_VFS_ROOT", vfs);
    /* ps3recomp's live-draw renderer: the default D3D12 backend draws this
     * game upside down with wrong font glyphs. */
    set_default(L"RSX_LIVE_DRAW", L"1");
    /* GPU command ring in 32 KB segments, as libgcm/RPCS3: the renderer
     * starts on a frame while the game still writes it (~+40% FPS in a
     * match). GCM_FIFO_SEGMENT=0 = old whole-ring behaviour. */
    set_default(L"GCM_FIFO_SEGMENT", L"0x8000");
    /* Per-frame log lines cost ~150 us each; PS3_VERBOSE=1 brings them back. */
    set_default(L"PS3_VERBOSE", L"0");
    apply_settings();
    /* Total playtime in the window caption (ps3recomp rsx_null_backend.c),
     * kept in playtime.txt (seconds) next to this launcher. */
    {
        wchar_t pt[PATHN];
        here_path(pt, L"playtime.txt");
        SetEnvironmentVariableW(L"PS3_PLAYTIME_FILE", pt);
    }

    /* Taskbar identity for the game window (ps3recomp rsx_null_backend.c):
     * pinning the running game pins this launcher, with its icon, and the
     * game groups under that pin. */
    {
        wchar_t self[PATHN], v[PATHN + 8];
        GetModuleFileNameW(NULL, self, PATHN);
        SetEnvironmentVariableW(L"PS3_APP_ID", L"CivRevPort.CivilizationRevolution");
        SetEnvironmentVariableW(L"PS3_RELAUNCH_NAME", TITLE);
        _snwprintf_s(v, PATHN + 8, _TRUNCATE, L"\"%s\"", self);
        SetEnvironmentVariableW(L"PS3_RELAUNCH_CMD", v);
        _snwprintf_s(v, PATHN + 8, _TRUNCATE, L"%s,0", self);
        SetEnvironmentVariableW(L"PS3_RELAUNCH_ICON", v);
    }

    rotate_logs();

    wchar_t out_log[PATHN], err_log[PATHN];
    here_path(out_log, L"run.log");
    here_path(err_log, L"run.err.log");
    SECURITY_ATTRIBUTES sa = {sizeof sa, NULL, TRUE};
    HANDLE hout = CreateFileW(out_log, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, &sa,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    HANDLE herr = CreateFileW(err_log, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, &sa,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    HANDLE hin = CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, &sa,
                             OPEN_EXISTING, 0, NULL);
    if (hout == INVALID_HANDLE_VALUE || herr == INVALID_HANDLE_VALUE) {
        msg(MB_ICONERROR, L"Can't create run.log / run.err.log in:\n%s", g_here);
        return 1;
    }

    static wchar_t cmd[PATHN * 4];
    _snwprintf_s(cmd, PATHN * 4, _TRUNCATE, L"\"%s\" \"%s\"%s%s", exe, eboot,
                 (args && *args) ? L" " : L"", args ? args : L"");
    STARTUPINFOW si = {sizeof si};
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdInput = hin;
    si.hStdOutput = hout;
    si.hStdError = herr;
    PROCESS_INFORMATION pi;
    if (!CreateProcessW(exe, cmd, NULL, NULL, TRUE, CREATE_NO_WINDOW, NULL, g_here, &si, &pi)) {
        msg(MB_ICONERROR, L"Could not start:\n%s\n\n(Windows error %lu)", exe, GetLastError());
        return 1;
    }
    CloseHandle(pi.hThread);
    CloseHandle(hout);
    CloseHandle(herr);
    if (hin != INVALID_HANDLE_VALUE)
        CloseHandle(hin);

    /* Give the game window our icon: check every 0.5 s until it exists, then
     * every 5 s (in case the game recreates it). */
    icon_ctx ic = {pi.dwProcessId, NULL, NULL, 0};
    ic.big = (HICON)LoadImageW(inst, MAKEINTRESOURCEW(1), IMAGE_ICON, GetSystemMetrics(SM_CXICON),
                               GetSystemMetrics(SM_CYICON), 0);
    ic.small = (HICON)LoadImageW(inst, MAKEINTRESOURCEW(1), IMAGE_ICON, GetSystemMetrics(SM_CXSMICON),
                                 GetSystemMetrics(SM_CYSMICON), 0);
    for (;;) {
        if (WaitForSingleObject(pi.hProcess, ic.set ? 5000 : 500) != WAIT_TIMEOUT)
            break;
        if (ic.big)
            EnumWindows(icon_cb, (LPARAM)&ic);
    }

    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess);
    if (code != 0)
        report_crash(code, err_log);
    return (int)code;
}
