/* Tests CivRev.ini -> environment in the launcher (built by build_test.ps1).
 * Includes the real CivRev.c; CIVREV_LAUNCHER_TEST leaves out its entry point. */
#define CIVREV_LAUNCHER_TEST 1
#include "../CivRev.c"
#include <stdio.h>

static int g_fail;

static void write_ini(const wchar_t *path, const char *text)
{
    FILE *f = _wfopen(path, L"wb");
    fputs(text, f);
    fclose(f);
}

static void check_env(const char *test, const wchar_t *name, const wchar_t *want /* NULL = unset */)
{
    wchar_t v[64];
    const DWORD n = GetEnvironmentVariableW(name, v, 64);
    const int ok = want ? (n > 0 && !wcscmp(v, want)) : (n == 0);
    printf("%s %s: %ls = %ls (want %ls)\n", ok ? "PASS" : "FAIL", test, name,
           n ? v : L"<unset>", want ? want : L"<unset>");
    if (!ok) g_fail = 1;
}

static void reset_env(void)
{
    SetEnvironmentVariableW(L"LD_BLACK_CAPTURES", NULL);
    SetEnvironmentVariableW(L"PAD_RUMBLE", NULL);
}

int main(void)
{
    wchar_t ini[MAX_PATH];
    GetTempPathW(MAX_PATH, ini);
    wcscat_s(ini, MAX_PATH, L"civrev_settings_test.ini");

    reset_env();
    write_ini(ini, "[game]\r\nvibration=on\r\n");
    apply_settings_from(ini);
    check_env("no [debug] key -> auto capture off", L"LD_BLACK_CAPTURES", L"0");
    check_env("vibration=on", L"PAD_RUMBLE", L"1");

    reset_env();
    write_ini(ini, "[game]\r\nvibration=off\r\n[debug]\r\nauto_capture=on\r\n");
    apply_settings_from(ini);
    check_env("auto_capture=on -> runtime default", L"LD_BLACK_CAPTURES", NULL);
    check_env("vibration=off", L"PAD_RUMBLE", L"0");

    reset_env();
    write_ini(ini, "[debug]\r\nauto_capture=off\r\n");
    apply_settings_from(ini);
    check_env("auto_capture=off", L"LD_BLACK_CAPTURES", L"0");

    reset_env();
    SetEnvironmentVariableW(L"LD_BLACK_CAPTURES", L"5");
    write_ini(ini, "[game]\r\nvibration=on\r\n");
    apply_settings_from(ini);
    check_env("value already set in env is kept", L"LD_BLACK_CAPTURES", L"5");

    DeleteFileW(ini);
    printf(g_fail ? "SOME TESTS FAILED\n" : "ALL PASS\n");
    return g_fail;
}
