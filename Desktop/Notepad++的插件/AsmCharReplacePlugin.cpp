//https://x.com/i/grok/share/fTR2xcxk4VTtwYUiWzd0NY0sw
#include "C:\Users\Administrator\Desktop\notepad-plus-plus-master\PowerEditor\src\MISC\PluginsManager\PluginInterface.h"
#include "C:\Users\Administrator\Desktop\notepad-plus-plus-master\lexilla\include\SciLexer.h"
#include "C:\Users\Administrator\Desktop\notepad-plus-plus-master\scintilla\include\Scintilla.h"
#include <windows.h>

#define SCI_SETLEXER 4002
#define SCLEX_ASM 34
#define SCE_ASM_DEFAULT 0
#define SCE_ASM_COMMENT 1
#define SCE_ASM_INSTRUCTION 3

const TCHAR* pluginName = TEXT("AsmCharReplacePlugin");// 插件名称
NppData nppData;// Notepad++ 数据
bool isEnabled = true;// 插件开关
bool isDebugMessagesEnabled = false;// 调试消息框开关
FuncItem funcItem[2];// 插件功能列表

// 切换插件功能的函数
void togglePlugin()
{
    isEnabled = !isEnabled;
    if (isDebugMessagesEnabled) {
        MessageBox(nppData._nppHandle, isEnabled ? TEXT("Plugin Enabled") : TEXT("Plugin Disabled"), TEXT("AsmCharReplacePlugin"), MB_OK);
    }
}

// 切换调试消息框的函数
void toggleDebugMessages()
{
    isDebugMessagesEnabled = !isDebugMessagesEnabled;
    MessageBox(nppData._nppHandle, isDebugMessagesEnabled ? TEXT("Debug Messages Enabled") : TEXT("Debug Messages Disabled"), TEXT("AsmCharReplacePlugin"), MB_OK);
}

// 初始化功能列表
void initMenu()
{
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

// 检查当前文件是否为 Assembly 语言
bool isAssemblyLanguage(HWND scintillaHandle)
{
    int lexer = static_cast<int>(SendMessage(scintillaHandle, SCI_GETLEXER, 0, 0));
    if (lexer != SCLEX_ASM)
    {
        SendMessage(scintillaHandle, SCI_SETLEXER, SCLEX_ASM, 0);
        SendMessage(scintillaHandle, SCI_STYLESETFORE, SCE_ASM_COMMENT, RGB(0, 128, 0));
        SendMessage(scintillaHandle, SCI_COLOURISE, 0, -1);
        if (isDebugMessagesEnabled) {
            MessageBox(nppData._nppHandle, TEXT("Lexer set to SCLEX_ASM"), TEXT("Debug"), MB_OK);
        }
    }
    return (lexer == SCLEX_ASM);
}


// 处理 Scintilla 通知
void handleNotification(SCNotification* notifyCode)
{
    if (!isEnabled || notifyCode->nmhdr.code != SCN_CHARADDED) return;

    HWND scintillaHandle = nppData._scintillaMainHandle;
    if (!scintillaHandle)
    {
        scintillaHandle = nppData._scintillaSecondHandle;
        if (!scintillaHandle)
        {
            if (isDebugMessagesEnabled) {
                MessageBox(nppData._nppHandle, TEXT("Invalid Scintilla handle"), TEXT("Debug"), MB_OK);
            }
            return;
        }
    }


    SendMessage(scintillaHandle, SCI_COLOURISE, 0, -1);// 强制重新着色以确保样式更新

    // 获取当前位置
    Sci_Position currentPos = static_cast<Sci_Position>(SendMessage(scintillaHandle, SCI_GETCURRENTPOS, 0, 0));
    if (currentPos < 3)
    {
        if (isDebugMessagesEnabled) {
            MessageBox(nppData._nppHandle, TEXT("Position too early for 3-byte character"), TEXT("Debug"), MB_OK);
        }
        return;
    }

    // 获取前3个字节（足以存储中文字符的UTF-8编码）
    char buffer[4] = { 0 };
    buffer[0] = static_cast<char>(SendMessage(scintillaHandle, SCI_GETCHARAT, currentPos - 3, 0));
    buffer[1] = static_cast<char>(SendMessage(scintillaHandle, SCI_GETCHARAT, currentPos - 2, 0));
    buffer[2] = static_cast<char>(SendMessage(scintillaHandle, SCI_GETCHARAT, currentPos - 1, 0));

    // 调试：显示buffer内容
    if (isDebugMessagesEnabled) {
        TCHAR debugMsg[256];
        wsprintf(debugMsg, TEXT("Buffer: %02X %02X %02X, Pos: %d"),
            (unsigned char)buffer[0], (unsigned char)buffer[1], (unsigned char)buffer[2], (int)currentPos);
        MessageBox(nppData._nppHandle, debugMsg, TEXT("Debug"), MB_OK);
    }

    // 检查中文字符
    bool isComma = (buffer[0] == (char)0xEF && buffer[1] == (char)0xBC && buffer[2] == (char)0x8C); // ，
    bool isSemicolon = (buffer[0] == (char)0xEF && buffer[1] == (char)0xBC && buffer[2] == (char)0x9B); // ；
    bool isPeriod = (buffer[0] == (char)0xE3 && buffer[1] == (char)0x80 && buffer[2] == (char)0x82); // 。

    char replaceChar = 0;
    const TCHAR* charName = nullptr;

    if (isComma)
    {
        replaceChar = ',';
        charName = TEXT("，");
    }
    else if (isSemicolon)
    {
        replaceChar = ';';
        charName = TEXT("；");
    }
    else if (isPeriod)
    {
        replaceChar = '.';
        charName = TEXT("。");
    }

    if (replaceChar)
    {
        if (!isAssemblyLanguage(scintillaHandle))
        {
            if (isDebugMessagesEnabled) {
                MessageBox(nppData._nppHandle, TEXT("Not an Assembly file"), TEXT("Debug"), MB_OK);
            }
            return;
        }

        // 检查多个位置的样式，确保准确判断注释
        int styleAtStart = static_cast<int>(SendMessage(scintillaHandle, SCI_GETSTYLEAT, currentPos - 3, 0));
        int styleAtMiddle = static_cast<int>(SendMessage(scintillaHandle, SCI_GETSTYLEAT, currentPos - 2, 0));
        int styleAtEnd = static_cast<int>(SendMessage(scintillaHandle, SCI_GETSTYLEAT, currentPos - 1, 0));

        if (isDebugMessagesEnabled) {
            TCHAR debugMsg[256];
            wsprintf(debugMsg, TEXT("Styles: Start=%d, Middle=%d, End=%d, IsComment=%d"),
                styleAtStart, styleAtMiddle, styleAtEnd, styleAtStart == SCE_ASM_COMMENT || styleAtMiddle == SCE_ASM_COMMENT || styleAtEnd == SCE_ASM_COMMENT);
            MessageBox(nppData._nppHandle, debugMsg, TEXT("Debug"), MB_OK);
        }

        if (styleAtStart != SCE_ASM_COMMENT && styleAtMiddle != SCE_ASM_COMMENT && styleAtEnd != SCE_ASM_COMMENT)
        {
            if (isDebugMessagesEnabled) {
                TCHAR debugMsg[256];
                wsprintf(debugMsg, TEXT("Replacing %s with %c"), charName, replaceChar);
                MessageBox(nppData._nppHandle, debugMsg, TEXT("AsmCharReplacePlugin"), MB_OK);
            }

            // 删除中文字符（UTF-8编码占3字节）
            SendMessage(scintillaHandle, SCI_BEGINUNDOACTION, 0, 0);
            SendMessage(scintillaHandle, SCI_SETSEL, currentPos - 3, currentPos);
            SendMessage(scintillaHandle, SCI_CLEAR, 0, 0);
            SendMessage(scintillaHandle, SCI_ADDTEXT, 1, (LPARAM)&replaceChar);
            SendMessage(scintillaHandle, SCI_ENDUNDOACTION, 0, 0);

            if (isDebugMessagesEnabled) {
                MessageBox(nppData._nppHandle, TEXT("Replacement attempted"), TEXT("Debug"), MB_OK);
            }
        }
        else
        {
            if (isDebugMessagesEnabled) {
                MessageBox(nppData._nppHandle, TEXT("In comment, skipping replacement"), TEXT("Debug"), MB_OK);
            }
        }
    }
}

// 插件初始化
void pluginInit(HANDLE /*hModule*/)
{
    initMenu();
    if (isDebugMessagesEnabled) {
        MessageBox(nppData._nppHandle, TEXT("pluginInit Called"), TEXT("AsmCharReplacePlugin"), MB_OK);
    }
}

// 插件清理
void pluginClean()
{
    // 可选：清理资源
}

// 导出函数
extern "C" __declspec(dllexport) void setInfo(NppData notpadPlusData)
{
    nppData = notpadPlusData;
    if (isDebugMessagesEnabled) {
        MessageBox(nppData._nppHandle, TEXT("setInfo Called"), TEXT("AsmCharReplacePlugin"), MB_OK);
    }
    pluginInit(NULL);
}

extern "C" __declspec(dllexport) const TCHAR* getName()
{
    if (isDebugMessagesEnabled) {
        MessageBox(nppData._nppHandle, TEXT("getName Called"), TEXT("AsmCharReplacePlugin"), MB_OK);
    }
    return pluginName;
}

extern "C" __declspec(dllexport) FuncItem* getFuncsArray(int* nbF)
{
    *nbF = 2;
    if (isDebugMessagesEnabled) {
        MessageBox(nppData._nppHandle, TEXT("getFuncsArray Called"), TEXT("AsmCharReplacePlugin"), MB_OK);
    }
    return funcItem;
}

extern "C" __declspec(dllexport) void beNotified(SCNotification* notifyCode)
{
    handleNotification(notifyCode);
}

extern "C" __declspec(dllexport) LRESULT messageProc(UINT /*Message*/, WPARAM /*wParam*/, LPARAM /*lParam*/)
{
    return TRUE;
}

extern "C" __declspec(dllexport) BOOL isUnicode()
{
    if (isDebugMessagesEnabled) {
        MessageBox(nppData._nppHandle, TEXT("isUnicode Called"), TEXT("AsmCharReplacePlugin"), MB_OK);
    }
    return TRUE;
}