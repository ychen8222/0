;初始化整个操作系统
;@ychen



;内存布局
initialize起始 equ 100000h - 10h;～10FFeF=initialize.Bin
MemoryManager起始 equ 200000h



;参数命名
架构位宽 equ 16
段地址乘数 equ 16
最小页大小 equ 4096;4kb对齐～+20480

org 段地址乘数;+10h
bits 16
mov al,al;处理器架构标识


;将会修改所有寄存器
;无输入
;无输出
mov ax,initialize起始/段地址乘数
mov ds,ax
mov es,ax
mov ss,ax
mov sp,0FFFFh;临时栈

mov si,字符串_间隔
call 实模式打印


;使用cpuid检查是否支持长模式，但在此之前先要检查是否支持cpuid
pushfd;读扩展标志寄存器
mov eax,[esp]
xor dword [esp],10_0000000000_0000000000b;反转第22位
popfd;写扩展标志寄存器
pushfd
cmp [esp],eax;扩展标志寄存器第21位可操作即可被置1或置0则代表支持cpuid指令
jnz CheckForPAE

add esp,4;删栈中EFlag数值，为什么不是还原，因为iD位并没有改变
mov si,Message_NoCpuidSupport
call 实模式打印
jmp 在实模式暂停处理器

CheckForPAE:
mov [esp],eax;还原EFlag寄存器
popfd
mov eax,80000000h;检查cpuid所接受的最大功能号
cpuid
cmp eax,80000001h;
jb NoLongMode;

mov eax,80000001h
cpuid
bt edx,29;将EDX的第30比特放入CF标志位
jc Success;Intel® 64 Intel® 64 Instruction Set Architecture

NoLongMode:;
mov si,Message_NoLongMode
call 实模式打印
jmp 在实模式暂停处理器

Success:;加载文件
mov si,路径_OSHAL
mov ah,9
int 21h
jc $

mov si,字符串_回车加换行
call 实模式打印
mov si,文件名_MEM
mov ebx,MemoryManager起始 + 最小页大小
mov ah,9
int 21h
jc $


;构建Kernelinitialize.Bin的内存页表
mov edi,_堆起始 + 最小页大小;顺便清空高位
and di,1111_0000_00000000b;清空低12位
add di,段地址乘数;别忘了实模式访问1mb以上内存需要偏移地址+10h
;mov ebx,initialize起始
lea eax,[edi+initialize起始];将CR3指向p4，PML4E
mov cr3,eax

;这是p1，PML4E
lea eax,[edi + 最小页大小 + initialize起始];p2，PDPTE的位置
or ax,111b;低12位是属性;应该使用1111内存页属性
cld;正序
stosd
mov eax,0
mov cx,最小页大小 / 4-1;-1因为上面已经stosd一次了
rep stosd

;这是p2，PDPTE
lea eax,[edi+ 最小页大小 + initialize起始];p3，PDE的位置
or ax,111b
stosd
mov eax,0
mov cx,最小页大小 / 4-1
rep stosd

;这是p3，PDE
lea eax,[edi + 最小页大小 + initialize起始];p4，PTE的位置
or ax,111b
stosd
mov dword [di],0
add di,4
add eax,最小页大小;第2张表的位置
stosd
;mov dword[di],0
;add di,4
mov eax,0
mov cx,最小页大小 / 4-3
rep stosd

;这是p4，PTE
mov eax,initialize起始+段地址乘数;物理地址的位置
or ax,111b
stosd;映射第1张页表到1mb处
mov dword [di],0
add di,4
mov eax,最小页大小;开始正常映射内存，但由于第1张页表映射了其他地方，所以我们不能访问实模式的中断描述符表了
or ax,111b
mov cx,400000h / 最小页大小 * 8 / 4 - 2;前4mb的内存

构建本程序的物理地址项:
stosd
mov dword [di],0
add di,4
add eax,最小页大小
loop 构建本程序的物理地址项



;https://www.ctyme.com/intr/rb-1741.htm https://osdev.org/Detecting_Memory_(x86)
;构建内存布局表
普通的内存布局项起始 equ 0
普通的内存布局项结束 equ 普通的内存布局项起始+2
ACPi的内存布局项起始 equ 普通的内存布局项结束+2
ACPi的内存布局项结束 equ ACPi的内存布局项起始+2
构建内存布局表函数的栈帧 equ ACPi的内存布局项结束+2

普通的内存布局项与ACPi的内存布局项之间的间隔 equ 20*4

sub sp,构建内存布局表函数的栈帧
mov [esp+普通的内存布局项起始],di;内存映射表起始
add di,普通的内存布局项与ACPi的内存布局项之间的间隔
mov [esp+ACPi的内存布局项起始],di
mov [esp+ACPi的内存布局项结束],di
sub di,普通的内存布局项与ACPi的内存布局项之间的间隔
;mov edi,堆
mov eax,0e820h;有些BiOS需要清空高位
mov ebx,0;要获取的项的序号，项从0开始计数
mov ecx,24;获取的项大小，BiOS会判断此值如果小于20则返回异常
mov edx,'PAMS';SMAP注意大小端
;将会修改EAX，BX，CX，EDX寄存器
;输入如上所示
;输出如下所示
;+ 0，dq 基地址
;+ 8，dq 长度（以字节为单位）
;+ 16，dd 该地址范围的类型
;系统内存映射地址类型的值：
;1h 内存，可供操作系统使用
;2h 保留，不可用（例如系统ROM、内存映射设备）
;3h ACPi回收内存（读取ACPi表后可供操作系统使用）
;4h ACPi NVS内存（操作系统需要在NVS会话之间保存此内存）
;其他尚未定义，视为保留
int 15h
jc 不支持eax0e820hint15h;第一次调用时设置进位意味着“不支持该功能”

cmp eax,534D4150h;成功后， EAX必须赋值为“SMAP”
jnz eax0e820hint15h发生错误

;cmp ebx,0;EBX=0意味着列表只有1个（无价值的）条目
;jz eax0e820hint15h发生错误

jmp 插入这里以保存第一次获取的项

继续获取内存布局:
 mov eax,0e820h;eax，ecx在每次int 0x15调用时都会被丢弃，因为EAX被BiOS赋值为用于验证是否成功的SMAP，ECX用于保存返回的项长度
 mov ecx,24;再次请求24个字节
 mov  dword es:[di+20] ,1;强制输入有效的3.X条目
 int 15h
 jc 结束获取内存布局

 插入这里以保存第一次获取的项:
 mov edx,eax;534D4150h;重新赋值可能已修改的寄存器，EAX已被BIOS赋值为SMAP注意大小端
 jcxz 获取下一项;跳过任何0长度的条目
 
 mov ecx,es:[di+8];低位的uint32_t内存区域长度
 or ecx,es:[di+8+4];将其与高位uint32_t进行“或”操作以检查否为零
 jz 获取下一项;如果长度uint64_t为0，则跳过该条目
 
 cmp cl,20
 jbe 普通的内存布局项;小于等于则跳转

 test byte es:[di+20],1b;此位为零则表示此项无效
 jz 获取下一项;忽略此项

 mov si,di;把ACPi的项复制到属于ACPi的项表中
 mov di,[esp+ACPi的内存布局项结束]
 add [esp+ACPi的内存布局项结束],cx
 rep movsb
 lea di,[si-24-20]

 普通的内存布局项:
 add di,20;推进到下一个位置以不覆盖此本项，因为BiOS不会帮我们推进
 cmp di,[esp+ACPi的内存布局项起始]
 jnz 获取下一项;还有空闲的位置保存普通的内存布局项

 mov cx,[esp+ACPi的内存布局项结束]
 sub cx,di;结束 - 起始 = 长度
 jz 不要复制ACPi的内存布局项;因为没有任何项

 ;mov si,[esp+ACPi的内存布局项起始]
 mov si,di
 mov ax,di
 lea di,[si+普通的内存布局项与ACPi的内存布局项之间的间隔]
 rep movsb
 mov di,ax

 不要复制ACPi的内存布局项:
 add word[esp+ACPi的内存布局项起始],普通的内存布局项与ACPi的内存布局项之间的间隔
 add word[esp+ACPi的内存布局项结束],普通的内存布局项与ACPi的内存布局项之间的间隔

 获取下一项:
 cmp ebx,0;如果EBX项序号被BiOS重置为0，则所有的项已获取结束
jnz 继续获取内存布局

结束获取内存布局:
mov bx,word[esp+普通的内存布局项起始];取出值并清空高位以便给长模式使用
mov di,di;word[esp+普通的内存布局项结束]
cmp bx,dx
jz $

mov si,word[esp+ACPi的内存布局项起始]
mov bp,word[esp+ACPi的内存布局项结束]
add sp,构建内存布局表函数的栈帧

;mov eax,initialize起始;把实模式的地址转换为长模式的地址
;add ebx,eax
;add edi,eax
;add esi,eax
;add ebp,eax


;构建MemoryManager的内存页表
;jmp $
mov dword[ContinueAddress],初始化内存管理进程+initialize起始
mov esp,$;顺便清空高位
jmp 切换到长模式

bits 64
初始化内存管理进程:
;jmp $
push bx
push di
push si
push bp


add edi,最小页大小
and di,1111_0000_00000000b;清空低12位
mov ebx,edi;p4，PML4E的地址

;这是p4，PML4E
lea eax,[edi + 最小页大小];p3，PDPTE的地址
or ax,111b;低12位是属性
;cld;正序
stosq
mov eax,0
mov ecx,最小页大小 / 8-1;-1是因为上面已经stosq一次了
rep stosq

;这是p3，PDPTE
lea eax,[edi + 最小页大小];p2，PDE的地址
or ax,111b
stosq
mov eax,0
mov cx,最小页大小 / 8-1
rep stosq

;这是p2，PDE
lea eax,[edi + 最小页大小];p1，PTE的地址
or ax,111b
stosq
add eax,最小页大小;第2张表的地址
stosq
mov eax,0
mov cx,最小页大小 / 8-2
rep stosq

;这是p1，PTE
mov eax,MemoryManager起始;物理内存的地址
or ax,111b
mov cx,10_0000h / 最小页大小 * 2;共映射2mb内存

构建内存管理进程的物理地址项:
 stosq
 add eax,最小页大小
loop 构建内存管理进程的物理地址项







;洗衣服时将他的袜子放进他的衣服里
;当光标到达行底时应该做点什么，比如准备更大的缓冲区以加快滚动




;游标



;error: unable to find valid values for all labels after 1004 passes; stalled for 1001, giving up.
预分配数据结构起始 equ 10FFeFh + 1

TSS项起始 equ 0;https://os.phil-opp.com/double-fault-exceptions/#the-ist-and-tss
 TSS预留的_1 equ TSS项起始 + 0
 RSPDPL0 equ TSS预留的_1 + 4
 RSPDPL1 equ RSPDPL0 + 8
 RSPDLP2 equ RSPDPL1 + 8
 TSS预留的_2 equ RSPDLP2 + 8
 iST0 equ TSS预留的_2 + 8
 iST1 equ iST0 + 8
 iST2 equ iST1 + 8
 iST3 equ iST2 + 8
 iST4 equ iST3 + 8
 iST5 equ iST4 + 8
 iST6 equ iST5 + 8
 iST7 equ iST6 + 8
 TSS预留的_3 equ iST7 + 8
 TSS预留的_4 equ TSS预留的_3 + 4
 iOPB equ TSS预留的_4 + 2
TSS项大小 equ iOPB + 2

TSS表起始 equ 预分配数据结构起始 + 0
TSS表大小 equ TSS项大小 * 4

系统调用项起始 equ 0
 系统调用项属性 equ 系统调用项起始 + 0
 系统调用进程页表指针 equ + 1
 系统调用代码指针 equ 系统调用进程页表指针 + 8
系统调用项大小 equ 系统调用代码指针 + 8

系统调用表起始 equ TSS表起始 + TSS表大小
系统调用表大小 equ 系统调用项大小 * 10

处理器控制块起始 equ 0
 当前执行的进程控制块指针 equ 处理器控制块起始 + 0
 当前执行的线程 equ 当前执行的进程控制块指针 + 4
处理器控制块结束 equ 当前执行的线程 +4

处理器控制表起始 equ 系统调用表起始 + 系统调用表大小
处理器控制表大小 equ 处理器控制块结束 * 4

进程控制块指针项起始 equ 0
 进程控制块指针 equ 进程控制块指针项起始 + 0
进程控制块指针项大小 equ 进程控制块指针 + 4

进程控制块指针表起始 equ 系统调用表起始 + 系统调用表大小
进程控制块指针表大小 equ 进程控制块指针项大小 * 10

进程控制块起始 equ 0
 进程页表指针 equ 进程控制块起始 + 0
 进程共享内存表指针 equ 进程页表指针 + 4
 进程打开文件表指针 equ 进程共享内存表指针 + 4
 共用内存块起始 equ 进程打开文件表指针 + 4
 共用内存块结束 equ 共用内存块起始 + 4
进程控制块大小 equ 共用内存块结束 + 4

进程控制表起始 equ 进程控制块指针表起始 + 进程控制块指针表大小
进程控制表大小 equ 进程控制块大小 * 10

线程控制块指针项起始 equ 0
 线程控制块指针 equ 线程控制块指针项起始 + 0
线程控制块指针项大小 equ 线程控制块指针 + 8

线程控制块指针表起始 equ 进程控制表起始 + 进程控制表大小
线程控制块指针表大小 equ 线程控制块指针项大小 * 10

线程控制块起始 equ 0
 RAX寄存器 equ 线程控制块起始 + 0
 RBX寄存器 equ RAX寄存器 + 8
 RCX寄存器 equ RBX寄存器 + 8
 RDX寄存器 equ RCX寄存器 + 8
 RSi寄存器 equ RDX寄存器 + 8
 RDi寄存器 equ RSi寄存器 + 8
 RBP寄存器 equ RDi寄存器 + 8
 RSP寄存器 equ RBP寄存器 + 8
 R8寄存器 equ RSP寄存器 + 8
 R9寄存器 equ R8寄存器 + 8
 R10寄存器 equ R9寄存器 + 8
 R11寄存器 equ R10寄存器 + 8
 R12寄存器 equ R11寄存器 + 8
 R13寄存器 equ R12寄存器 + 8
 R14寄存器 equ R13寄存器 + 8
 R15寄存器 equ R14寄存器 + 8
 RiP寄存器 equ R15寄存器 + 8
 RFLAGS寄存器 equ RiP寄存器 + 8
线程控制块大小 equ RFLAGS寄存器 + 8

线程控制表起始 equ 线程控制块指针表起始 + 线程控制块指针表大小
线程控制表大小 equ 线程控制块大小 * (10 * ( 进程控制表大小 / 10 ) )

预分配数据结构结束 equ 0+8



;初始化数据表结构
mov eax,0;清空TSS项的随机值
mov ecx,TSS项大小 * 2 / 8
mov edi,TSS表起始
rep stosq

mov qword[TSS表起始 + RSPDPL0 + TSS项大小 * 0],0x10000
;jmp $
;https://f.osdev.org/viewtopic.php?p=63014
mov rax,TSS表起始 + TSS项大小 * 0
mov word[TSS指针表起始 + initialize起始 + 0],TSS项大小 - 1;长度 - 1以忽略后1字节，因为计算机是从0开始计数的
mov [TSS指针表起始 + initialize起始 + 2],ax
shr rax,16;把EAX高位移下来
mov [TSS指针表起始 + initialize起始 + 4],al
mov	byte[TSS指针表起始 + initialize起始 + 5],10001001b;P，DPL，0，Type
mov byte[TSS指针表起始 + initialize起始 + 6],0;段属性和段长度
mov byte[TSS指针表起始 + initialize起始 + 7],ah
shr rax,16;把RAX高位移下来
mov [TSS指针表起始 + initialize起始 + 8],eax
mov dword[TSS指针表起始 + initialize起始 + 12],0;预留

mov ax,TSS指针表起始 - 全局描述表起始
ltr ax

;当表内中间的一项或多项条目释放后会产生空洞，需要移动内容来覆盖空洞，如果频繁移动会影响性能，我想可以新建另一个表来保存这些空洞的位置，下次写入表就直接往这些空洞里写，满一页合并这些内容以释放内存页
mov byte[系统调用表起始 + 系统调用项属性 + 系统调用项大小 * 1],1;进程属性
mov rax,cr3;第一个进程就是本进程
mov [系统调用表起始 + 系统调用进程页表指针 + 系统调用项大小 * 1],rax
mov qword[系统调用表起始 + 系统调用代码指针 + 系统调用项大小 * 1],调度中心的不常用的调用 + initialize起始;代码指针RiP
;mov dword[系统调用表末尾 + initialize起始],系统调用项大小 * 1
mov byte[系统调用项数量 + initialize起始],1 + 6

mov [进程控制块起始 + 进程页表指针 + 进程控制块大小 * 1],rax

;mov [线程控制块起始 + ],

mov [进程控制块起始 + 进程页表指针 + 进程控制块大小 * 1],rbx

mov qword[线程控制块起始 + RiP寄存器 + 线程控制块大小 * 2],4096

;mov qword[edi + 1],rax;调度中心的页表指针

;mov [edi - 8 * 2],rax;调度中心进程控制表指针


;mov qword[edi + 1],rbx;内存管理的页表指针
;mov eax,edi
;sub eax,[线程控制表起始 + initialize起始]
;mov [edi - 1 - 8 * 4 - 8],rax;内存管理进程控制表指针
;add edi,1 + 8 * 4
;mov [进程控制表结束 + initialize起始],edi


;add edi,(8 * 17 + 8) * 10
;mov [t线程控制表起始 + initialize起始],edi





;https://zhuanlan.zhihu.com/p/590066420 https://wiki.osdev.org/Segment_Selector https://github.com/dreamportdev/Osdev-Notes/blob/master/06_Userspace/02_Switching_Modes.md
;CPU为什么不直接使用描述符内的DPL，而是新增了RPL，历史遗留问题，我用了一晚上的时间才发现这问题
;我的理解是段描述符只标识了这个段的访问权限，其他进程有自己特权级和权限，当其他进程访问这个段时就需要他的特权级来判断是否能访问这个段
; SS（用户态栈段选择子）。
; RSP（用户态栈指针）。
; RFLAGS（用户态标志寄存器）。
; CS（用户态代码段选择子）。
; RIP（用户态返回地址）。
;push qword R3DATA - 全局描述表起始 + 3
;push qword 0x7c000
;pushfq
;push qword R3CODE - 全局描述表起始 + 3
;push qword sszzss + initialize起始
;iretq
;sszzss:
;nop
;push ax
;int 6
;ud2
;jmp $





jmp $


;复制跳转数据
mov esi,调度中心跳转头起始 + initialize起始
mov edi,0
mov cl,调度中心跳转头结束 - 调度中心跳转头起始
rep movsb
mov al,0;清零此段
mov cl,中断描述符表起始 - 切换页表 - (调度中心跳转头结束 - 调度中心跳转头起始)
rep stosb
mov esi,跳板起始 + initialize起始
mov edi,MemoryManager起始
mov cx,内核结束 - 跳板起始
rep movsb
mov qword[MemoryManager起始 + 最小页大小 - 24],最小页大小
mov rax,cr3
mov [MemoryManager起始 + 最小页大小 - 16],rax;调度中心的CR3
mov qword[MemoryManager起始 + 最小页大小 - 8],1;进程序号
mov r11d,ebx;内存管理进程的CR3
mov ecx,4096
mov esp,4096 - 40
jmp initialize起始 - initialize起始 - initialize起始








mov esi,[esp]
mov ecx,[esp + 4]
mov edi,进程控制表结束 + initialize起始

循环处理内存布局项表:
cmp dword[esi + 16],1;判断内存项类型是否为空闲
jnz 推进到下一个内存项

movsq
movsq
sub esi,16;消除上面两个movsq推动的esi然后由下面的add esi,20统一推动以配合从别处跳转来的指令

推进到下一个内存项:
add esi,20
cmp ecx,esi
jnz 循环处理内存布局项表











mov word[实模式代码的位置+initialize起始],fpfs
jmp 切换到实模式









;如果是发生中断但也是要进入系统调用入口，可是RAX并未被保存
;可以根据SS段寄存器的值，判断到如果是个固有的值则表示从中断进来需要将一些值复制到线程控制块，因此内核栈必须要跟调度中心共享内存，因为进入进程需要修改R11寄存器所以进入进程后也判断固有值，如果是中断栈还需要从栈里还原用户的R11
;如果出错则发生中断的进程将会损坏






保存线程上下文:
;我需要将所有寄存器存入线程控制块
;将会修改R11寄存器
;输入需要获取当前处理器核心的编号
;输出R11当前处理器核心的编号
mov cx,ss
cmp cx,0
;jz $

str r11d;获取TSS项序号






;将会修改RAX，RCX寄存器
;输入AX系统调用号，R11进程序号
;输出R11保存了RAX的原始值
;传递参数RBX，RDX，RSi，RDi，RBP，R8，R9，R10，R12，R13，R14，R15，R16，R17，R18
跳转到系统调用项:

mov r11,rax
movzx eax,ax

cmp rax,[系统调用项数量 + initialize起始];系统调用表结束 - 系统调用表起始/8
jae 输入的系统调用号大于系统调用项数量;大于等于则跳转

mov ecx,eax
shl eax,4;×16
add eax,ecx;×1
;add eax,[系统调用表起始+initialize起始]
movzx ecx,byte[eax];属性
jmp [ecx * 8 + 调用状态跳转表起始+initialize起始]

空闲的调用:
jmp $
jmp 切换到实模式

共用内存块:


jmp $


一般的调用:
mov rcx,[eax + 1];CR3
mov r11,[eax + 1 + 8];RiP
jmp initialize起始-initialize起始-initialize起始


挂起的调用:
jmp $


失效的调用:
jmp $



;将会修改EAX寄存器
;输入
;无输出
调度中心的不常用的调用:
cmp bl,1
ja $

movzx ebx,bl
jmp [ebx*8+调度中心不常用的调用表起始+initialize起始]

调度中心不常用的调用表起始:
dq 修改系统调用表+initialize起始



;将会修改AX，EBX，RCX，R11寄存器
;输入BX系统调用号，RDX进程页表，RSi进程调用入口点，R11进程序号
;输出AX返回值
修改系统调用表:
movzx ebx,bx;清空高位
mov r11d,ebx
shl r11d,4; × 16
lea ebx,[r11d + 系统调用表起始]; × 1 = × 17

cmp byte[ebx + 系统调用项属性],0 - 1;检测进程控制块是否可用
jz $

ltr cx
sub cx,全局描述表结束 - 全局描述表起始
shr cx,4; ÷ 16
movzx ecx,cx;清空高位
add ecx,处理器控制表起始

mov r11d,[ecx+ 当前执行的进程控制块指针]
mov r11d,[r11d + 进程页表指针]

mov [ebx + 系统调用进程页表指针],r11
mov [ebx+ 系统调用代码指针],rdx
mov byte[ebx + 系统调用项属性],2;设置本调用项状态
mov bx,0;系统调用返回值

mov ax,0;调度中心调用号
mov r11d,0
jmp initialize起始 - initialize起始 - initialize起始





输入的系统调用号大于系统调用项数量:
mov bx,1
jmp $





















;我需要使用共享内表来保存共享内存的状态吗
;我想我需要一个表来保存系统调用时的共享内存起始指针，用于传递参数
;然后其他的东西我不需要保存，让应用程序来自行管理自己的内存，因为共享内存跟普通内存没有太大区别，我只需要记录共享次数来决定是否释放即可
;


;申请共用内存，向目标程序申请共用内存，申请一块未申请过的内存然后向程序请求他的指定位置进行共用

创建共享内存块:
nop

jmp $






;当要煮东西时提前叫rn去洗东西





;二分查找树
;平衡二叉树


;
;
;
;虽然在这里每层页表的名字都被简化了，但在处理器上每层页表都有自己的名字和故事
;rol指令把最高bit移入最低bit并复制1份进CF标志位
VMMU:;手动实现mmu
mov ebx,0;清空RBX寄存器
;第1层页表
rol rax,16 + 9
mov bx,ax
and bh,0000_0001;清空不需要的位因为页表内寻址只需要9位
mov rcx,[rcx + rbx]
;test cl,0;检查存在位
;jz $
;第2层页表


;第3层页表
mov rdx,rcx
shr rdx,16


;第4层页表










;将会修改RCX寄存器
;输入RCX进程序号
;输出RCX页表指针
转到进程:
shl ecx,3;×8
add ecx,[进程控制项指针表起始+initialize起始]
mov rcx,[ecx]
cmp rcx,0 - 1;进程控制项是否可用
jz $

;add ecx,[线程控制表起始+initialize起始]
mov ecx,[ecx+1];读取页表指针
jmp initialize起始 - initialize起始 - initialize起始




;将会修改RAX，RCX，R11寄存器
;输入BX返回值，RDX返回地址，R11进程序号
;传递参数AX，RDX，RSi，RDi，RBP，R8，R9，R10，R12，R13，R14，R15，R16，R17，R18
系统调用返回:
shl r11d,3;×8
add r11d,[进程控制项指针表起始 + initialize起始]
mov r11,[r11d]
cmp rcx,0 - 1;进程控制项是否可用
jz $

;add ecx,[线程控制表起始 + initialize起始]
mov ecx,[ecx + 1];读取页表指针
mov ax,bx;返回值
mov r11,rdx;返回地址
jmp initialize起始 - initialize起始 - initialize起始










;
;
;
;
pushaq:;Push All Qword
将大部分用户寄存器保存到线程控制块:;
pushfq
push qword 0
push r15
push r14
push r13
push r12
push r11
push r10
push r9
push r8
push rsp
push rbp
push rdi
push rsi
push rdx
push rcx
push rbx
push rax
ret










bits 16
fpfs:


mov si,字符串_eax0e820hint15hisnotsupported
call 实模式打印
jmp $




























bits 64
调度中心跳转头起始:
mov cr3,r11
mov r11d,保存线程上下文 + initialize起始;跳转到系统调用项函数的指针-initialize起始;[系统调用入口点的指针 - 调度中心跳转头起始];调度处理代码指针的指针
jmp r11
调度中心跳转头结束:


跳板起始:
;跳转入口
;注意这不是内核而是进入调度中心的跳转头
;由于硬件限制我们必须要这个
;我想让处理器制造商增加一些直接进入调度中心的指令你觉得这可能吗
;@ychen

;内存布局
;0h~1000;Kernel.Bin


;org 0
;bits 64
;将会修改RiP，CR3寄存器
;输入R11=RiP
;无输出
切换页表:
mov cr3,r11


;从外部切换页表后会来到此处
pop r11
pushfq;不要修改别人的标志寄存器
cmp rcx,0;如果不为零则表示进入用户代码
jz 不使用外部传入的返回地址

mov [rsp + 16],rcx;替换为外部传入的返回地址

不使用外部传入的返回地址:
popfq
pop rcx
ret


;不会修改寄存器
;输入压栈返回地址
;输出RCX下一条指令的位置，R11D调度中心的CR3
系统调用入口:
cli;关中断
push rcx
mov rcx,[rsp + 8]
push r11
mov r11d,[最小页大小 -16];调度中心的CR3
jmp 切换页表


中断描述符表起始:;Interrupt Descriptor Table
dw 除法错误 - 16;int0处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 16;int0处理代码位置的中16位
dd 0;int0处理代码位置的高32位
dd 0;填充0

dw 0;int1处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int1处理代码位置的中16位
dd 0;int1处理代码位置的高32位
dd 0;填充0

dw 0;int2处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int2处理代码位置的中16位
dd 0;int2中断处理代码位置的高32位
dd 0;填充0

dw 0;int3处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int3处理代码位置的中16位
dd 0;int0处理代码位置的高32位
dd 0;填充0

dw 0;int4处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int4处理代码位置的中16位
dd 0;int4处理代码位置的高32位
dd 0;填充0

dw 0;int5处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int5处理代码位置的中16位
dd 0;int5处理代码位置的高32位
dd 0;填充0

dw 未定义的操作码 - 16;int6处理代码位置的低16位
dw 长模式代码段 - 全局描述表起始;段选择子
dw 08e00h;属性
dw 16;int6处理代码位置的中16位
dd 0;int6处理代码位置的高32位
dd 0;填充0

dw 0;int7处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int7处理代码位置的中16位
dd 0;int7处理代码位置的高32位
dd 0;填充0

dw 双重错误;int8处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int8处理代码位置的中16位
dd 0;int8处理代码位置的高32位
dd 0;填充0

dw 0;int9处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int9处理代码位置的中16位
dd 0;int9处理代码位置的高32位
dd 0;填充0

dw 无效的TSS段;int10处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int10处理代码位置的中16位
dd 0;int10处理代码位置的高32位
dd 0;填充0

dw 段不存在 - 16;int11处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 16;int11处理代码位置的中16位
dd 0;int11处理代码位置的高32位
dd 0;填充0

dw 栈段故障 - 16;int12处理代码位置的低16位
dw 16;段选择子
dw 0ee00h;属性
dw 16;int12处理代码位置的中16位
dd 0;int12处理代码位置的高32位
dd 0;填充0

dw 一般性保护错误;int13处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int13处理代码位置的中16位
dd 0;int13处理代码位置的高32位
dd 0;填充0

dw 页错误;int14处理代码位置的低16位
dw 16;段选择子
dw 0ee00h;属性
dw 0;int14处理代码位置的中16位
dd 0;int4处理代码位置的高32位
dd 0;填充0

dw 0;int15处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int15处理代码位置的中16位
dd 0;int15处理代码位置的高32位
dd 0;填充0

dw 0;int16处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int16中断处理代码位置的中16位
dd 0;int16处理代码位置的高32位
dd 0;填充0

dw 0;int17处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int17处理代码位置的中16位
dd 0;int17处理代码位置的高32位
dd 0;填充0

dw 0;int18处理代码位置的低16位
dw 0;段选择子
dw 0;属性
dw 0;int18处理代码位置的中16位
dd 0;int18处理代码位置的高32位
dd 0;填充0

dw 0;int19处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int19处理代码位置的中16位
dd 0;int19处理代码位置的高32位
dd 0;填充0

dw 0;int20处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int20处理代码位置的中16位
dd 0;int20处理代码位置的高32位
dd 0;填充0

dw 0;int21处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int21处理代码位置的中16位
dd 0;int21处理代码位置的高32位
dd 0;填充0

dw 0;int22处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int22处理代码位置的中16位
dd 0;int22处理代码位置的高32位
dd 0;填充0

dw 0;int23处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int23处理代码位置的中16位
dd 0;int23处理代码位置的高32位
dd 0;填充0

dw 0;int24处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int24处理代码位置的中16位
dd 0;int24处理代码位置的高32位
dd 0;填充0

dw 0;int25处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int25处理代码位置的中16位
dd 0;int25处理代码位置的高32位
dd 0;填充0

dw 0;int26处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int26处理代码位置的中16位
dd 0;int26处理代码位置的高32位
dd 0;填充0

dw 0;int27处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int27处理代码位置的中16位
dd 0;int27处理代码位置的高32位
dd 0;填充0

dw 0;int28处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int28处理代码位置的中16位
dd 0;int28处理代码位置的高32位
dd 0;填充0

dw 0;int29处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int29处理代码位置的中16位
dd 0;int29处理代码位置的高32位
dd 0;填充0

dw 0;int30处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int30处理代码位置的中16位
dd 0;int30处理代码位置的高32位
dd 0;填充0

dw 0;int31处理代码位置的低16位
dw 16;段选择子
dw 8e00h;属性
dw 0;int31处理代码位置的中16位
dd 0;int处理代码位置的高32位
dd 0;填充0
中断描述符表结束:


除法错误:;#DE
mov eax,8
;jmp 调度中心_系统调用

未定义的操作码:;#UD
mov eax,9
jmp 系统调用入口

双重错误:;#DF
mov eax,10
jmp 系统调用入口

无效的TSS段:;#TS
mov eax,11
jmp 系统调用入口

段不存在:;#NP
mov eax,12
jmp 系统调用入口

栈段故障:;#SS
mov eax,13
jmp 系统调用入口

一般性保护错误:;#GP
mov eax,14
jmp 系统调用入口

页错误:;#PF
mov eax,15
jmp 系统调用入口
内核结束:


;处理64位的错误中断
bits 64
int0:
mov si,字符串_除法错误
jmp 打印处理器的异常

int6:
mov si,字符串_未定义的操作码
jmp 打印处理器的异常

int8:
mov si,字符串_双重错误
jmp 打印处理器的异常

int10:
mov si,字符串_无效的TSS段
jmp 打印处理器的异常

int11:
mov si,字符串_段不存在
jmp 打印处理器的异常

int12:
mov si,字符串_栈段故障
jmp $;打印处理器的异常

int13:
mov si,字符串_一般性保护错误
jmp 打印处理器的异常

int14:
mov si,字符串_页错误



打印处理器的异常:
mov word[实模式代码的位置+initialize起始],打印后进入长模式
mov dword[ContinueAddress],切换到实模式后暂停处理器+initialize起始
jmp 切换到实模式

切换到实模式后暂停处理器:
mov word[实模式代码的位置+initialize起始],在实模式暂停处理器
jmp 切换到实模式























bits 16
打印后进入长模式:
call 实模式打印
jmp 切换到长模式












;如 ACPI 规范中所述，要查找 ACPI RSDT，请在 EBDA 中查找“RSD PTR”，如果不存在，则每 16 个字节搜索 0e0000h-0fffffh。它包含一个指向偏移量 12 处的 RSDT 的指针

不支持eax0e820hint15h:
;80h 无效命令 (PC,PCjr)
;cmp ah,86h;不支持 86h 功能 (XT)
mov si,字符串_eax0e820hint15hisnotsupported
call 实模式打印
jmp 在实模式暂停处理器

字符串_eax0e820hint15hisnotsupported db 13,10,"BIOS doesn't support Int15h AX = E820h",0


eax0e820hint15h发生错误:
mov si,字符串_eax0e820hint15hAnerroroccurred
call 实模式打印
jmp 在实模式暂停处理器

字符串_eax0e820hint15hAnerroroccurred db 13,10,'EAX 0e820h int 15h An error occurred',0






;将会修改EAX，ECX，EDX，CS，DS，ES，FS，GS，SS，ESP，GDTR，iDTR，CR0，CR4寄存器
;输入ContinueAddress长模式跳转地址
;输出
;https://wiki.osdev.org/Talk:Entering_Long_Mode_Directly
切换到长模式:
;mov ax,0
;mov ds,ax
;mov es,ax
;mov fs,ax
;mov gs,ax
;mov ss,ax

mov eax,cr4
or eax,1010_0000b;启用物理地址扩展PhysicalAddressExtension，PGE
mov cr4,eax
mov ecx,0c0000080h;EFER MSR
rdmsr;将会修改EAX和EDX寄存器
or eax,1_00000000b;启用长模式
wrmsr
mov eax,cr0
or eax,1000000000000000_0000000000000001b;通过同时启用PG分页和PE保护
cli;拒收硬件中断
mov cr0,eax
lgdt cs:[全局描述表指针];设置全局描述符表
jmp dword 长模式代码段 - 全局描述表起始 : LongMode + initialize起始

bits 64
LongMode:
mov ax,0;长模式数据段 - 全局描述表起始
;mov ds,ax
;mov es,ax
;mov fs,ax
mov ecx,ss;转换成64位长模式的栈值
shl ecx,4;× 16
movzx esp,sp;清空高位
add esp,ecx;加上段地址
;mov gs,ax
;mov ss,ax

lidt [长模式中断描述符表指针 + initialize起始];我迫切地需要知道发生什么错误
jmp qword[rel + ContinueAddress]

ContinueAddress dd 0,0


;将会修改EAX，ECX，CS，DS，ES，FS，GS，SS，ESP，iDTR，CR0，CR4寄存器
;输入实模式代码的位置即跳转地址
;无输出
;https://wasm.in/threads/perexod-v-long-mode-i-obratno.29057/ https://board.flatassembler.net/topic.php?p=165470 https://github.com/reactos/reactos/blob/master/boot/freeldr/freeldr/arch/amd64/entry.S
切换到实模式:
;mov ax,实模式数据段 - 全局描述表起始
;mov ds,ax
;mov es,ax
;mov fs,ax
;mov gs,ax

jmp dword far [rel 兼容保护模式代码指针];nasm.exe编译器不支持jmp fword ptr [mem]这个写法，我先用其他编译器把这个写法编译成二进制文件，然后用ndisasm.exe反编译就得到了nasm.exe所支持的写法

bits 32
从保护模式切换到实模式:
;jmp $;注意 使用ida连接VMware时会在此处丢失单步跟踪，在此处使用jmp $即可解决
mov eax,cr0
and eax,01111111_11111111_11111111_11111111b;禁用内存分页
mov cr0,eax
jmp 实模式代码段 - 全局描述表起始 : RealModeEntryPoint

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
jmp word initialize起始/段地址乘数:InRealMode;清除预取队列并纠正CS

InRealMode:
;mov ax,cs;initialize起始/16
;mov ds,ax
;mov es,ax
;mov fs,ax
;mov gs,ax
;mov ss,ax
cmp esp,10FFeFh
ja $;大于则跳转

cmp esp,0F0000h
ja 不能使用单一段值;大于则跳转

mov eax,esp;转换成16位实模式的栈值
mov edx,0
mov ecx,edx;保存EDX的值
mov esp,10000h
div esp;EDX高：EAX低 ÷ ESP = EAX … EDX
shl ax,12;左移12位来补12个0，把1变成1000
mov ss,ax;商作为SS段
mov esp,edx;余数作为ESP偏移，顺便清空高位
mov edx,ecx;还原EDX的值
jmp 栈已转换成实模式的

不能使用单一段值:
mov ax,0FFFFh;需要使用下面的3个F了
mov ss,ax
sub esp,0FFFF0h;减去段地址

栈已转换成实模式的:
lidt [中断向量表指针];16位的中断描述符表
sti;接收硬件中断
jmp word[实模式代码指针]















;将会修改AX，BH，Si寄存器
;输入DS：Si带结束符的字符串位置
;输出
实模式打印:
mov ah,14;0E功能号
mov bh,0;页码
;BL = 前景色（仅限图形模式）
jmp 插入_3

继续实模式的打印:;每个指令都很重要确保他们被正确执行
 int 10h;中断号

 插入_3:
 lodsb;将DS：Si指向的内容放入AL然后Si+1
 cmp al,0
jnz 继续实模式的打印

ret


在实模式暂停处理器:
 ;cli;关中断会导致有些虚拟机报错
 hlt
jmp short 在实模式暂停处理器


;将会修改EAX，Di寄存器
;输入ES：Di中断描述符的写入位置，EAX中断处理代码的位置，BX段选择子，DX本中断描述符的属性
;输出
;制作_64位模式的中断描述符:
;stosw;中断处理代码位置的低16位
;mov ax,bx;段选择子
;stosw
;mov ax,dx;属性
;stosw
;shr eax,16;移下来
;stosw;中断处理代码位置的中16位
;mov eax,0;EAX已被清空
;stosd;我们没使用到的中断处理代码位置的高32位
;stosd;填充0
;ret

代码结束:



常量起始:

Message_NoCpuidSupport db 13,10,"The system doesn't support cpuid",0
Message_NoLongMode db 13,10,'Long mode is not supported',0;ZealOS requires a 64-bit capable processor.
字符串_间隔 db 13
字符串_回车加换行 db 13
字符串_换行 db 10,0
字符串_除法错误 db 13,10,'Division Error',0
字符串_未定义的操作码 db 13,10,'Undefined Opcode Exception',0
字符串_双重错误 db 13,10,'Double Fault',0
字符串_无效的TSS段 db 13,10,'Invalid TSS',0
字符串_段不存在 db 13,10,'Segment Not Present',0
字符串_栈段故障 db 13,10,'Stack-Segment Fault',0
字符串_一般性保护错误 db 13,10,'General Protection Fault',0
字符串_页错误 db 13,10,'Page Fault',0
路径_OSHAL db 'OPERATING SYSTEM/HARDWARE ABSTRACTION LAYER/',0
文件名_MEM db 'MEMORYMANAGER.BIN',0


全局描述表指针:;Global Descriptor Table
dw 全局描述表结束 - 全局描述表起始 - 1;长度-1以忽略后1字节，因为计算机是从0开始计数的
dd 全局描述表起始 + initialize起始;idt的位置

;https://wiki.osdev.org/Global_Descriptor_Table
;align 8
全局描述表起始:
dw 0000h,0000h,0000h,0000h;空描述符
长模式代码段 dw 0000h,0000h,9b00h,0020h;长模式cs
R0DATA dq 0x00cf93000000ffff
;长模式数据段 dw 0000h,0000h,9300h,0000h;长模式ds
兼容保护模式代码段 dw 0FFFFh,0000h,9b00h,00cFh;兼容保护模式cs

实模式代码段:;dw 0FFFFh,0FFF0h,9F0Fh,0000h;实模式cs
dw 0FFFFh;段界限，段长度
db 0F0h,0FFh,0Fh;注意，基地址，段起始
db 9Fh;10011111b;段属性
db 0;1100_1111b;段属性_段长度，段界限1111b
db 0;段基址，段起始00h

;实模式数据段:;dw 0FFFFh,0000h,9300h,0000h;实模式ds
;dw 0FFFFh;段界限，段长度
;db 00,00,00;注意，基地址，段起始
;db 93h;10010011b;段属性
;db 0;1100_1111b;段属性_段长度，段界限1111b
;db 0;段基址，段起始00h
R3DATA dq 0x0020F30000000000;0x00cff3000000ffffULL
R3CODE dq 0x0020Fb0000000000
dq 0
TSS指针表起始:
dq 0,0;由2个描述符组成的1个TSS描述符
全局描述表结束:



调用状态跳转表起始:
dq 空闲的调用 + initialize起始
dq 共用内存块 + initialize起始
dq 一般的调用 + initialize起始
dq 挂起的调用 + initialize起始
dq 失效的调用 + initialize起始
dq 创建共享内存块 + initialize起始
调用状态跳转表结束:


兼容保护模式代码指针:
dd 从保护模式切换到实模式 + initialize起始
dw 兼容保护模式代码段 - 全局描述表起始

实模式代码指针:
实模式代码的位置 dw 0

中断向量表指针:;Interrupt Vector Table
dw 256 * 4 - 1;实模式有256个中断项，每个项的长度为4byte，别忘了-1byte
dd 0;起始于0结束于3FF

长模式中断描述符表指针:
dw 中断描述符表结束 - 中断描述符表起始 - 1
dq 中断描述符表起始 + initialize起始

常量结束:



_空值变量起始:
长模式中断表信息的位置:
长模式中断表长度 equ 长模式中断表信息的位置 + 0
长模式中断表位置 equ 长模式中断表长度 + 2
系统调用项数量 equ 长模式中断表位置+8
系统调用表末尾指针 equ 系统调用项数量+8
;设置系统调用 dd 0;程标识符
;dq 0;程标识符RiP
;系统调用表末尾指针 equ 系统调用表起始+4
进程控制项指针表起始 equ 系统调用表末尾指针
进程标识表结束 equ 进程控制项指针表起始+4
线程控制表末尾指针 equ 进程标识表结束
进程控制表结束 equ 线程控制表末尾指针 + 4
共享内存表起始 equ 进程控制表结束 + 4

_空值变量结束:



_堆起始 equ _空值变量结束+4
;堆布局
;Kernelinitialize.Bin内存页表
;Kernelinitialize.Bin中断描述符表64

;内存布局表
;MemoryManager内存页表
;系统调用表
;进程控制表
;共享内存表





