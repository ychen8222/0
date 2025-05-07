// https://x.com/i/grok/share/fTR2xcxk4VTtwYUiWzd0NY0sw
// Notepad++ 插件，用于在 Assembly 文件中将中文字符替换为对应的英文字符（如全角逗号替换为半角逗号）
// 支持 .asm 和 .inc 文件，仅在非注释区域进行替换，支持调试消息输出

#include "C:\Users\Administrator\Desktop\notepad-plus-plus-master\PowerEditor\src\MISC\PluginsManager\PluginInterface.h"
#include "C:\Users\Administrator\Desktop\notepad-plus-plus-master\lexilla\include\SciLexer.h"
#include "C:\Users\Administrator\Desktop\notepad-plus-plus-master\scintilla\include\Scintilla.h"
#include <windows.h>
#include <unordered_map>
#include <string> // 添加 string 头文件以支持 std::string

#define SCI_SETLEXER 4002
#define SCLEX_ASM 34
#define SCE_ASM_DEFAULT 0
#define SCE_ASM_COMMENT 1
#define SCE_ASM_INSTRUCTION 3

// 插件全局变量
const TCHAR* pluginName = TEXT("AsmCharReplacePlugin"); // 插件名称
NppData nppData; // Notepad++ 提供的接口数据（如主句柄和 Scintilla 句柄）
bool isEnabled = true; // 插件开关，控制是否执行字符替换
bool isDebugMessagesEnabled = false; // 调试消息开关，控制是否弹出调试消息框
FuncItem funcItem[2]; // 插件菜单项数组，支持两个功能：切换插件和调试消息

// 中文字符到英文字符的映射表
struct CharMapping {
    const char* utf8; // UTF-8 编码（3字节，用于匹配中文字符）
    char replacement; // 替换的英文字符
    const TCHAR* name; // 字符名称（用于调试输出）
};
const CharMapping charMappings[] = {
    { "\xEF\xBC\x8C", ',', TEXT("，") }, // 全角逗号
    { "\xE3\x80\x90", '[', TEXT("【") }, // 全角左方括号
    { "\xE3\x80\x91", ']', TEXT("】") }, // 全角右方括号
    { "\xEF\xBC\x9A", ':', TEXT("：") }, // 全角冒号
    { "\xEF\xBC\x9B", ';', TEXT("；") }, // 全角分号
    { "\xE3\x80\x81", '/', TEXT("、") }, // 顿号
    { "\xE3\x80\x82", '.', TEXT("。") }  // 全角句号
};
const size_t numMappings = sizeof(charMappings) / sizeof(charMappings[0]);

// 文件状态缓存
static bool isCurrentFileAssembly = false; // 当前文件是否为 Assembly 文件
static bool isCacheValid = false; // 缓存是否有效
static TCHAR lastFilePath[MAX_PATH] = { 0 }; // 缓存最近检查的文件路径

// 全局哈希表，用于加速字符查找
static std::unordered_map<std::string, CharMapping> charMap;

// 函数声明
void togglePlugin(); // 切换插件启用/禁用状态
void toggleDebugMessages(); // 切换调试消息框启用/禁用状态
void initMenu(); // 初始化插件菜单
bool isAssemblyLanguage(HWND scintillaHandle); // 检查当前文件是否为 Assembly 语言
void handleNotification(SCNotification* notifyCode); // 处理 Scintilla 通知（如字符输入）
void pluginInit(HANDLE hModule); // 插件初始化
void pluginClean(); // 插件清理
bool checkFileExtension(const TCHAR* filePath); // 检查文件扩展名是否为 .asm 或 .inc
void updateFileAssemblyStatus(); // 更新文件 Assembly 状态
void initCharMap(); // 初始化字符映射哈希表

// 初始化哈希表，将 charMappings 数组加载到 unordered_map 以加速查找
void initCharMap() {
    for (size_t i = 0; i < numMappings; ++i) {
        charMap[std::string(charMappings[i].utf8)] = charMappings[i]; // 键为 UTF-8 字节序列，值为映射信息
    }
}

// 切换插件启用/禁用状态
void togglePlugin() {
    isEnabled = !isEnabled; // 切换插件状态
    if (isDebugMessagesEnabled) {
        MessageBox(nppData._nppHandle, isEnabled ? TEXT("Plugin Enabled") : TEXT("Plugin Disabled"), TEXT("AsmCharReplacePlugin"), MB_OK);
    }
}

// 切换调试消息框启用/禁用状态
void toggleDebugMessages() {
    isDebugMessagesEnabled = !isDebugMessagesEnabled; // 切换调试消息状态
    MessageBox(nppData._nppHandle, isDebugMessagesEnabled ? TEXT("Debug Messages Enabled") : TEXT("Debug Messages Disabled"), TEXT("AsmCharReplacePlugin"), MB_OK);
}

// 初始化插件菜单，设置两个菜单项：切换替换功能和调试消息
void initMenu() {
    funcItem[0]._pFunc = togglePlugin;
    lstrcpy(funcItem[0]._itemName, TEXT("Toggle Replace"));
    funcItem[0]._init2Check = false;
    funcItem[0]._pShKey = NULL;

    funcItem[1]._pFunc = toggleDebugMessages;
    lstrcpy(funcItem[1]._itemName, TEXT("Toggle Debug Messages"));
    funcItem[1]._init2Check = false;
    funcItem[1]._pShKey = NULL;

    if (isDebugMessagesEnabled) {
        MessageBox(nppData._nppHandle, TEXT("Menu Initialized"), TEXT("AsmCharReplacePlugin"), MB_OK);
    }
}

// 检查文件扩展名是否为 .asm 或 .inc
// 使用 _tcsicmp 进行不区分大小写的比较，避免字符串复制以提高性能
bool checkFileExtension(const TCHAR* filePath) {
    if (!filePath || !*filePath) return false; // 空路径检查
    size_t len = _tcslen(filePath);
    const TCHAR* extensions[] = { TEXT(".asm"), TEXT(".inc") };
    for (const TCHAR* ext : extensions) {
        size_t extLen = _tcslen(ext);
        if (len >= extLen && _tcsicmp(filePath + len - extLen, ext) == 0) {
            return true; // 匹配扩展名
        }
    }
    return false;
}

// 更新当前文件的 Assembly 状态，检查文件扩展名并缓存结果
// 使用文件路径缓存避免重复检查，提高性能
void updateFileAssemblyStatus() {
    TCHAR filePath[MAX_PATH] = { 0 };
    SendMessage(nppData._nppHandle, NPPM_GETFULLCURRENTPATH, MAX_PATH, (LPARAM)filePath);
    if (_tcscmp(filePath, lastFilePath) == 0 && isCacheValid) return; // 路径未变，跳过检查
    _tcscpy_s(lastFilePath, MAX_PATH, filePath); // 更新缓存路径
    isCurrentFileAssembly = checkFileExtension(filePath); // 检查扩展名
    if (!isCurrentFileAssembly && filePath[0] == 0) { // 处理未保存文件
        TCHAR fileName[MAX_PATH] = { 0 };
        SendMessage(nppData._nppHandle, NPPM_GETFILENAME, MAX_PATH, (LPARAM)fileName);
        isCurrentFileAssembly = checkFileExtension(fileName);
    }
    isCacheValid = true; // 标记缓存有效
    if (!isCurrentFileAssembly && isDebugMessagesEnabled) {
        MessageBox(nppData._nppHandle, TEXT("Not an Assembly file"), TEXT("Debug"), MB_OK);
    }
}

// 检查当前文件是否为 Assembly 语言
// 结合缓存和 Scintilla 词法分析器状态，确保准确性
bool isAssemblyLanguage(HWND scintillaHandle) {
    if (!isCacheValid) {
        updateFileAssemblyStatus(); // 缓存无效时更新状态
    }
    if (!isCurrentFileAssembly) {
        if (isDebugMessagesEnabled) {
            MessageBox(nppData._nppHandle, TEXT("Not an Assembly file"), TEXT("Debug"), MB_OK);
        }
        return false;
    }
    int lexer = static_cast<int>(SendMessage(scintillaHandle, SCI_GETLEXER, 0, 0));
    if (lexer != SCLEX_ASM && isDebugMessagesEnabled) {
        MessageBox(nppData._nppHandle, TEXT("Lexer is not SCLEX_ASM"), TEXT("Debug"), MB_OK);
    }
    return (lexer == SCLEX_ASM);
}

// 处理 Scintilla 通知，主要处理字符输入（SCN_CHARADDED）以替换中文字符
// 优化：使用哈希表加速字符查找，仅在必要时调用 SCI_COLOURISE，减少样式检查
void handleNotification(SCNotification* notifyCode) {
    // 处理文件打开或缓冲区切换，更新文件状态
    if (notifyCode->nmhdr.code == NPPN_FILEOPENED || notifyCode->nmhdr.code == NPPN_BUFFERACTIVATED) {
        isCacheValid = false;
        updateFileAssemblyStatus();
        return;
    }

    // 仅处理字符输入事件，且插件启用时
    if (!isEnabled || notifyCode->nmhdr.code != SCN_CHARADDED) return;

    // 获取当前 Scintilla 句柄
    int which = -1;
    SendMessage(nppData._nppHandle, NPPM_GETCURRENTSCINTILLA, 0, (LPARAM)&which);
    if (which != 0 && which != 1) {
        if (isDebugMessagesEnabled) {
            TCHAR debugMsg[256];
            wsprintf(debugMsg, TEXT("Invalid Scintilla index: %d"), which);
            MessageBox(nppData._nppHandle, debugMsg, TEXT("Debug"), MB_OK);
        }
        return;
    }
    HWND scintillaHandle = (which == 0) ? nppData._scintillaMainHandle : nppData._scintillaSecondHandle;
    if (!scintillaHandle || !IsWindow(scintillaHandle)) {
        if (isDebugMessagesEnabled) {
            MessageBox(nppData._nppHandle, TEXT("Invalid Scintilla handle"), TEXT("Debug"), MB_OK);
        }
        return;
    }

    // 获取当前光标位置
    Sci_Position currentPos = static_cast<Sci_Position>(SendMessage(scintillaHandle, SCI_GETCURRENTPOS, 0, 0));

    // 确保文档为 UTF-8 编码
    if (SendMessage(scintillaHandle, SCI_GETCODEPAGE, 0, 0) != SC_CP_UTF8) {
        if (isDebugMessagesEnabled) {
            MessageBox(nppData._nppHandle, TEXT("Non-UTF8 encoding detected"), TEXT("Debug"), MB_OK);
        }
        return;
    }

    // 检查是否足以读取 3 字节的 UTF-8 字符
    if (currentPos < 3) {
        if (isDebugMessagesEnabled) {
            MessageBox(nppData._nppHandle, TEXT("Position too early for 3-byte character"), TEXT("Debug"), MB_OK);
        }
        return;
    }

    // 获取前 3 个字节（可能的中文字符）
    char buffer[4] = { 0 };
    buffer[0] = static_cast<char>(SendMessage(scintillaHandle, SCI_GETCHARAT, currentPos - 3, 0));
    buffer[1] = static_cast<char>(SendMessage(scintillaHandle, SCI_GETCHARAT, currentPos - 2, 0));
    buffer[2] = static_cast<char>(SendMessage(scintillaHandle, SCI_GETCHARAT, currentPos - 1, 0));

    // 调试：输出缓冲区内容
    if (isDebugMessagesEnabled) {
        TCHAR debugMsg[256];
        wsprintf(debugMsg, TEXT("Buffer: %02X %02X %02X, Pos: %d"),
            (unsigned char)buffer[0], (unsigned char)buffer[1], (unsigned char)buffer[2], (int)currentPos);
        MessageBox(nppData._nppHandle, debugMsg, TEXT("Debug"), MB_OK);
    }

    // 使用哈希表查找匹配的字符
    char replaceChar = 0;
    const TCHAR* charName = nullptr;
    auto it = charMap.find(std::string(buffer, 3));
    if (it != charMap.end()) {
        replaceChar = it->second.replacement;
        charName = it->second.name;
    }

    // 如果找到匹配的字符，进行替换
    if (replaceChar) {
        if (!isAssemblyLanguage(scintillaHandle)) {
            if (isDebugMessagesEnabled) {
                MessageBox(nppData._nppHandle, TEXT("Not an Assembly file"), TEXT("Debug"), MB_OK);
            }
            return;
        }

        // 仅在替换时重新着色，减少性能开销
        SendMessage(scintillaHandle, SCI_COLOURISE, 0, -1);

        // 检查末尾字节的样式，判断是否为注释
        int styleAtEnd = static_cast<int>(SendMessage(scintillaHandle, SCI_GETSTYLEAT, currentPos - 1, 0));

        // 调试：输出样式信息
        if (isDebugMessagesEnabled) {
            TCHAR debugMsg[256];
            wsprintf(debugMsg, TEXT("Style: End=%d, IsComment=%d"), styleAtEnd, styleAtEnd == SCE_ASM_COMMENT);
            MessageBox(nppData._nppHandle, debugMsg, TEXT("Debug"), MB_OK);
        }

        // 非注释区域执行替换
        if (styleAtEnd != SCE_ASM_COMMENT) {
            if (isDebugMessagesEnabled) {
                TCHAR debugMsg[256];
                wsprintf(debugMsg, TEXT("Replacing %s with %c"), charName, replaceChar);
                MessageBox(nppData._nppHandle, debugMsg, TEXT("AsmCharReplacePlugin"), MB_OK);
            }

            // 执行替换操作，包裹在撤销动作中
            SendMessage(scintillaHandle, SCI_BEGINUNDOACTION, 0, 0);
            SendMessage(scintillaHandle, SCI_SETSEL, currentPos - 3, currentPos);
            SendMessage(scintillaHandle, SCI_CLEAR, 0, 0);
            SendMessage(scintillaHandle, SCI_ADDTEXT, 1, (LPARAM)&replaceChar);
            SendMessage(scintillaHandle, SCI_ENDUNDOACTION, 0, 0);

            if (isDebugMessagesEnabled) {
                MessageBox(nppData._nppHandle, TEXT("Replacement attempted"), TEXT("Debug"), MB_OK);
            }
        }
        else {
            if (isDebugMessagesEnabled) {
                MessageBox(nppData._nppHandle, TEXT("In comment, skipping replacement"), TEXT("Debug"), MB_OK);
            }
        }
    }
}

// 插件初始化，设置菜单并初始化哈希表
void pluginInit(HANDLE /*hModule*/) {
    initMenu(); // 初始化菜单
    initCharMap(); // 初始化字符映射哈希表
    if (isDebugMessagesEnabled) {
        MessageBox(nppData._nppHandle, TEXT("pluginInit Called"), TEXT("AsmCharReplacePlugin"), MB_OK);
    }
}

// 插件清理函数，目前为空
void pluginClean() {
    // 可选：清理资源
}

// 导出函数：设置 Notepad++ 数据并初始化插件
extern "C" __declspec(dllexport) void setInfo(NppData notpadPlusData) {
    nppData = notpadPlusData; // 保存 Notepad++ 数据
    if (isDebugMessagesEnabled) {
        MessageBox(nppData._nppHandle, TEXT("setInfo Called"), TEXT("AsmCharReplacePlugin"), MB_OK);
    }

    // 验证句柄有效性
    if (!nppData._nppHandle || !IsWindow(nppData._nppHandle)) {
        if (isDebugMessagesEnabled) {
            MessageBox(nppData._nppHandle, TEXT("Invalid Notepad++ handle during initialization"), TEXT("AsmCharReplacePlugin"), MB_OK | MB_ICONERROR);
        }
        return;
    }
    if (!nppData._scintillaMainHandle || !IsWindow(nppData._scintillaMainHandle) ||
        !nppData._scintillaSecondHandle || !IsWindow(nppData._scintillaSecondHandle)) {
        if (isDebugMessagesEnabled) {
            MessageBox(nppData._nppHandle, TEXT("Invalid Scintilla handles during initialization"), TEXT("AsmCharReplacePlugin"), MB_OK | MB_ICONERROR);
        }
        return;
    }

    pluginInit(NULL); // 初始化插件
    updateFileAssemblyStatus(); // 初始化文件状态
}

// 导出函数：返回插件名称
extern "C" __declspec(dllexport) const TCHAR* getName() {
    if (isDebugMessagesEnabled) {
        MessageBox(nppData._nppHandle, TEXT("getName Called"), TEXT("AsmCharReplacePlugin"), MB_OK);
    }
    return pluginName;
}

// 导出函数：返回插件功能数组
extern "C" __declspec(dllexport) FuncItem* getFuncsArray(int* nbF) {
    *nbF = 2; // 两个菜单项
    if (isDebugMessagesEnabled) {
        MessageBox(nppData._nppHandle, TEXT("getFuncsArray Called"), TEXT("AsmCharReplacePlugin"), MB_OK);
    }
    return funcItem;
}

// 导出函数：处理 Scintilla 通知
extern "C" __declspec(dllexport) void beNotified(SCNotification* notifyCode) {
    handleNotification(notifyCode);
}

// 导出函数：处理消息（当前未使用）
extern "C" __declspec(dllexport) LRESULT messageProc(UINT /*Message*/, WPARAM /*wParam*/, LPARAM /*lParam*/) {
    return TRUE;
}

// 导出函数：确认插件支持 Unicode
extern "C" __declspec(dllexport) BOOL isUnicode() {
    if (isDebugMessagesEnabled) {
        MessageBox(nppData._nppHandle, TEXT("isUnicode Called"), TEXT("AsmCharReplacePlugin"), MB_OK);
    }
    return TRUE;
}
