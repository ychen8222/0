;由于UEFI过于复杂横跨多个领域，因此仅获取必要的数据，剩下的需要时再补充
;UEFI就像宏内核，所有的代码都处于同一个地址空间，函数调用不通过int中断或syscall系统调用指令实现，而是使用根据系统表使用call调用指令实现
;不要纠结于代码质量，因为UEFI仅在启动时使用完即弃
;rel等于rip寄存器，nasm不允许rip + 这种写法
;虽然开启了内存分页，但UEFI已将物理地址跟虚拟地址地一一对应，且至少有32MB物理内存，因为低于32MB则不会启动
;UEFI必定支持FAT12，FAT16，FAT32文件系统的读取，有些则支持NTFS的读取，如果你有其他的文件系统则需要自己实现


;文档链接
;https://forum.nasm.us/index.php?topic=2786.0
;https://masm32.com/board/index.php?topic=7942.0
;https://learn.microsoft.com/zh-cn/windows/win32/debug/pe-format
;https://www.aldeid.com/wiki/PE-Portable-executable
;https://www.cnblogs.com/zpchcbd/p/14674298.html
;https://wiki.osdev.org/Uefi.inc



页大小 equ 4096
扇区大小 equ 512


;org 0;不指定起始地址，因为UEFi会将本文件复制到内存任意位置，寻址时加上RiP即可解决此问题
可移植可执行起始:
;MS-DOS 2.0 兼容 EXE 格式
db 'MZ';标识，取自微软开发人员Mark Zbikowski的姓名缩写
times 29 dw 0;不需要此处的DOS数据
dd 80h-40h;PE格式起始字节地址，改为0x40，去掉“times 32 dw 0”。它将跳过该部分并直接转到文件偏移 0x40 处的 PE 签名，而不是 (0x40 + (32*sizeof dw))
;times 32 dw 0;可填写等量多文本

;PE格式起始
E_lfanew db 'PE',0,0;MS-DOS 存根之后，在偏移量 0x3c 处指定的文件偏移处，是一个 4 字节签名，该签名将该文件标识为 PE 格式映像文件。 此签名为“PE\0\0”（字母“P”和“E”后跟两个 null 字节）
;COFF 文件标头（对象和映像）
;在对象文件的开头，或紧接在映像文件签名之后，是以下格式的标准 COFF 文件头。 请注意，Windows 加载器将部分数限制为 96
dw 8664h;标识目标计算机类型，AMD64架构
NumberOfSections dw 节表个数;部分数目。 这指示部分表的大小，该表紧跟在标头之后，两个部分(.text, .data)
dd 0;自 1970 年 1 月 1 日 00:00 起的秒数的低 32 位（C 运行时 time_t 值），指示文件的创建时间
dd 0;COFF 符号表的文件偏移量；如果没有 COFF 符号表，则为零。 映像的此值应为零，因为 COFF 调试信息已被弃用
dd 0;符号表中的项数。 此数据可用于查找紧跟在符号表后面的字符串表。 映像的此值应为零，因为 COFF 调试信息已被弃用
dw 可选标头结束 - 可选标头起始;可选标头的大小，它是可执行文件所必需的，但对象文件不需要它。 对于对象文件，此值应为零
dw 1000h + 2h;指示文件属性的标志，是映像文件是系统文件，而不是用户程序 + 纯映像， 这表示映像文件有效并且可以运行。 如果未设置此标志，则表示有链接器错误

可选标头起始:;实际上不是可选的
dw 20bh;PE32+ 映像允许使用 64 位地址空间，同时会将映像大小限制为 2 GB
db 0;链接器主版本号
db 0;链接器次要版本号
dd 代码填充结束 - 代码起始;代码（文本）段的大小，或者如果有多个部分，则是所有代码段之和
dd 数据填充结束 - 数据起始;初始化数据部分的大小，或者如果有多个数据部分，则是所有此类部分之和
dd 0;未初始化数据部分 (BSS) 的大小，或者如果有多个 BSS 部分，则是所有此类部分的和
dd 代码起始;页大小;可执行文件加载到内存中时相对于映像基址的入口点地址。 对于程序映像，这是起始地址。 对于设备驱动程序，这是初始化函数的地址。 入口点对于 DLL 是可选的。 不存在入口点时，此字段必须为零
dd 代码起始;页大小;加载到内存中后相对于代码开头部分映像基址的地址

;可选标头 Windows 特定字段（仅限映像）
;这对于 UEFI 应用程序也是必需的。相信我，这一发现经过了大量的调试。
dq 可移植可执行起始;可移植可执行起始;映像加载到内存中后第一个字节的首选地址；必须是 64 K 的倍数。DLL 的默认值为 0x10000000。 Windows CE EXE 的默认值为 0x00010000。 Windows NT、Windows 2000、Windows XP、Windows 95、Windows 98 和 Windows Me 的默认值为 0x0040000
SectionAlignment dd 页大小;各部分加载到内存中时的对齐值（以字节为单位）。 它必须大于或等于 FileAlignment。 默认值为体系结构的页面大小
FileAlignment dd 扇区大小;用于使映像文件中各部分的原始数据一致的对齐系数（以字节为单位）。 该值应为 2 的幂次方，介于 512 和 64K 之间（含）。 默认值为 512。 如果 SectionAlignment 小于体系结构的页面大小，则 FileAlignment 必须与 SectionAlignment 匹配
dw 0;所需操作系统的主版本号
dw 0;所需操作系统的次要版本号
dw 0;映像的主版本号
dw 0;映像的次要版本号
dw 0;子系统的主版本号
dw 0;子系统的次要版本号
dd 0;保留，必须为零
dd 页大小 * 节表个数 + 可移植可执行填充结束 - 可移植可执行起始;映像加载到内存中时的映像大小（以字节为单位），包括所有标头。 它必须是 SectionAlignment 的倍数
dd 可移植可执行大小 ;MS DOS 存根、PE 标头和节标头的组合大小，其向上舍入到 FileAlignment 的倍数
dd 0;映像文件的校验和。 用于计算校验和的算法已合并到 IMAGHELP.DLL 中。 加载时会检查以下内容是否有效：所有驱动程序、启动时加载的任何 DLL 以及加载到关键 Windows 进程中的任何 DLL
dw 10;运行此映像所需的子系统，可扩展固件接口 (EFI) 应用程序
dw 0;DLL 特征，不是DLL文件，因此可以为零
dq 页大小;要保留的栈的大小。 仅提交 SizeOfStackCommit；其余部分一次提供一页，直到达到保留大小
SizeOfStackCommit dq 页大小;要立即提交的栈大小
dq 页大小;要保留的本地堆空间的大小。 仅提交 SizeOfHeapCommit；其余部分一次提供一页，直到达到保留大小
SizeOfHeapCommit dq 0x0 ;要立即提交的本地堆空间大小
dd 0;保留，必须为零
dd 0;可选标头剩余部分中数据目录项的数目。 每项都描述位置和大小
可选标头结束:

;节表（节标头）
;https://www.cnblogs.com/zpchcbd/p/14674298.html
所有节表起始:
dq `code`;8 字节的 Null 填充 UTF-8 编码字符串。 如果字符串长度正好为 8 个字符，则无终止 null 字符。 对于较长的名称，此字段包含一个斜杠 (/)，后跟十进制数的 ASCII 表示形式，该十进制数是字符串表中的偏移量。 可执行映像不使用字符串表，也不支持长度超过 8 个字符的节名称。 如果向可执行文件发送对象文件中的长名称，则这些长名称将被截断
dd 代码大小;加载到内存中时节的总大小。 如果此值大于 SizeOfRawData，则节中会用零填充。 此字段仅对可执行映像有效，应针对对象文件设置为零
dd 代码起始 - 可移植可执行起始;对于可执行映像，是指当节加载到内存中时，该节相对于映像基址的第一个字节的地址。 对于对象文件，此字段是应用重定位前第一个字节的地址；为简单起见，编译器应将此字段设置为零。 否则，它是重定位期间从偏移量中减去的任意值
SizeOfRawData.1 dd 代码填充结束 - 代码起始;节（对于对象文件）的大小或磁盘上已初始化的数据的大小（对于映像文件）。 对于可执行映像，这必须是可选标头中的 FileAlignment 的倍数。 如果此值小于 VirtualSize，则节的其余部分用零填充。 由于 SizeOfRawData 字段被舍入，但 VirtualSize 字段未被舍入，因此 SizeOfRawData 也可能大于 VirtualSize。 当节仅包含未初始化的数据时，此字段应为零
dd 代码起始 -可移植可执行起始 ;指向 COFF 文件中节的第一页的文件指针。 对于可执行映像，这必须是可选标头中的 FileAlignment 的倍数。 对于对象文件，该值应在 4 字节边界上对齐，以获取最佳性能。 当节仅包含未初始化的数据时，此字段应为零
dd 0;指向节的重定位项的开头的文件指针。 对于可执行映像或没有重定位的情况，这项设置为零
dd 0;指向节的行号项开头的文件指针。 如果没有 COFF 行号，则此字段设置为零。 映像的此值应为零，因为 COFF 调试信息已被弃用
dw 0;节的重定位项数。 对于可执行映像，此字段设置为零
dw 0;节的行号项数。 映像的此值应为零，因为 COFF 调试信息已被弃用
dd 20h + 20000000h + 40000000h;描述节特性的标志。该节包含可执行代码，可以读取此节
单个节表结束:

dq `data`;8 字节的 Null 填充 UTF-8 编码字符串。 如果字符串长度正好为 8 个字符，则无终止 null 字符。 对于较长的名称，此字段包含一个斜杠 (/)，后跟十进制数的 ASCII 表示形式，该十进制数是字符串表中的偏移量。 可执行映像不使用字符串表，也不支持长度超过 8 个字符的节名称。 如果向可执行文件发送对象文件中的长名称，则这些长名称将被截断
dd 数据大小;加载到内存中时节的总大小。 如果此值大于 SizeOfRawData，则节中会用零填充。 此字段仅对可执行映像有效，应针对对象文件设置为零
dd 数据起始 - 可移植可执行起始;对于可执行映像，是指当节加载到内存中时，该节相对于映像基址的第一个字节的地址。 对于对象文件，此字段是应用重定位前第一个字节的地址；为简单起见，编译器应将此字段设置为零。 否则，它是重定位期间从偏移量中减去的任意值
SizeOfRawData.2 dd 数据填充结束 - 数据起始;节（对于对象文件）的大小或磁盘上已初始化的数据的大小（对于映像文件）。 对于可执行映像，这必须是可选标头中的 FileAlignment 的倍数。 如果此值小于 VirtualSize，则节的其余部分用零填充。 由于 SizeOfRawData 字段被舍入，但 VirtualSize 字段未被舍入，因此 SizeOfRawData 也可能大于 VirtualSize。 当节仅包含未初始化的数据时，此字段应为零
dd 数据起始 - 可移植可执行起始;指向 COFF 文件中节的第一页的文件指针。 对于可执行映像，这必须是可选标头中的 FileAlignment 的倍数。 对于对象文件，该值应在 4 字节边界上对齐，以获取最佳性能。 当节仅包含未初始化的数据时，此字段应为零
dd 0;指向节的重定位项的开头的文件指针。 对于可执行映像或没有重定位的情况，这项设置为零
dd 0;指向节的行号项开头的文件指针。 如果没有 COFF 行号，则此字段设置为零。 映像的此值应为零，因为 COFF 调试信息已被弃用
dw 0;节的重定位项数。 对于可执行映像，此字段设置为零
dw 0;节的行号项数。 映像的此值应为零，因为 COFF 调试信息已被弃用
dd 40h + 40000000h + 80000000h;描述节特性的标志。可以读取此节，可以写入到此节中
所有节表结束:
节表个数 equ (所有节表结束 - 所有节表起始) / (单个节表结束 - 所有节表起始)
可移植可执行结束:
可移植可执行大小 equ 可移植可执行结束 - 可移植可执行起始
;times 扇区大小 - 可移植可执行大小 db 0;对齐
可移植可执行填充结束:


;https://uefi.org/specs/UEFI/2.10/02_Overview.html#x64-platforms
;调用约定
;RCX第一个参数，RDX第二个参数，R8第三个参数，R9第四个参数
;最后一个参数被最先压入栈，RSP - 24，RSP + 0第五个参数，RSP + 8第六个参数，RSP + 16第七个参数，RSP + 24第八个参数
;寄存器Rax，Rcx Rdx R8，R9，R10，R11和XMM0到XMM5是易失性寄存器因此在函数调用时会被修改
;寄存器RBX，RBP，RDI，RSI，R12，R13，R14，R15和XMM6到XMM15被视为非易失性寄存器必须由使用它们的函数进行保存和恢复
;函数指针是指向相应函数标签的指针不需要特殊处理
;调用UEFI函数前必须以16byte字节对齐栈，不对齐就黑屏
;固定为 64 位的返回值在 Rax 寄存器中返回。如果返回值超出 64 位，则调用者必须分配并传递一个指针作为返回值的第一个参数 Rcx。随后的参数将向右移动一个参数，因此例如参数一将在 Rdx 中传递。要返回的用户定义类型长度必须是 1、2、4、8、16、32 或 64 位。



;https://uefi.org/specs/UEFI/2.10/04_EFI_System_Table.html#id4
;typedef struct {
标识 equ 0
版本 equ 标识 + 8
标头大小 equ 版本 + 4
循环冗余校验_32 equ 标头大小 +4
EFI表头_保留 equ 循环冗余校验_32 + 4
; } EFI_TABLE_HEADER;
EFI表头大小 equ EFI表头_保留 + 4


;EFI系统表包含指向运行时和启动服务表的指针
;所有的表都在这里，不要去其他目录下寻找https://uefi.org/specs/UEFI/2.10/04_EFI_System_Table.html#efi-system-table-1
;https://blog.csdn.net/sevensevensevenday/article/details/71158858
;typedef struct {
;  EFI_TABLE_HEADER                 Hdr;
固件供应商 equ EFI表头大小 + 0;  CHAR16                           *FirmwareVendor;
固件版本 equ 固件供应商 + 8;  UINT32                           FirmwareRevision;
控制台输入句柄 equ 固件版本 + 8;  EFI_HANDLE                       ConsoleInHandle;
简单文本输入协议 equ 控制台输入句柄 + 8;  EFI_SIMPLE_TEXT_INPUT_PROTOCOL   *ConIn;
控制台输出句柄 equ 简单文本输入协议 + 8;  EFI_HANDLE                       ConsoleOutHandle;
简单文本输出协议 equ 控制台输出句柄 + 8;  EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL  *ConOut;
标准错误句柄 equ 简单文本输出协议 + 8;  EFI_HANDLE                       StandardErrorHandle;
标准错误输出 equ 标准错误句柄 + 8;  EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL  *StdErr;
运行时服务表指针 equ 标准错误输出 + 8;  EFI_RUNTIME_SERVICES             *RuntimeServices;
引导服务表指针 equ 运行时服务表指针 + 8;  EFI_BOOT_SERVICES                *BootServices;
配置表项数 equ 引导服务表指针 + 8;  UINTN                            NumberOfTableEntries;
配置表指针 equ 配置表项数 + 8;  EFI_CONFIGURATION_TABLE          *ConfigurationTable;
;} EFI_SYSTEM_TABLE;


;https://uefi.org/specs/UEFI/2.10/12_Protocols_Console_Support.html#efi-simple-text-output-protocol
;typedef struct _EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL {
重置文本输出设备硬件 equ 0; EFI_TEXT_RESET                           Reset;
输出字符串 equ 重置文本输出设备硬件 + 8; EFI_TEXT_STRING                          OutputString;
测试目标设备 equ 输出字符串 + 8; EFI_TEXT_TEST_STRING                     TestString;
查询支持的文本模式 equ 测试目标设备 + 8; EFI_TEXT_QUERY_MODE                      QueryMode;
设置支持的文本模式 equ 查询支持的文本模式 + 8; EFI_TEXT_SET_MODE                        SetMode;
设置字符属性 equ 设置支持的文本模式 + 8; EFI_TEXT_SET_ATTRIBUTE                   SetAttribute;
清空屏幕 equ 设置字符属性 + 8; EFI_TEXT_CLEAR_SCREEN                    ClearScreen;
设置光标位置 equ 清空屏幕 + 8; EFI_TEXT_SET_CURSOR_POSITION             SetCursorPosition;
隐藏或显示光标 equ 设置光标位置 + 8; EFI_TEXT_ENABLE_CURSOR                   EnableCursor;
模式的数据指针 equ 隐藏或显示光标 + 8; SIMPLE_TEXT_OUTPUT_MODE                  *Mode;
;} EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL;


;https://uefi.org/specs/UEFI/2.10/04_EFI_System_Table.html#efi-boot-services
;#define EFI_BOOT_SERVICES_SIGNATURE 0x56524553544f4f42
;#define EFI_BOOT_SERVICES_REVISION EFI_SPECIFICATION_VERSION

;typedef struct {
;  EFI_TABLE_HEADER     Hdr;

;  //
;任务优先服务  // Task Priority Services
;  //
提升任务优先级 equ EFI表头大小 + 0;  EFI_RAISE_TPL        RaiseTPL;       // EFI 1.0+
恢复任务优先级 equ 提升任务优先级 + 8;  EFI_RESTORE_TPL      RestoreTPL;     // EFI 1.0+

;    //
;内存服务    // Memory Services
;    //
分配内存页 equ 恢复任务优先级 + 8;    EFI_ALLOCATE_PAGES   AllocatePages;  // EFI 1.0+
释放内存页 equ 分配内存页 + 8;    EFI_FREE_PAGES       FreePages;      // EFI 1.0+
获取内存图 equ 释放内存页 + 8;    EFI_GET_MEMORY_MAP   GetMemoryMap;   // EFI 1.0+
分配内存池 equ 获取内存图 + 8;    EFI_ALLOCATE_POOL    AllocatePool;   // EFI 1.0+
释放内存池 equ 分配内存池 + 8;    EFI_FREE_POOL        FreePool;       // EFI 1.0+

;    //
;事件和定时器服务    // Event & Timer Services
;    //
创建事件 equ 释放内存池 + 8;    EFI_CREATE_EVENT     CreateEvent;    // EFI 1.0+
设置定时器 equ 创建事件 + 8;    EFI_SET_TIMER        SetTimer;       // EFI 1.0+
等待产生事件 equ 设置定时器 + 8;    EFI_WAIT_FOR_EVENT   WaitForEvent;   // EFI 1.0+
信号事件 equ 等待产生事件 + 8;    EFI_SIGNAL_EVENT     SignalEvent;    // EFI 1.0+
关闭事件 equ 信号事件 + 8;    EFI_CLOSE_EVENT      CloseEvent;     // EFI 1.0+
检查事件 equ 关闭事件 + 8;    EFI_CHECK_EVENT      CheckEvent;     // EFI 1.0+

;    //
;协议事件处理服务    // Protocol Handler Services
;    //
安装协议接口 equ 检查事件 + 8;    EFI_INSTALL_PROTOCOL_INTERFACE     InstallProtocolInterface;            // EFI 1.0+
重新安装协议接口 equ 安装协议接口 + 8;    EFI_REINSTALL_PROTOCOL_INTERFACE   ReinstallProtocolInterface;          // EFI 1.0+
卸载协议接口 equ 重新安装协议接口 + 8;    EFI_UNINSTALL_PROTOCOL_INTERFACE   UninstallProtocolInterface;          // EFI 1.0+
处理协议 equ 卸载协议接口 + 8;    EFI_HANDLE_PROTOCOL                HandleProtocol;                      // EFI 1.0+
引导服务表预留项_1 equ 处理协议 + 8; VOID*   Reserved;    // EFI 1.0+
注册协议通知 equ 引导服务表预留项_1 + 8;    EFI_REGISTER_PROTOCOL_NOTIFY       RegisterProtocolNotify;              // EFI  1.0+
定位句柄 equ 注册协议通知 + 8;    EFI_LOCATE_HANDLE                  LocateHandle;                        // EFI 1.0+
定位设备路径 equ 定位句柄 + 8;    EFI_LOCATE_DEVICE_PATH             LocateDevicePath;                    // EFI 1.0+
安装配置表 equ 定位设备路径 + 8; EFI_INSTALL_CONFIGURATION_TABLE       InstallConfigurationTable;           // EFI 1.0+

;    //
;映像服务    // Image Services
;    //
加载映像 equ 安装配置表 + 8;    EFI_IMAGE_UNLOAD               LoadImage;        // EFI 1.0+
进入映像 equ 加载映像 + 8;    EFI_IMAGE_START                StartImage;       // EFI 1.0+
退出映像 equ 进入映像 + 8;    EFI_EXIT                       Exit;             // EFI 1.0+
卸载映像 equ 退出映像 + 8;    EFI_IMAGE_UNLOAD               UnloadImage;      // EFI 1.0+
退出引导服务 equ 卸载映像 + 8;    EFI_EXIT_BOOT_SERVICES         ExitBootServices; // EFI 1.0+

;    //
;看门狗和杂项服务    // Miscellaneous Services
;    //
获取下一单次计数 equ 退出引导服务 + 8;    EFI_GET_NEXT_MONOTONIC_COUNT   GetNextMonotonicCount; // EFI 1.0+
延迟计数 equ 获取下一单次计数 + 8;    EFI_STALL                      Stall;                 // EFI 1.0+
设置看门狗定时器 equ 延迟计数 + 8;    EFI_SET_WATCHDOG_TIMER         SetWatchdogTimer;      // EFI 1.0+

;    //
;驱动程序支持服务    // DriverSupport Services
;    //
连接控制器 equ 设置看门狗定时器 + 8;    EFI_CONNECT_CONTROLLER         ConnectController;     // EFI 1.1
断开控制器 equ 连接控制器 + 8;    EFI_DISCONNECT_CONTROLLER      DisconnectController;  // EFI 1.1+

;    //
;打开和关闭协议服务    // Open and Close Protocol Services
;    //
打开协议 equ 断开控制器 + 8;    EFI_OPEN_PROTOCOL              OpenProtocol;           // EFI 1.1+
关闭协议 equ 打开协议 + 8;    EFI_CLOSE_PROTOCOL             CloseProtocol;          // EFI 1.1+
打开协议信息 equ 关闭协议  + 8; EFI_OPEN_PROTOCOL_INFORMATION     OpenProtocolInformation;// EFI 1.1+

;    //
;库服务    // Library Services
;    //
每个句柄的协议数 equ 打开协议信息 + 8;    EFI_PROTOCOLS_PER_HANDLE       ProtocolsPerHandle;     // EFI 1.1+
定位句柄缓冲区 equ 每个句柄的协议数 + 8;    EFI_LOCATE_HANDLE_BUFFER       LocateHandleBuffer;     // EFI 1.1+
协议定位 equ 定位句柄缓冲区 + 8;    EFI_LOCATE_PROTOCOL            LocateProtocol;         // EFI 1.1+
安装多个协议接口 equ 协议定位 + 8;  EFI_UNINSTALL_MULTIPLE_PROTOCOL_INTERFACES  InstallMultipleProtocolInterfaces;    // EFI 1.1+
卸载多个协议接口 equ 安装多个协议接口 + 8;  EFI_UNINSTALL_MULTIPLE_PROTOCOL_INTERFACES UninstallMultipleProtocolInterfaces;   // EFI 1.1+*

;    //
;32位CRC服务    // 32-bit CRC Services
;    //
计算CRC32 equ 卸载多个协议接口 + 8;    EFI_CALCULATE_CRC32    CalculateCrc32;     // EFI 1.1+

;    //
;杂项服务    // Miscellaneous Services
;    //
复制内存 equ 计算CRC32 + 8;    EFI_COPY_MEM           CopyMem;        // EFI 1.1+
设置内存 equ 复制内存 + 8;    EFI_SET_MEM            SetMem;         // EFI 1.1+
创建事件Ex equ 设置内存 + 8;    EFI_CREATE_EVENT_EX    CreateEventEx;  // UEFI 2.0+
;  } EFI_BOOT_SERVICES;













;#define EFI_BLOCK_IO_PROTOCOL_GUID \
 ;{0x964e5b21,0x6459,0x11d2,\
;  {0x8e,0x39,0x00,0xa0,0xc9,0x69,0x72,0x3b}}

;typedef struct _EFI_BLOCK_IO_PROTOCOL {
;  UINT64                         Revision;
;  EFI_BLOCK_IO_MEDIA             *Media;
;  EFI_BLOCK_RESET                Reset;
;  EFI_BLOCK_READ                 ReadBlocks;
;  EFI_BLOCK_WRITE                WriteBlocks;
;  EFI_BLOCK_FLUSH                FlushBlocks;
;} EFI _BLOCK_IO_PROTOCOL;













;将会修改所有寄存器
;输入RCX句柄，RDX系统表，RSP调用者的栈
;无输出
代码起始:
bits 64
;jmp $

;保存传入参数
;https://uefi.org/specs/UEFI/2.10/02_Overview.html#handoff-state-2
sub rsp,8;注意将栈对齐16byte字节，因为UEFI使用call指令进入本函数而非jmp指令，这就导致了虽然UEFI在进入本函数前栈是以16byte字节对齐但因为call会在栈中压入返回地址并将栈减8byte字节而使栈不以16byte字节对齐，应再次将栈减8byte字节以恢复栈的16byte字节对齐
push rdx
push rcx

;提前获取函数指针以加快调用速度和减少代码大小
;你可使用IDA按F5进行反编译以查看结构体详情
mov rbx,[rdx + 简单文本输出协议]
mov [rel + 简单文本输出协议表起始],rbx

mov rbp,[rdx + 简单文本输出协议]
mov rbp,[rbp + 输出字符串]
mov [rel + 输出字符串函数指针],rbp

mov rax,[rdx + 引导服务表指针]
mov [rel + 引导服务表起始],rax

mov rcx,[rdx + 引导服务表指针]
mov rcx,[rcx+定位句柄]
mov [rel + 定位句柄函数指针],rcx

mov rsi,[rdx + 引导服务表指针]
mov rsi,[rsi + 打开协议]
mov [rel + 打开协议函数指针],rsi

mov rdi,[rdx + 引导服务表指针]
mov rdi,[rdi + 分配内存页]
mov [rel + 分配内存页函数指针],rdi

mov r8,[rdx + 引导服务表指针]
mov r8,[r8 + 获取内存图]
mov [rel + 获取内存图函数指针],r8



lea rax,[rel + 可参照IDA函数结构体结束]
jmp rax



;https://uefi.org/specs/UEFI/2.10/12_Protocols_Console_Support.html#efi-simple-text-output-protocol-outputstring
;typedef
;EFI_STATUS
;(EFIAPI *EFI_TEXT_STRING) (
; IN EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL    *This,
; IN CHAR16                             *String
; );

;输入RCX简单文本输出协议表指针，RDX字符串指针
;输出显示字符串
可参照IDA函数结构体结束:
mov rcx,rbx
lea rdx,[rel + 字符串_间隔]
call rbp

db 0ebh,0feh
;https://wiki.osdev.org/Reading_sectors_under_UEFI
mov r9,0;在缓冲区不够大时会返回需要多大的缓冲区，输入零大小以获得需要多大的缓冲区
lea rdx,[rel + 块设备读写的UUid]
lea rbx,[rel + 缓冲区起始]
call 获取指定的句柄表
mov rcx,8000000000000005h
cmp rax,rcx
jnz $

cmp r9,0
jz $

mov r9,20h
lea rdx,[rel + 块设备读写的UUid]
lea rbx,[rel + 缓冲区起始]
call 获取指定的句柄表
cmp rax,0

jmp $




;稍等一下，以便用户可以看到该字符串
;mov rcx,;5000000;一百万微秒等于一秒
;call [BOOT_SERVICES_STALL]











;https://uefi.org/specs/UEFI/2.10/07_Services_Boot_Services.html#efi-boot-services-locatehandle
;typedef
;EFI_STATUS
;(EFIAPI *EFI_LOCATE_HANDLE) (
;   IN EFI_LOCATE_SEARCH_TYPE                 SearchType，指定要返回哪些句柄。类型 EFI_LOCATE_SEARCH_TYPE 在“相关定义”中定义。
;   IN EFI_GUID                               *Protocol OPTIONAL，指定要搜索的协议。仅当 SearchType 为ByProtocol时，此参数才有效。类型 EFI_GUID 在EFI_BOOT_SERVICES.InstallProtocolInterface()函数描述中定义 。
;   IN VOID                                   *SearchKey OPTIONAL，指定搜索关键字。如果 SearchType 为AllHandles或ByProtocol ，则忽略此参数。如果 SearchType 为ByRegisterNotify ，则该参数必须是函数EFI_BOOT_SERVICES.RegisterProtocolNotify()返回的 Registration 值 。
;   IN OUT UINTN                              *BufferSize，在输入时，以字节为单位的缓冲区大小。在输出时，*Buffer*中返回的数组的字节大小（如果缓冲区足够大）或获取该数组所需的缓冲区的字节大小（如果缓冲区不够大）。
;   OUT EFI_HANDLE                            *Buffer，返回数组的缓冲区。类型 EFI_HANDLE 在 InstallProtocolInterface() 函数描述中定义。
;   );

;//******************************************************
;// EFI_LOCATE_SEARCH_TYPE
;//******************************************************
;typedef enum {
所有句柄数组 equ 0;   AllHandles,
通过注册通知 equ 所有句柄数组 + 1;   ByRegisterNotify,
按协议 equ 通过注册通知 + 1;   ByProtocol
;  } EFI_LOCATE_SEARCH_TYPE;

;输入，RCX 搜索的句柄表类型，RDX全局唯一标识，R8 搜索关键字，R9 句柄表缓冲区大小，RBX 句柄缓冲区起始
;输出RAX返回值，R9 所需的缓冲区大小，缓存区内句柄数组
获取指定的句柄表:
mov rcx,按协议
mov r8,0;null
sub rsp,8 * 4 + 8
mov [rsp + 8 * 3],r9
lea r9,[rsp + 8 * 3]
mov [rsp + 8 * 4],rbx
call [rel + 定位句柄函数指针]
mov r9,[rsp + 8 * 3];为何uefi不把所需的缓冲区大小直接写入r8寄存器，难道是fastcall约定返回值只能在rax寄存器吗
add rsp,8 * 4 + 8
ret


;输入
;输出
;
获取指定的句柄表函数返回状态:
cmp al,7
ja $

lea rdx,[rel + 获取指定的句柄表函数返回状态的字符串指针表起始]
movzx eax,al
add rdx,rax
jmp 打印并暂停







;https://uefi.org/specs/UEFI/2.10/07_Services_Boot_Services.html#efi-boot-services-allocatepages











打印并暂停:
mov rcx,[rel + 简单文本输出协议表起始]
call [rel + 输出字符串函数指针] 



暂停:
hlt
jmp 暂停


















;https://uefi.org/specs/UEFI/2.10/07_Services_Boot_Services.html#efi-boot-services-allocatepages
;typedef
;EFI_STATUS
;(EFIAPI *EFI_ALLOCATE_PAGES) (
;   IN EFI_ALLOCATE_TYPE                   Type，要执行的分配类型。请参阅“Related Definitions”
;   IN EFI_MEMORY_TYPE                     MemoryType，要分配的内存类型。EFI_MEMORY_TYPE 在下文的“Related Definitions”中定义。这些内存类型也在ExitBootServices() 之前的内存类型使用和 ExitBootServices() 之后的内存类型使用中进行了更详细的描述。正常分配（即任何 UEFI 应用程序的分配）的类型为 EfiLoaderData。0x70000000..0x7FFFFFFF范围内的MemoryType值保留供 OEM 使用。0x80000000..0xFFFFFFFF 范围内的MemoryType值保留供操作系统供应商提供的 UEFI OS 加载程序使用。
;   IN UINTN                               Pages，要分配的 4KB 连续页数量
;   IN OUT EFI_PHYSICAL_ADDRESS            *Memory，指向物理地址的指针。输入时，地址的使用方式取决于Type的值。有关更多信息，请参阅“Definitions”。输出时，地址设置为已分配页面范围的基数。请参阅“Related Definitions”
;   );
;注意：UEFI 应用程序、UEFI 驱动程序和 UEFI OS 加载器不得分配类型为EfiReservedMemoryType、EfiMemoryMappedIO和EfiUnacceptedMemoryType 的内存

;//******************************************************
;//EFI_ALLOCATE_TYPE
;//******************************************************
;// These types are discussed in the "Description" section below.
;typedef enum {
;   AllocateAnyPages,
;   AllocateMaxAddress,
;   AllocateAddress,
;   MaxAllocateType
;} EFI_ALLOCATE_TYPE;

;//******************************************************
;//EFI_MEMORY_TYPE
;//******************************************************
;// These type values are discussed in Memory Type Usage before ExitBootServices()  and  Memory Type Usage after ExitBootServices().
;typedef enum {
;   EfiReservedMemoryType,
;   EfiLoaderCode,
;   EfiLoaderData,
;   EfiBootServicesCode,
;   EfiBootServicesData,
;   EfiRuntimeServicesCode,
;   EfiRuntimeServicesData,
;   EfiConventionalMemory,
;   EfiUnusableMemory,
;   EfiACPIReclaimMemory,
;   EfiACPIMemoryNVS,
;   EfiMemoryMappedIO,
;   EfiMemoryMappedIOPortSpace,
;   EfiPalCode,
;   EfiPersistentMemory,
;   EfiUnacceptedMemoryType,
;   EfiMaxMemoryType
;} EFI_MEMORY_TYPE;

;//******************************************************
;//EFI_PHYSICAL_ADDRESS
;//******************************************************
;typedef UINT64 EFI_PHYSICAL_ADDRESS;

;AllocatePages() 函数分配请求的页数，并返回指向Memory引用位置的页范围基址的指针。该函数扫描内存映射以查找空闲页。当它找到一个物理上连续的、足够大且满足Type分配要求的页块时，它会更改内存映射以指示这些页现在属于MemoryType类型

;一般而言，UEFI OS 加载器和 UEFI 应用程序应分配 EfiLoaderData 类型的内存（和池）。UEFI 启动服务驱动程序必须分配 EfiBootServicesData 类型的内存（和池）。UREFI 运行时驱动程序应分配 EfiRuntimeServicesData 类型的内存（和池）（尽管此类分配只能在启动服务期间进行）

;AllocateAnyPages类型的分配请求分配满足请求的任何可用页面范围。输入时， Memory指向的地址将被忽略。

;AllocateMaxAddress类型 的分配请求分配任何可用的页面范围，其最高地址小于或等于输入时Memory指向的地址

;AllocateAddress类型的分配请求在输入的Memory指向的地址处分配页面

;注意：不针对特定实现的 UEFI 驱动程序和 UEFI 应用程序必须使用 AllocateAnyPages 地址模式为以下运行时类型执行内存分配：
;EfiACPIReclaimMemory
;EfiACPIMemoryNVS
;EfiRuntimeServicesCode
;EfiRuntimeServicesData
;EfiReservedMemoryType

;输入RCX函数类型，RDX页类型，R8 4K页数，R9物理地址指针
;输出
;将会修改寄存器
函数_从系统分配内存页:



call [rel + 分配内存页函数指针]


ret






;https://wiki.osdev.org/GOP





;成功返回UEFI
;mov rcx,[EFI_句柄]
;mov rdx,0
;mov r8, 1
;call [BOOT_SERVICES_EXIT]
;ret
代码结束:
代码大小 equ 代码结束 - 代码起始
;times 扇区大小 - 代码大小 db 0;对齐
代码填充结束:




获取指定的句柄表函数返回状态的字符串指针表起始:
dq 表示返回句了柄数组的字符串
dq 表示没有与搜索相匹配的句柄字符串
dq 表示指向缓冲区大小的指针为空的字符串
dq 表示搜索类型不是EFI_LOCATE_SEARCH_TYPE的成员的字符串
dq 表示搜索类型为ByProtocol且ProtocoL为空的字符串
dq 表示找到一个或多个匹配项并且BufferSize为NULL字符串
dq 表示缓冲区大小足够大以容纳结果但缓冲区指针为空的字符串










;字符串
数据起始:

字符串_间隔 dw 13
回车加换行 dw 13
换行 dw 10,0
测试文本 db __utf16__ 'cialoo 0721',0,0
块设备读写的UUid db 21h,5bh,4eh,96h,59h,64h,0d2h,11h,8eh,39h,00h,0a0h,0c9h,69h,72h,3bh
表示返回句了柄数组的字符串 db __utf16__ 'The array of handles was returned',0,0
表示没有与搜索相匹配的句柄字符串 db __utf16__ 'No handles match the search',0,0
表示指向缓冲区大小的指针为空的字符串 db __utf16__ 'Pointer to buffer size is null',0,0
表示搜索类型不是EFI_LOCATE_SEARCH_TYPE的成员的字符串 db __utf16__ 'SearchType is not a member of EFI_LOCATE_SEARCH_TYPE',0,0
表示字搜索类为ByRegisterNotify且SearchKey为空的型符串 db __utf16__ 'SearchType is ByRegisterNotify and SearchKey is NULL',0,0
表示搜索类型为ByProtocol且ProtocoL为空的字符串 db __utf16__ 'SearchType is ByProtocol and ProtocoL is NULL',0,0
表示找到一个或多个匹配项并且BufferSize为NULL字符串 db __utf16__ 'One or more matches are found and BufferSize is NULL',0,0
表示缓冲区大小足够大以容纳结果但缓冲区指针为空的字符串 db __utf16__ 'BufferSize is large enough for the result and Buffer is NULL',0,0
;db __utf16__
;db __utf16__
;db __utf16__




















EFI_句柄 dq 0
EFI_系统表 dq 0
EFI_返回地址 dq 0

;常用的函数表指针
简单文本输出协议表起始 dq 0
引导服务表起始 dq 0

;常用函的数指针
;int10打印字符串;BIOS中断不支持这个函数
输出字符串函数指针 dq 0
定位句柄函数指针 dq 0
打开协议函数指针 dq 0
分配内存页函数指针 dq 0
获取内存图函数指针 dq 0

;int10AH0e输出单个字符:;UEFI不支持这个函数
int10AH02设置光标位置:
int10AH03获取光标位置:



数据结束:
数据大小 equ 数据结束 - 数据起始
;times 扇区大小 -  数据大小 db 0;对齐
数据填充结束:

缓冲区起始: