// https://x.com/i/grok/share/fTR2xcxk4VTtwYUiWzd0NY0sw
// Notepad++ 插件，用于在 Assembly 文件中将中文字符替换为对应的英文字符（如全角逗号替换为半角逗号）
// 支持 .asm 和 .inc 文件，仅在非注释区域进行替换，支持调试消息输出

#include "C:\Users\Administrator\Desktop\notepad-plus-plus-master\PowerEditor\src\MISC\PluginsManager\PluginInterface.h"
#include "C:\Users\Administrator\Desktop\notepad-plus-plus-master\lexilla\include\SciLexer.h"
#include "C:\Users\Administrator\Desktop\notepad-plus-plus-master\scintilla\include\Scintilla.h"
#include <windows.h>
#include <tchar.h>
#include <unordered_map>
#include <string> // 添加 string 头文件以支持 std::string

#define SCLEX_ASM 34
#define SCE_ASM_COMMENT 1

// 插件全局变量
const TCHAR* pluginName = TEXT("AsmCharReplacePlugin");
NppData nppData = {0}; 
bool isEnabled = true; 
bool isDebugMessagesEnabled = false; 
FuncItem funcItem[2] = {0}; 

// 中文字符映射表
struct CharMapping {
    const char* utf8; 
    char replacement; 
    const TCHAR* name; 
};

const CharMapping charMappings[] = {
    { "\xEF\xBC\x8C", ',', TEXT("，") }, // 全角逗号
    { "\xE3\x80\x90", '[', TEXT("【") }, 
    { "\xE3\x80\x91", ']', TEXT("】") }, 
    { "\xEF\xBC\x9A", ':', TEXT("：") }, 
    { "\xEF\xBC\x9B", ';', TEXT("；") }, 
    { "\xE3\x80\x81", '/', TEXT("、") }, 
    { "\xE3\x80\x82", '.', TEXT("。") }, 
    { "\xEF\xBF\xA5", '$', TEXT("￥") }, 
    { "\xE2\x80\x98", '\'', TEXT("‘") }, 
    { "\xE2\x80\x99", '\'', TEXT("’") }, 
    { "\xEF\xBC\x88", '(', TEXT("（") }, 
    { "\xEF\xBC\x89", ')', TEXT("）") }, 
    { "\xE2\x80\x9C", '"', TEXT("“") }, 
    { "\xE2\x80\x9D", '"', TEXT("”") }  
};
const size_t numMappings = sizeof(charMappings) / sizeof(charMappings[0]);

// 文件状态缓存
static bool isCurrentFileAssembly = false; 
static bool isCacheValid = false; 
static TCHAR lastFilePath[MAX_PATH] = { 0 }; 

static std::unordered_map<std::string, CharMapping> charMap;

// ==================== 函数声明（前置声明） ====================
HWND GetCurrentScintilla();
void initCharMap();
bool checkFileExtension(const TCHAR* filePath);
void updateFileAssemblyStatus();
bool isAssemblyLanguage(HWND scintillaHandle);
void handleNotification(SCNotification* notifyCode);

void togglePlugin();
void toggleDebugMessages();
void pluginInit(HANDLE hModule);
void pluginClean();

// ==================== 辅助函数 ====================

HWND GetCurrentScintilla() {
    int which = -1;
    SendMessage(nppData._nppHandle, NPPM_GETCURRENTSCINTILLA, 0, (LPARAM)&which);
    return (which == 0) ? nppData._scintillaMainHandle : nppData._scintillaSecondHandle;
}

void initCharMap() {
    charMap.clear();
    for (size_t i = 0; i < numMappings; ++i) {
        charMap[std::string(charMappings[i].utf8, 3)] = charMappings[i];
    }
}

bool checkFileExtension(const TCHAR* filePath) {
    if (!filePath || !*filePath) return false;
    size_t len = _tcslen(filePath);
    const TCHAR* extensions[] = { TEXT(".asm"), TEXT(".inc") };
    for (const TCHAR* ext : extensions) {
        size_t extLen = _tcslen(ext);
        if (len >= extLen && _tcsicmp(filePath + len - extLen, ext) == 0) {
            return true;
        }
    }
    return false;
}

void updateFileAssemblyStatus() {
    TCHAR filePath[MAX_PATH] = { 0 };
    SendMessage(nppData._nppHandle, NPPM_GETFULLCURRENTPATH, MAX_PATH, (LPARAM)filePath);

    if (_tcscmp(filePath, lastFilePath) == 0 && isCacheValid) 
        return;

    _tcscpy_s(lastFilePath, MAX_PATH, filePath);
    isCurrentFileAssembly = checkFileExtension(filePath);

    if (!isCurrentFileAssembly && filePath[0] == 0) {
        TCHAR fileName[MAX_PATH] = { 0 };
        SendMessage(nppData._nppHandle, NPPM_GETFILENAME, MAX_PATH, (LPARAM)fileName);
        isCurrentFileAssembly = checkFileExtension(fileName);
    }

    isCacheValid = true;

    if (!isCurrentFileAssembly && isDebugMessagesEnabled) {
        MessageBox(nppData._nppHandle, TEXT("Not an Assembly file"), TEXT("Debug"), MB_OK);
    }
}

bool isAssemblyLanguage(HWND scintillaHandle) {
    if (!isCacheValid) {
        updateFileAssemblyStatus();
    }
    if (!isCurrentFileAssembly) {
        if (isDebugMessagesEnabled) {
            MessageBox(nppData._nppHandle, TEXT("Not an Assembly file"), TEXT("Debug"), MB_OK);
        }
        return false;
    }
    int lexer = (int)SendMessage(scintillaHandle, SCI_GETLEXER, 0, 0);
    return (lexer == SCLEX_ASM);
}

// ==================== 菜单功能 ====================

void togglePlugin() {
    isEnabled = !isEnabled;
    if (isDebugMessagesEnabled) {
        MessageBox(nppData._nppHandle, isEnabled ? TEXT("Plugin Enabled") : TEXT("Plugin Disabled"), TEXT("AsmCharReplacePlugin"), MB_OK);
    }
}

void toggleDebugMessages() {
    isDebugMessagesEnabled = !isDebugMessagesEnabled;
    MessageBox(nppData._nppHandle, isDebugMessagesEnabled ? TEXT("Debug Messages Enabled") : TEXT("Debug Messages Disabled"), TEXT("AsmCharReplacePlugin"), MB_OK);
}

// 处理通知
void handleNotification(SCNotification* notifyCode) {
    if (notifyCode->nmhdr.code == NPPN_FILEOPENED || 
        notifyCode->nmhdr.code == NPPN_BUFFERACTIVATED) {
        isCacheValid = false;
        updateFileAssemblyStatus();
        return;
    }

    if (!isEnabled || notifyCode->nmhdr.code != SCN_CHARADDED) 
        return;

    HWND scintillaHandle = GetCurrentScintilla();
    if (!scintillaHandle || !IsWindow(scintillaHandle)) return;

    if (!isAssemblyLanguage(scintillaHandle)) {
        return;
    }

    Sci_Position currentPos = (Sci_Position)SendMessage(scintillaHandle, SCI_GETCURRENTPOS, 0, 0);
    if (currentPos < 3) return;

    if (SendMessage(scintillaHandle, SCI_GETCODEPAGE, 0, 0) != SC_CP_UTF8) {
        if (isDebugMessagesEnabled) {
            MessageBox(nppData._nppHandle, TEXT("Non-UTF8 encoding detected"), TEXT("Debug"), MB_OK);
        }
        return;
    }

    char buffer[4] = {0};
    buffer[0] = (char)SendMessage(scintillaHandle, SCI_GETCHARAT, currentPos - 3, 0);
    buffer[1] = (char)SendMessage(scintillaHandle, SCI_GETCHARAT, currentPos - 2, 0);
    buffer[2] = (char)SendMessage(scintillaHandle, SCI_GETCHARAT, currentPos - 1, 0);

    auto it = charMap.find(std::string(buffer, 3));
    if (it == charMap.end()) return;

    char replaceChar = it->second.replacement;
    const TCHAR* charName = it->second.name;

    Sci_Position start = (currentPos > 50) ? currentPos - 50 : 0;
    SendMessage(scintillaHandle, SCI_COLOURISE, start, currentPos + 10);

    int styleAtEnd = (int)SendMessage(scintillaHandle, SCI_GETSTYLEAT, currentPos - 1, 0);

    if (styleAtEnd != SCE_ASM_COMMENT) {
        if (isDebugMessagesEnabled) {
            TCHAR debugMsg[256];
            wsprintf(debugMsg, TEXT("Replacing %s with %c"), charName, replaceChar);
            MessageBox(nppData._nppHandle, debugMsg, TEXT("AsmCharReplacePlugin"), MB_OK);
        }

        SendMessage(scintillaHandle, SCI_BEGINUNDOACTION, 0, 0);
        SendMessage(scintillaHandle, SCI_SETSEL, currentPos - 3, currentPos);
        SendMessage(scintillaHandle, SCI_CLEAR, 0, 0);
        SendMessage(scintillaHandle, SCI_ADDTEXT, 1, (LPARAM)&replaceChar);
        SendMessage(scintillaHandle, SCI_ENDUNDOACTION, 0, 0);
    }
}

void pluginInit(HANDLE /*hModule*/) {
    initCharMap();

    funcItem[0]._pFunc = togglePlugin;
    lstrcpy(funcItem[0]._itemName, TEXT("Toggle Replace"));

    funcItem[1]._pFunc = toggleDebugMessages;
    lstrcpy(funcItem[1]._itemName, TEXT("Toggle Debug Messages"));
}

void pluginClean() {
    charMap.clear();
    isCacheValid = false;
    lastFilePath[0] = 0;
}

// ==================== 导出函数 ====================

extern "C" __declspec(dllexport) void setInfo(NppData notepadPlusData) {
    nppData = notepadPlusData;
    pluginInit(NULL);
    updateFileAssemblyStatus();
}

extern "C" __declspec(dllexport) const TCHAR* getName() {
    return pluginName;
}

extern "C" __declspec(dllexport) FuncItem* getFuncsArray(int* nbF) {
    *nbF = 2;
    return funcItem;
}

extern "C" __declspec(dllexport) void beNotified(SCNotification* notifyCode) {
    handleNotification(notifyCode);
}

extern "C" __declspec(dllexport) LRESULT messageProc(UINT, WPARAM, LPARAM) {
    return TRUE;
}

extern "C" __declspec(dllexport) BOOL isUnicode() {
    return TRUE;
}