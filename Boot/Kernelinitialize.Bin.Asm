;============================================================================
;初始化整个操作系统\
@ychen
;----------------------------------------------------------------------------

;内存布局
iNiTiALiZE起始 equ 100000h-10h;～10FFeF=initialize.Bin
缓存区_1 equ 数据结束;～6FFFF
;系统内存映射表
;中断描述符表
页表 equ 4096;4kb对齐～+20480
栈 equ 0FFFFh;FFFF：FFFF

org 10h;+10h
mov ax,iNiTiALiZE起始/10h
mov ds,ax
mov es,ax
mov ss,ax
mov esp,栈;顺便清空高位

mov si,回车加换行
call 实模式的打印
mov si,换行
call 实模式的打印

CheckFor64BitSupport:
pushfd;检查CPU是否支持CPUID
pop eax
mov ebx,eax
xor eax,00200000h;反转第21位
push eax
popfd
pushfd
pop eax
cmp eax,ebx;EFLAG第21位可操作即可被置1或置0则代表支持CPUiD指令
jnz CheckForPAE

mov si,Msg_NoCpuidSupport
call 实模式的打印
jmp 暂停处理器

Msg_NoCpuidSupport db 13,10,"The system doesn't support CPUiD.",0

CheckForPAE:;检测到 CPUID 支持 - 获取 PAE/PGE
mov eax,80000000h
cpuid
cmp eax,80000000h;Any function > 0x80000000 ?
jbe NoLongMode;如果不是，则没有长模式。

xor edx,edx;检查CPU是否支持长模式
mov eax,80000001h
cpuid
and edx,20000000h
test edx,edx
jnz Success

NoLongMode:;
mov si,Msg_NoLongMode
call 实模式的打印
jmp 暂停处理器

Msg_NoLongMode db 13,10,"Long mode is not supported.",0

Success:;
mov si,OSHAL
mov ah,9
int 21h
jc $

mov si,回车加换行
call 实模式的打印
mov si,MEM
mov ebx,10FFF0h
mov ah,9
int 21h
jnc $

mov edi,缓存区_1;顺便清空高位
mov ebx,0;第一次调用时须要为0
mov ecx,20;获取的项大小
mov edx,534D4150h;SMAP注意大小端
mov eax,0e820h;有些BiOS需要清空高位
int 15h
jc 实模式的打印不支持eax0e820hint15h;第一次调用时设置的进位意味着“不支持的功能”

cmp eax,534D4150h;成功后， eax必须赋值为“SMAP” 
jnz 实模式的打印eax0e820hint15h发生错误

继续获取内存布局:
 mov eax,0e820h;有些BiOS需要清空高位
 int 15h
 jc 结束获取内存布局

;add di,20
 cmp eax,534D4150h;成功后， eax必须赋值为“SMAP” 
 jnz 实模式的打印eax0e820hint15h发生错误

 cmp ebx,0
jnz 继续获取内存布局

结束获取内存布局:


;AH = C1h
;int 15


push di;获取的内存布局表结束

mov eax,tesst+iNiTiALiZE起始
mov cx,8e00h;属性，中断门
call 制作_64位模式的中断描述符












;应该使用1111内存页属性

add di,页表
and di,1111_0000_00000000b;清空低12位
add di,10h;别忘了实模式访问1mb以上内存需要偏移地址+10h
;mov ebx,iNiTiALiZE起始
lea eax,[edi+iNiTiALiZE起始];将cr3指向p4，PML4E
mov cr3,eax

;这是p4，PML4E
lea eax,[edi+iNiTiALiZE起始+4096];p3，PDPTE的位置
or eax,111b;低12位是属性
cld;正序
stosd
mov eax,0
mov cx,4096/4-1;-1因为上面已经stosd一次了
rep stosd

;这是p3，PDPTE
lea eax,[edi+iNiTiALiZE起始+4096];p2，PDE的位置
or eax,111b
stosd
mov eax,0
mov cx,4096/4-1
rep stosd

;这是p2，PDE
lea eax,[edi+iNiTiALiZE起始+4096];p1，PTE的位置
or eax,111b
stosd
mov dword[di],0
add di,4
add eax,4096;第2张表的位置
stosd
;mov dword[di],0
;add di,4
mov eax,0
mov cx,4096/4-3
rep stosd

;这是p1，PTE
mov eax,111b;物理地址的位置
;or eax,0000111b
mov cx,4194304/4096*8/4;前4mb的内存

构建物理地址项:
stosd
mov dword[di],0
add di,4
add eax,4096
loop 构建物理地址项

nop;等待缓存写入内存
nop
nop
nop
;jmp $

mov dword[ContinueAddress],tesst+iNiTiALiZE起始;eax
jmp 进入长模式





bits 64
tesst:
nop
nop
;jmp $




mov word[实模式代码的位置+iNiTiALiZE起始],fpfs



jmp 进入实模式


bits 16
fpfs:


mov si,字符串eax0e820hint15hisnotsupported
call 实模式的打印
jmp $

















bits 64

;#DE




bits 16




















OSHAL db 'OPERATING SYSTEM/HARDWARE ABSTRACTION LAYER/',0
MEM db 'MEMORYMANAGER.BIN',0







;如 ACPI 规范中所述，要查找 ACPI RSDT，请在 EBDA 中查找“RSD PTR”，如果不存在，则每 16 个字节搜索 0e0000h-0fffffh。它包含一个指向偏移量 12 处的 RSDT 的指针

实模式的打印不支持eax0e820hint15h:
;80h 无效命令 (PC,PCjr)
;cmp ah,86h;不支持 86h 功能 (XT)
mov si,字符串eax0e820hint15hisnotsupported
call 实模式的打印
jmp 暂停处理器

字符串eax0e820hint15hisnotsupported db 13,10,'eax 0e820h int 15h is not supported',0


实模式的打印eax0e820hint15h发生错误:
mov si,字符串eax0e820hint15hAnerroroccurred
call 实模式的打印
jmp 暂停处理器

字符串eax0e820hint15hAnerroroccurred db 13,10,'eax 0e820h int 15h An error occurred',0






;将会修改EAX，ECX，CS，DS，ES，FS，GS，SS，ESP，GDTR，iDTR，CR0，CR4寄存器
;输入ContinueAddress长模式跳转地址
;输出
进入长模式:;ExitToLongMode
cli;关中断
mov ax,0
mov ds,ax
mov es,ax
mov fs,ax
mov gs,ax
mov ss,ax

mov eax,cr4
or eax,1010_0000b;启用物理地址扩展PhysicalAddressExtension，PGE
mov cr4,eax
mov ecx,0c0000080h;指定EFER MSR
rdmsr
or eax,1_00000000b;启用长模式
wrmsr
mov eax,cr0
or eax,10000000000000000000000000000001b;通过同时启用PG分页和PE保护
mov cr0,eax
lgdt cs:[GDTcfg]
jmp dword 16:InLongMode+iNiTiALiZE起始

bits 64
InLongMode:
db 0FFh,25h;64位间接跳转操作码
dd 1;LongModeEntryPoint相对地址

nop;为什么需要这个NOP

LongModeEntryPoint:
dd RealEntryPoint+iNiTiALiZE起始,0;这是个64位的地址

RealEntryPoint:
mov ax,18h
mov ds,ax
mov es,ax
mov fs,ax
mov gs,ax
add esp,iNiTiALiZE起始
lidt [长模式中断表];我迫切地需要知道发生什么错误
jmp qword[ContinueAddress+iNiTiALiZE起始]

ContinueAddress dd 0,0



;将会修改EAX，ECX，CS，DS，ES，FS，GS，SS，ESP，iDTR，CR0，CR4寄存器
;输入实模式代码的位置即跳转地址
;输出
进入实模式:;SwitchToReal
mov ax,18h;24
mov ds,ax
mov es,ax
mov fs,ax
mov gs,ax
db 0FFh,2dh;jmp fword ptr cs:[jumpvector];操作码
dd 0;[位置]

jumpvector:
dd SwitchToRealCompSegment+iNiTiALiZE起始
dw 30h

SwitchToRealCompSegment:
;jmp $; 注意 使用ida连接VMware时会在此处丢失单步跟踪，在此处jmp $即可解决
mov rax, cr0;目前处理器64位里的32位兼容模式。但它会解释相应地生成的指令。将RAX变成EAX 
and eax,7FFFFFFFh;禁用内存分页
mov cr0, rax
db 0eah;32bit jmp
AddressOfRealModeEntryPoint dd RealModeEntryPoint
dw 20h;段选择子

nop

bits 16
RealModeEntryPoint:
mov ecx,0c0000080h;指定EFER MSR
rdmsr
and eax,11111111_11111111_11111110_11111111b;禁用长模式
wrmsr
mov eax,cr4
and eax,11111111_11111111_11111111_01011111b;屏蔽PAE和PGE
mov cr4,eax
mov eax,cr0
and eax,11111111_11111111_11111111_11111110b;禁用保护模式PE
mov cr0,eax
jmp word iNiTiALiZE起始/10h:InRealMode;清除预取队列并纠正CS

InRealMode:
mov ax,cs;iNiTiALiZE起始/16
mov ds,ax
mov es,ax
mov fs,ax
mov gs,ax
mov ss,ax
cmp esp,10FFeFh
lidt cs:[iVTcfg]
ja $;大于则跳转

sub esp,iNiTiALiZE起始
jmp word[实模式代码的位置]

实模式代码的位置 dw 0

iVTcfg:;
dw 256*4-1;实模式有256个中断项，每个项的长度为4byte，别忘了-1byte
dd 0;起始于0结束于3FF



GDTcfg:;
dw GdtEnd-GdtStart-1;长度-1以忽略后1字节，因为计算机是从0开始计数的
dd GdtStart+iNiTiALiZE起始;idt的位置

;align 8
GdtStart:;
dw 0000h,0000h,0000h,0000h;空描述符
dw 0000h,0000h,0000h,0000h;占位
dw 0000h,0000h,9800h,0020h;长模式cs
dw 0FFFFh,0000h,0F300h,00CFh;长模式ds

;dw 0FFFFh,0000h,9E00h,0000h;实模式cs
dw 0FFFFh;段长度
db 0F0h,0FFh,0Fh;注意，基地址
db 9eh;10010010b;段属性
db 0;1100_1111b;段属性_段长度1111b
db 0;基地址00h

dw 0FFFFh,0000h,9200h,0000h;实模式ds
dw 0FFFFh,0000h,9B00h,00CFh;兼容保护模式cs
GdtEnd:;









;将会修改AX，BH，Si寄存器
;输入DS：Si带结束符的字符串位置
;输出
实模式的打印:
mov ah,14;功能号
mov bh,0;页码
jmp 插入_3

继续实模式的打印:;每个指令都很重要确保他们被正确执行
 int 10h;中断号

 插入_3:
 lodsb;将DS：Si指向的内容放入AL然后Si+1
 cmp al,0
jnz 继续实模式的打印

ret



暂停处理器:
 cli;会导致某些虚拟机报错
 hlt
jmp short 暂停处理器





;将会修改AX，BH，Di寄存器
;输入ES：Di中断描述符的写入位置，EAX中断处理代码的位置，CL本中断描述符的属性，DX段选择子
;输出
制作_64位模式的中断描述符:
stosw;中断处理代码位置的低16位
mov ax,10h;dx;段选择子
stosw
mov ax,cx;属性
stosw
shr eax,16;移下来
stosw;中断处理代码位置的中16位
;mov eax,0;EAX已被清空
stosd;我们没使用到的中断处理代码位置的高32位
stosd;填充0
ret





回车加换行 db 13
换行 db 10,0
长模式中断表:
dw 0
dq 0


数据结束:; equ $