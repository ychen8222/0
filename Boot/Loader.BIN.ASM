;============================================================================
;这是个加载程序，也就是引导的第二阶段
;我不会使用一些不直观的指令比如，xor ax,ax
;2023年
;该死的win系统损坏，害得我丢失亿些东西，只能重新写了
;----------------------------------------------------------------------------
;内存布局
;90000～9FFFF_Loader.BIN
call 自定位
自定位 pop si
sub si,自定位
push si
add si,DOSstart
;shl ax,4;段转偏移
;add ss:[esp],ax;为什么必须要ESP
mov ax,cs
mov ds,ax;ds=cs
mov ax,9000h;复制到的位置
mov es,ax
mov di,0

in al,92h;别忘了打开A20
or al,10b
out 92h,al

mov cx,DOSEnd-DOSstart
mov al,cl;save
shr cx,2;除以4，以便最高效复制
rep movsd;如果CX为0则什么都不操作
mov cl,al;恢复
and cl,11b;只保留低二位
rep movsb;如果CX为0则什么都不操作

mov ax,0;ds，es段寄存器已被占用
mov fs,ax
mov ax,9000h

mov fs:[36h],ax;现在写入我们的中断程序
mov bx,int8-DOSstart;加上我们的基地址10h
mov fs:[34h],bx

mov fs:[86h],ax
mov bx,int21-DOSstart
mov fs:[84h],bx

mov fs:[2h],ax
mov bx,int0-DOSstart
mov fs:[0h],bx

mov es:[驱动器号-DOSstart],dl;保存驱动器号
cmp bp,0aa55h;由我们的引导扇区过传来的判断数
jnz 无法确定文件系统类型
cmp dh,2
ja 无法确定文件系统类型;大于则跳转


movzx bx,dh;由我们的引导扇区过传来的文件系统编号
shl bx,1;×2
add bx,文件系统类型表_1
pop bp;弹基地址
add bx,bp
mov bx,[bx]
add bx,bp;加基地址
jmp bx

文件系统类型表_1:
dw 无法确定文件系统类型
dw iso9660_1


iso9660_1:
mov byte es:[文件系统编号-DOSstart],1
mov word es:[扇区大小-DOSstart],2048
mov eax,fs:[7c00h+3]
mov es:[当前目录簇号-DOSstart],eax
mov eax,fs:[7c00h+3+4]
mov es:[iSO9660目录长度-DOSstart],eax

mov ax,9000h
mov es,ax
mov word[第一个文件名+bp],Boot+2
mov word[第二个文件名+bp],BOOT+2
mov word[文件名长度+bp],4
call 获取文件项
jc $

mov bx,5;设置文件系统参数
int 21h
dec si
dec si
call 打印

mov word[第一个文件名+bp],Command
mov word[第二个文件名+bp],COMMAND
mov word[文件名长度+bp],11
call 获取文件项
jc $

mov bx,5;设置文件系统参数
int 21h
call 打印

没有找到_1:
push ax
mov ax,9000h
mov es,ax
mov ds,ax
pop ax
call 显示寄存器
jmp $




获取文件项:
mov bx,4;获取一个文件项
int 21h
jc 没有找到
cmp dx,word[文件名长度+bp]
jnz 获取文件项;没有找到


mov si,[第一个文件名+bp]
add si,bp
mov [原CX值+bp],cx
mov cx,[文件名长度+bp]
push di;下一轮还需要
rep cmpsb
pop di
mov si,[第一个文件名+bp]
jz 找到了


cmp word[第二个文件名+bp],0
jz 获取文件项;没有段文件名
mov si,[第二个文件名+bp]
add si,bp
mov cx,[文件名长度+bp]
rep cmpsb
mov si,[第二个文件名+bp]
jnz 获取文件项;没有找到
没有找到:
找到了:
mov cx,[原CX值+bp]
add si,bp
ret


第一个文件名 dw 0
第二个文件名 dw 0
原CX值 dw 0
文件名长度 dw 0

Boot db 13,10,'Boot/',0
BOOT db 13,10,'BOOT/',0
Command db 'Command.BIN',0
COMMAND db 'COMMAND.BIN',0





无法确定文件系统类型:
jmp 8000h:0h;进入命令处理程序





DOSstart:;Disk Operating System
int21:
mov cs:[0FFFbh],eax;保
pop eax;弹cs+ip
inc sp;删压的标志位，注意栈只能压word
inc sp
push eax;压返回地址
mov eax,cs:[0FFFbh];原

mov cs:[0FFF9h],ss
mov cs:[0FFF7h],sp;保存原栈
mov sp,9000h
mov ss,sp
mov sp,0FFF7h
push ds

shl bx,1;×2
cmp bx,4*2
stc;设置进位
ja 返回;大于则跳转
add bx,功能-DOSstart
mov bx,cs:[bx]
jmp bx

功能:
dw 0;null，错误处理
dw 获取文件系统编号-DOSstart
dw 修改文件系统编号-DOSstart

dw 设置重新读取文件扇区-DOSstart
dw 获取一个文件项-DOSstart
dw 设置文件系统参数-DOSstart


;输出
;BX >文件系统编号
获取文件系统编号:
movzx bx,cs:[文件系统编号-DOSstart]
jmp 返回

;输入
;BL >文件系统编号
修改文件系统编号:
mov cs:[文件系统编号-DOSstart],bl
jmp 返回

文件系统编号 db 0



;输入
;无
设置重新读取文件扇区:
mov byte cs:[重置读取-DOSstart],1
jmp 返回

;输入
;无
;输出
; >文件参数
获取一个文件项:
movzx bx,cs:[文件系统编号-DOSstart]
shl bx,1;×2
add bx,文件系统-DOSstart
cmp bx,3*2
stc;设置进位
ja 返回;大于则跳转
push 9000h;不要用寄存器赋值，以免破坏传递的参数
pop ds;段地址，int13ah42的DS：SI，磁盘参数块需要
mov bx,[bx]
jmp bx

文件系统:
dw 0;null，错误处理
dw iSO9660-DOSstart
dw FAT32_1-DOSstart
;dw -DOSstart



;输入
;无
;输出
;EAX >LBA
;ECX >扇区数据长度
;DX >文件名长度
;9000h：DI >文件名
iSO9660:
cmp byte [重置读取-DOSstart],0;标志
jz 不要重置
mov byte [重置读取-DOSstart],0;设置为0下次就不会重新读文件扇区了
mov eax,[当前目录簇号-DOSstart]
mov [LBA-DOSstart],eax

mov eax,[iSO9660目录长度-DOSstart]
mov edx,0;清空除法高位
movzx ebx,word [扇区大小-DOSstart]
div ebx;edx高：eax低÷ebx =eax……edx
cmp dx,0
jz 没有超出_2;超出一个字节都需要读完整个扇区
inc ax
没有超出_2 mov [循环次数-DOSstart],ax
mov word [当前扇区偏移量-DOSstart],0FFFFh

不要重置:
mov di,[当前扇区偏移量-DOSstart]
mov ax,DOSEnd-DOSstart
add ax,[扇区大小-DOSstart]
cmp di,ax;当前扇区处理完了吗
jb 取一个项;小于则跳转

读下一个扇区:
cmp word [循环次数-DOSstart],0
jnz 还没读完
mov byte [重置读取-DOSstart],1;下次则从头开始
stc;设置进位
jmp 返回

还没读完:
dec word [循环次数-DOSstart]
mov eax,[LBA-DOSstart]
inc dword [LBA-DOSstart];推进到下一个扇区
mov edx,0;清空LBA高位
mov ebx,9000_0000h;缓存区，段地址
mov bx,DOSEnd-DOSstart;偏移地址，在此处放置扇区
call 读盘
add bx,[bx];跳过一个.目录
add bx,[bx];跳过一个..目录
mov di,bx
mov [当前扇区偏移量-DOSstart],di

取一个项:
cmp word [di],0;这个项的长度为0则
jz 读下一个扇区;触底
mov ax,[di];取这个项的长度
add [当前扇区偏移量-DOSstart],ax;加进偏移量
mov eax,[di+2];2双端格式的范围位置 (LBA)，2~8÷2
mov ecx,[di+10];双端格式的数据长度（范围大小）
add di,33;指向文件名长度
movzx dx,byte [di-1];取文件名长度
clc;清除进位
jmp 返回







;输入
;无
;输出
; >文件参数
设置文件系统参数:
movzx bx,cs:[文件系统编号-DOSstart]
shl bx,1;×2
add bx,文件系统_1-DOSstart
cmp bx,3*2
stc;设置进位
ja 返回;大于则跳转
mov bx,cs:[bx]
jmp bx

文件系统_1:
dw 0;null，错误处理
dw iSO9660_1-DOSstart
dw FAT32_1-DOSstart
;dw -DOSstart




;输入
;无
;输出
; >文件参数
iSO9660_1:
mov cs:[当前目录簇号-DOSstart],eax
mov cs:[iSO9660目录长度-DOSstart],eax
mov byte cs:[重置读取-DOSstart],1
jmp 返回







重置读取 db 1
LBA dd 0
循环次数 dw 0
当前扇区偏移量 dw 0









;输入
;DS：SI >文件名位置
;CX >文件名长度
;输出
;EAX >LBA
FAT32_1:
mov word cs:[bp+目录项序号-DOSstart],0
;mov ax,[bp+路径缓存区结束-DOSstart]
add ax,[bp+扇区大小-DOSstart]
mov [bp+单个扇区目录项临时缓存结束-DOSstart],ax;用于快速进入目录



mov eax,[bp+当前目录簇号-DOSstart]
call 簇转LBA

下一个扇区_32:

mov bx,0FFFFh
shl ebx,16;《段地址移到高位
mov bx,[bp+单个扇区目录项临时缓存结束-DOSstart];在此之后放置目录项扇区
mov cx,0
mov edx,0;清空LBA高位
call 读盘

mov di,[bp+单个扇区目录项临时缓存结束-DOSstart]
sub di,32
不正常的项:
add di,32
mov ax,[bp+单个扇区目录项临时缓存结束-DOSstart]
add ax,[扇区大小]
cmp di,ax
jz 下一个扇区_32

cmp byte cs:[di],0e5h
jz 不正常的项





cmp byte cs:[di+12],0Fh;检测是否为长文件名
jnz 短文件名

cmp byte cs:[di],40h
;jb ;小于则跳转






push di

inc word cs:[bp+目录项序号-DOSstart]

mov di,cs:[bp+扇区大小-DOSstart]
shl di,1;×2
add di,[bp+单个扇区目录项临时缓存结束-DOSstart]
mov eax,0
mov ax,cs:[bp+目录项序号-DOSstart]











短文件名:

add di,32;20h，DI指向下一个文件条目的32字节结构体开头处











;EAX，EBX，EDX，DI寄存器将会被修改
;输入
;EAX >待转换数值
;ES：DI >缓存区
;输出
;ES：DI >10进制ascall码，结尾为0，注意倒序应使用std指令
;除法
;ax÷bl =al……ah，被除数÷除数 =商……余数
;Edx高：Eax低÷Ebx =Eax……Edx
二进制转十进制ascall码:
mov bl,al
mov al,0;用于标记结束
stosb
mov al,bl

mov ebx,10
不为零则跳转:
 mov edx,0
 div ebx;一直除以10
 add dl,'0';此0非彼0
 xchg al,dl;只要余数
 stosb;存入
 mov al,dl;恢复AL，保护被除数

 cmp eax,0
jnz 不为零则跳转
ret


;EAX，EBX，ECX，SI寄存器将会被修改
;输入，非数字符会发生？
;ES：SI >字符串，需带结束符
;输出
;EAX >数值
十进制ascall码转二进制:
mov eax,0;清空高位，防止错误
lodsb;这是最高位

sub al,'0';转换为数值
movzx ebx,byte [si];不能使用lodsb指令了，因为这会破坏我们的数值
inc si;推进到下一个字符
cmp bl,0;不为0则给下面用
jz 注意只有个位数;不能×10

不为零则跳转_1:
mov ecx,eax
shl eax,3;×8
jc 注意只有个位数;会触发溢出吗
add eax,ecx
add eax,ecx;+×2

sub bl,'0';转换为数值
add eax,ebx;加上个位数

movzx ebx,byte [si];不能使用lodsb指令了，因为这会破坏我们的数值
inc si;推进到下一个字符
cmp bl,0
jnz 不为零则跳转_1
注意只有个位数:
ret








;EAX，EBX寄存器将会被修改
;输入
;EBX >待转换数值
;DS：DI >缓存区
;输出
;DS：DI >16进制ascall码，结尾为0，注意倒序应使用std指令
二进制转十六进制ascall码:
 mov al,bl
 shr ebx,4;显示了一位
 and al,00001111b;只保留低四位
 cmp al,10;是字母
 jb 小于则跳转
 add al,7;补齐，数字到字母之间隔了几个符号
 小于则跳转 add al,'0';此0非彼0
 stosb;存入
 cmp ebx,0
jnz 二进制转十六进制ascall码
ret


;EAX，SI，DI寄存器将会被修改
;输入
;DS：SI >字符
;输出
;ES：DI >缓存区
UTF16转UTF8:
不为零则跳转_这里有问题:
lodsw;读取一个UTF16字符
cmp ax,0
jz UTF16转换结束

xchg al,ah;大端存储转小端存储
cmp eax,127;7Fh，只含ascll
ja 大于则跳转_不是英文
stosb;直接写入al即可
jmp UTF16转UTF8;继续转换

大于则跳转_不是英文:
stc;设置进位表示遇到错误的字符
UTF16转换结束:
ret


;AX，SI，DI寄存器将会被修改
;输入
;DS：SI >字符
;输出
;ES：DI >缓存区
UTF8转UTF16:
lodsb;读取一个UTF8字符
cmp al,0
jz UTF8转换结束
shl ax,8;移动到AH
stosw
jmp UTF8转UTF16;继续转换



stc
UTF8转换结束:
ret



当前目录簇号 dd 0
iSO9660目录长度 dd 0
目录项序号 dw 0
单个扇区目录项临时缓存结束 dw 0






实现_drvnum:














返回:
pop ds
pop sp
mov ss,cs:[0FFF9h];还原栈
retf;iret是int指令专用返回

;将会修改DX，SI寄存器
;从硬盘读取一个扇区数据
;输入
;EAX >LBA低32位
;EDX >LBA高32位
;EBX >高32位段地址+低32位偏移地址
;输出
;EBX >目标位置
读盘:;读硬盘调用+增加dpa包是加扇区
mov cs:[偏移地址-DOSstart],ebx;低位段地址，高位偏移地址
mov cs:[LBA低位-DOSstart],eax
mov cs:[LBA高位-DOSstart],edx
mov si,参数块-DOSstart
mov dl,cs:[驱动器号-DOSstart]
mov ah,42h;扩展调用
int 13h
;jmp $
ret

驱动器号 db 0
扇区大小 dw 0

参数块:
db 16;[0]参数块大小
db 0;[1]保留，必须为0
db 1;[2]要传输的块数0~127
db 0;[3]保留，必须为0
偏移地址 dw 0;[4]
段地址 dw 0;[6]
LBA低位 dd 0;[8]低32位
LBA高位 dd 0;[12]高32位



;将会修改EAX,EDX寄存器
;输入
;EAX >目标簇号
;输出
;EAX >LBA号
;EDX >簇占用的扇区数
;如果链表末端则设置进位，EAX，EDX不变，链表结束
;乘法
;al×bl =ax，被乘数×被乘数 =积
;Eax×Edx =Edx高：低Eax
簇转LBA:
cmp eax,0FFFFFF8h;如果链表结束
jae 链表末端;等于大于则跳转，这是簇链的结束标志

;（簇号-2）×每个簇占用的扇区数+数据区起始扇区号 =簇的LBA号
dec eax
dec eax

movzx edx,byte ds:[每个簇占用的扇区数];使用扩位传送覆盖DX的高位以进行32位乘法
push dx;只有这个寄存器未被使用
mul edx;EDX是乘法的高位但我们不允许EAX溢出到高位
pop dx;不用压桟edx以节省空间

add eax,dword ds:[数据区起始];数据区起始扇区号
ret;此时进位未设置，除非参数错误

链表末端:
stc;通过进位表示结束
ret

每个簇占用的扇区数 db 0
数据区起始 dd 0




继续打印:;每个指令都很重要确保他们被正确执行
 xor bx,bx
 mov ah,14;BIOS中断参数
 int 10h;显示字符

 打印:
 lodsb;将DS：SI指向的内容放入al然后SI+1
 or al,al;判断al中的字符值是否 =0
jnz 继续打印
ret







int8:;下次支持其他段寄存器
push eax
push bp
pushf
mov bp,Gdtinfo-DOSstart

in al,92h;打开A20
or al,10b
out 92h,al

lgdt cs:[bp];读入GDT长度及位置
mov eax,cr0
or al,1b
cli
mov cr0,eax
jmp 8:pmode-DOSstart
pmode:
mov bp,16
mov gs,bp
and al,11111110b
mov cr0,eax
jmp 0FFFFh:unreal-DOSstart
unreal:
popf;不需要sti
pop bp
pop eax
retf

Gdtinfo:
dw GdtEnd-GdtStart-1;长度-1以忽略后一字节
dd GdtStart-DOSstart+0FFFFh
GdtStart:
dq 0h
db 0xff, 0xff, 0, 0, 0, 10011010b, 00000000b, 0
db 0xff, 0xff, 0, 0, 0, 10010010b, 11001111b, 0
GdtEnd:


int0:
mov si,除法错误-DOSstart
push ax
push bx
call 打印
pop bx
pop ax
call 显示寄存器
jmp DOSstart
除法错误 db 10,'Division error',13,0



;将会修改EAX，EBX，EDX，DI寄存器
;输入
;EAX >
;输出
;EAX >
;EDX >
显示寄存器:
push edi
mov di,DOSEnd-DOSstart+2048;在此处放置转换的ascall码
push eax
push ebx
push ecx
push esi
mov ax,0a00h;结束符
stosw

mov ebx,ebp
call 二进制转十六进制ascall码
mov si,_EBP寄存器-DOSstart
mov cx,7
rep movsb

mov ebx,esp
add ebx,20;减去我们在栈里压的一些东西
call 二进制转十六进制ascall码
mov si,_ESP寄存器-DOSstart
mov cx,7
rep movsb

mov ebx,dword [esp+16];EDI的值
call 二进制转十六进制ascall码
mov si,_EDI寄存器-DOSstart
mov cx,7
rep movsb

pop ebx;ESI的值
call 二进制转十六进制ascall码
mov si,_ESI寄存器-DOSstart
mov cx,7
rep movsb

mov ebx,edx
call 二进制转十六进制ascall码
mov si,_EDX寄存器-DOSstart
mov cx,7
rep movsb

pop ebx;ECX的值
call 二进制转十六进制ascall码
mov si,_ECX寄存器-DOSstart
mov cx,7
rep movsb

pop ebx;原EBX的值
call 二进制转十六进制ascall码
mov si,_EBX寄存器-DOSstart
mov cx,7
rep movsb

pop ebx;EAX的值
call 二进制转十六进制ascall码
mov si,_EAX寄存器-DOSstart
mov cx,6
rep movsb
add sp,4;栈平衡

mov si,di
dec si;减一以免取到下一个字符
std
call 打印
cld;恢复正序
ret

_EBP寄存器 db '> PBE  '
_ESP寄存器 db '> PSE  '
_EDI寄存器 db '> iDE',10,13
_ESI寄存器 db '> iSE  '
_EDX寄存器 db '> XDE  '
_ECX寄存器  db '> XCE  '
_EBX寄存器 db '> XBE  '
_EAX寄存器 db '> XAE',10









DOSEnd:








