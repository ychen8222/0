;============================================================================
;集成文件系统
;垃圾NASM编译器不支持双org，需要额外计算相对位置
;我不会使用一些不直观的指令比如，xor ax,ax\
@cya

;2023年
;该死的Win系统损坏，害得我丢失亿些东西，只能重新写了\
@cya
;----------------------------------------------------------------------------

;内存布局
DOS段地址 equ 60000h;～DOS结束=Loader.Bin
缓存区_1 equ 数据结束;～6FFFF
缓存区_2 equ 缓存区_1+2048
栈 equ 0FFFFh;60000：FFFF
缓存区_3 equ 70000h;～7FFFF


push ax
push cx
push si
push di
call 自定位

自定位:
pop si
sub si,自定位
push si;再次压栈，基地址
add si,DOS起始
mov di,cs;DS=CS
mov ds,di
mov di,DOS段地址/16;Loader将自己复制到的位置
mov es,di
mov di,0
mov fs,di;DS，ES段寄存器已被占用
mov cx,DOS结束-DOS起始
push cx
shr cx,2;÷4，以便最高效复制
rep movsd;如果CX为0则什么都不操作
pop cx
and cl,11b;只保留低二位
rep movsb;如果CX为0则什么都不操作

mov cx,DOS段地址/10h;现在写入我们的中断程序
mov fs:[2],cx;段地址
mov word fs:[0],int0-DOS起始;偏移地址

mov fs:[2+4],cx
mov word fs:[4*1h],int_1-DOS起始

;int2

;int3

mov fs:[2+24],cx
mov word fs:[4*6h],int6-DOS起始

;mov fs:[2+32],cx
;mov word fs:[4*8h],int8-DOS起始

mov fs:[2+48],cx
mov word fs:[4*0ch],intC-DOS起始

mov fs:[2+52],cx
mov word fs:[4*0dh],intD-DOS起始

mov fs:[2+84h],cx
mov word fs:[4*21h],int21-DOS起始

cmp bp,0AA55h;由我们的引导扇区过传来的判断数
jnz 无法确定文件系统类型

pop bp;基地址

mov ax,2401h;启用A20门
int 15h
jc $

mov ah,2;修改文件系统类型号
int 21h
jc 无法确定文件系统类型;文件系统类型号过大

pop di
pop si
pop cx
pop ax
movzx esp,sp;清空高位
mov es:[驱动器号],dl
movzx dx,dh;把高位传到低位并清空高位
xchg bx,dx;由我们的引导扇区过传来的文件系统类型号
shl bx,1;×2
add bx,bp;加基地址
mov bx,[bx+文件系统类型_1];取值，注意BP默认的段寄存器是SS
add bx,bp;加基地址
xchg bx,dx
jmp dx;跳转CS：DX

文件系统类型_1:
dw 无法确定文件系统类型
dw iSO9660文件系统
dw FAT32文件系统
dw Joliet文件系统
dw 无法确定文件系统类型;UDF

;----------------------------------------------------------------------------
无法确定文件系统类型:
mov si,未知文件系统
;add si,bp
call 打印
CALL 显示寄存器
jmp $
jmp 8000h:0h;进入命令处理程序
未知文件系统 db '?File System?'











iSO9660文件系统:
mov word es:[扇区大小],bx
mov ebx,eax
mov ah,5;设置文件或目录
int 21h
mov ah,1;获取文件系统参数
int 21h
push ecx;+8
push eax;+4
push dx;+2
push si;+0
mov si,换行
add si,bp
call 打印
mov si,OSHALKERINIT
add si,bp;加基地址
mov ebx,100000h
mov ah,9
int 21h
jmp 0FFFFh:10h







没有文件夹:
call 打印None和原字符
call 打印斜杠
jmp 打印换行并返回BiOS



;将会修改EAX，EBX，ECX，DX，Si寄存器
;输入DS：Si文件夹名位置
;输出
文件名包含结束符_2:
xchg si,dx
mov ax,0FFFFh
sub ax,cx
mov cx,ax;文件名长度
mov al,1;需要文件夹
mov bx,9;获取一个文件或文件夹
int 21h
jc 没有找到并打印斜杠

mov al,'/'
call 打印一个字符
mov si,dx

打开文件夹_1:
mov cx,0FFFFh
mov dx,si

继续对比结束符_2:
lodsb
cmp al,0
jz 路径结束

cmp al,'/'
jz 文件名包含结束符_2

cmp al,'\'
jz 文件名包含结束符_2

loop 继续对比结束符_2

stc
ret

路径结束:
clc
ret



;将会修改EAX，EBX，ECX，DX，Si，Di寄存器
;输入DS：Si文件名偏移位置
;输出
文件名包含结束符_1:

xchg si,dx
mov ax,0FFFFh
sub ax,cx
mov cx,ax;文件名长度
mov al,0;需要文件
mov bx,9;获取一个文件或文件夹
int 21h
jnc 找到其中一个文件

mov cx,si
mov si,None
add si,bp
call 打印
mov bl,'|'
mov si,cx
call 打印字符直到遇见自定义的结束符
mov al,'|'
call 打印一个字符

读入其中一个存在的文件:
mov cx,0FFFFh
mov dx,si

继续对比结束符_3:
lodsb
cmp al,0
jz 路径结束_1

cmp al,'|'
jz 文件名包含结束符_1

loop 继续对比结束符_3

路径结束_1:
stc
ret

找到其中一个文件:
clc
ret







;将会修改AH寄存器
;输入AL字符
;输出
打印一个字符:
mov ah,14
push bx
mov bh,0;页码
int 10h
pop bx
ret



;不会修改寄存器
;输入AL字符
;输出
打印斜杠:
push ax
push bx
mov al,'/'
mov ah,14
mov bh,0;页码
int 10h
pop bx
pop ax
ret



;将会修改寄存器
;输入BL结束符，DS：Si字符位置
;输出
打印字符直到遇见自定义的结束符:
mov ah,14;功能号
mov bh,0;页码
jmp 插入_2

继续打印_1:
 int 10h;中断号

 插入_2:
 lodsb;将DS：Si指向的内容放入AL然后Si+1
 cmp al,bl
jnz 继续打印_1

ret



没有找到:
call 打印None和原字符

打印换行并返回BiOS:
mov si,换行
add si,bp
call 打印
int 18H;返回BiOS
jmp 停



;将会修改AL，BL，Si寄存器
打印None和原字符:
push si;原字符
mov si,None
add si,bp
call 打印
pop si
add si,bp
call 打印
ret



没有找到并打印斜杠:
call 打印None和原字符
call 打印斜杠
jmp 打印换行并返回BiOS




Joliet文件系统:
ud2
call 显示寄存器
jmp $

nop

;单个 CPU 一次只能执行一条指令。单处理器中的多任务处理通常是每个运行进程的不同寄存器/分页之间的快速切换（在软件级别），并且速度如此之快以至于看起来进程同时运行。

;多核 CPU 类似于拥有许多共享相同内存的单 CPU。其他所有内容（寄存器、模式等）均特定于每个 CPU。这意味着如果我们有一个 8 核处理器，我们必须执行相同的过程 8 次才能将其置于长模式下。我们可以让一个处理器处于实模式，另一个处理器处于保护模式，另一个处理器处于长模式，等等。


;push code32_idx    ; The selector of the compatibility code segment
;xor rcx,rcx    

;mov ecx,Back32    ; The address must be an 64-bit address,
                  ; so upper 32-bits of RCX are zero.
;push rcx
;retf


FAT32文件系统:
mov ax,fs:[7c00h+11]
mov es:[扇区大小],ax
mov al,fs:[7c00h+13]
mov es:[t_u8_3],al;每个簇占用的扇区数
mov eax,fs:[7c00h+44]
mov es:[当前目录簇号],eax
mov eax,fs:[7c00h+52+4];820，FAT起始
mov es:[t_u32_2],eax;iSO9660目录长度
mov eax,fs:[7c00h+52+8];1Fe838，第一个数据扇区，全部值
mov es:[t_u32_1],eax;FAT数据区起始
mov al,fs:[7c00h+64]
mov es:[驱动器号],al

mov si,换行;表示我们已进入Loader
add si,bp
call 打印

mov bx,1;获取文件系统参数
int 21h
push eax;+6，根目录的簇号
push bx;+4
push di;+2
push dx;+0！，扇区大小

mov al,1;文件夹
mov cx,4
mov si,BOOT
add si,bp;加基地址
mov bx,9;获取一个文件或文件夹
int 21h
mov si,斜杠BOOT
jc 没有找到

mov bx,5;设置文件系统参数
int 21h
mov al,'/'
mov ah,14;功能号
mov bh,0;页码
int 10h

mov al,0;文件
mov cx,11
mov si,COMMAND
add si,bp;加基地址
mov bx,9;获取一个文件或文件夹
int 21h
jc 没有找到

mov bx,5;设置文件系统参数
int 21h
mov ecx,7000_0000h;读入文件扇区不会修改ebx
sub cx,[esp];减应对推

继续读入_1:
add cx,[esp];推偏移地址
mov bx,7
int 21h
jnc 继续读入_1

mov eax,[esp+6]
mov bx,5;恢复原根目录
int 21h
pop dx;传递参考数据
pop di
pop bx
pop eax

jmp 7000h:0h;进入命令处理程序









换行 db 13,10,0
None db 'None ',0

OSHALKERINIT db 'OPERATING SYSTEM/HARDWARE ABSTRACTION LAYER/KERNELINITIALIZE.BIN',0

OSHAL db 'OPERATING SYSTEM/HARDWARE ABSTRACTION LAYER/',0
INITIALIZE db 'INITIALIZE.BIN|',0



斜杠BOOT db '/'
BOOT db 'BOOT',0

COMMAND db 'COMMAND.BIN|',0


;----------------------------------------------------------------------------
DOS起始:;Disk Operating System
;int指令执行流程为pushf  push cs  push ip  jmp
int21:
mov cs:[u16_1],ss
cmp word cs:[u16_1],DOS段地址/10h
jnz 不是在内部调用_1

or byte cs:[标志],10b;标记为在内部调用
jmp 不设置栈_1

不是在内部调用_1:
mov cs:[栈-4],sp
mov cs:[栈-2],ss;保原存栈
mov sp,DOS段地址/16;设置新栈
mov ss,sp
mov esp,栈-6;顺便清空高位

不设置栈_1:
cmp ah,功能号大小/2;垃圾NASM编译器不支持动态数值的除法
ja 功能号过大;大于则跳转

push bx
movzx bx,ah
shl bx,1;×2
mov bx,cs:[bx+功能表起始-DOS起始]
cmp bx,寻址表结束-DOS起始;地址已经不在表内所以不需要再次定位
JAE 不区分文件系统;大于等于则跳转

push si
movzx si,byte cs:[文件系统类型号]
shl si,1;×2
mov bx,cs:[bx+si];BX是基地址，Si是表内偏移
pop si

不区分文件系统:
xchg [esp],bx
ret;跳转至CS：BX


功能号过大:
mov ah,1;功能号错误

进位返回:
or byte cs:[标志],100b;置1这个位
jmp 返回

退位返回:
and byte cs:[标志],1111_1011b;置0这个位
;jmp 返回

返回:
test byte cs:[标志],10b;被测试位 =0则ZF =1
jz 不是在内部调用_2

and byte cs:[标志],1111_1101b;下次返回时可能就要还原栈了，所以清空这个标志
jmp 不设置栈_2;现在还不用还原栈

不是在内部调用_2:
lss sp,cs:[栈-4];还原栈

不设置栈_2:;设置栈内CF标志位，注意压栈顺序
test byte cs:[标志],100b;被测试位 =0则ZF =1
jnz CF置_1

and byte[esp+4],1111_1110b;CF置0
iret;是弹出标志位并返回

CF置_1:;
or byte[esp+4],1b
iret;是弹出标志位并返回


功能号大小 equ 功能表结束-功能表起始;垃圾NASM编译器不支持动态数值的除法
功能表起始:
dw 0;获取功能号信息
dw 获取簇号或逻辑扇区号-DOS起始;1
dw 修改文件系统类型号-DOS起始;2
dw 设置重新读取文件扇区-DOS起始;3
dw 获取一个文件项-DOS起始;4
dw 设置簇号或逻辑扇区号-DOS起始;5
dw 重置文件读入状态-DOS起始;6
dw 读入文件扇区-DOS起始;7
dw 解析MBR-DOS起始;8
dw 打开_1个文件或文件夹-DOS起始;9
功能表结束:


获取簇号或逻辑扇区号:
dw 0;null
dw iSO9660获取逻辑扇区号-DOS起始
dw FAT获取簇号-DOS起始

获取一个文件项:
dw 0;null
dw iSO9660_1-DOS起始
dw FAT32_1-DOS起始

设置簇号或逻辑扇区号:
dw 0;null
dw iSO9660设置逻辑扇区号-DOS起始;注意 nasm bug
dw FAT设置簇号-DOS起始

读入文件扇区:
dw 0;null
dw iSO9660读一个文件扇区-DOS起始
dw FAT32_3-DOS起始

打开_1个文件或文件夹:
dw 0;null
dw iSO9660打开_1个文件或路径-DOS起始
dw FAT32_打开_1个文件或文件夹-DOS起始

寻址表结束:;结束位置跟下面一项的地址重复了，所以需要大于等于跳转



;无输入
;输出ECX当前簇号，EBX目录长度，DL驱动器号，DH文件系统类型号，Si扇区大小
iSO9660获取逻辑扇区号:;
mov ebx,cs:[t_u32_2];iSO9660目录长度

FAT获取簇号:
mov ecx,cs:[当前目录簇号];簇号或逻辑扇区号
mov dL,cs:[驱动器号]
mov dh,cs:[文件系统类型号]
mov si,cs:[扇区大小]
jmp 退位返回



;输入DH文件系统类型号
修改文件系统类型号:
cmp dh,2
ja 进位返回;大于则跳转

mov cs:[文件系统类型号],dh
jmp 退位返回



;无输入
设置重新读取文件扇区:
and byte cs:[标志],1111_1110b
jmp 退位返回



;输入EBX=iSO9660目录长度，ECX当前逻辑扇区号
;无输出
iSO9660设置逻辑扇区号:;注意 nasm bug
mov cs:[t_u32_2],ebx

;输入ECX当前目录簇号
;无输出
FAT设置簇号:;
mov cs:[当前目录簇号],ecx
and byte cs:[标志],1111_1110b
jmp 退位返回



;输入
;AL =属性
;输出
;EAX >LBA
;ECX >扇区数据长度
;DX >文件名长度
;ES：Di >文件名
iSO9660_1:
push ebx
push si
push ds
call iSO9660获取一个项
pop ds
pop si
pop ebx
ret



;将会修改EAX，EBX，ECX，EDX，Si，Di寄存器
;需要输入1次EAX扇区数据长度，需要输入1次EBX=LBA，需要输入1次CL文件属性号
;输出EAX=LBA，ECX扇区数据长度，DX文件名长度，ES：Di文件名
iSO9660获取一个项:
mov si,DOS段地址/10h
mov ds,si;段地址，int13ah42的DS：Si，磁盘参数块需要
mov si,缓存区_3/10h
mov es,si;返回值
test byte[标志],1b;被测试位 =0则ZF =1
jnz 不要重置

cmp cl,2
ja 属性错误;大于则跳转

mov [文件属性号],cl
or byte[标志],1b;取消下次重置
mov [逻辑扇区号],ebx

;iSO9660目录长度
mov edx,0;清空除法高位
movzx ebx,word[扇区大小]
div ebx;edx高：eax低÷ebx =eax…edx
cmp dx,0
jz 没有超出_2;超出一个字节都需要读完整个扇区

inc ax

没有超出_2:
mov [t_u8_1],ax
mov word[当前扇区偏移量],0FFFFh


不要重置:
mov bx,[当前扇区偏移量]

继续取项_1:
cmp bx,[扇区大小];当前扇区处理完了吗
jb 直接取项;小于则跳转

读下一个扇区:
cmp word[t_u8_1],0
jz 项已读完_1

dec word[t_u8_1]
mov eax,[逻辑扇区号]
inc dword[逻辑扇区号];推进到下一个扇区
mov edx,0;LBA高位
mov ebx,缓存区_3
mov cx,1
call 读盘
add bx,es:[bx];跳过一个.目录
add bx,es:[bx];跳过一个..目录

直接取项:
movzx dx,byte es:[bx];本项长度
cmp dl,0
jz 读下一个扇区;触底

mov al,es:[bx+25]
add bx,dx;原项+现项=预先推进到下一个项
mov di,iSO9660属性表-DOS起始
call 对比文件属性
jnz 继续取项_1;不符合类型

mov [当前扇区偏移量],bx;更新
sub bx,dx;减去预推
mov eax,es:[bx+2];2双端格式的范围位置 (LBA)，2~8÷2
mov ecx,es:[bx+10];双端格式的数据长度（范围大小）
movzx dx,byte es:[bx+32];取文件名长度
lea di,es:[bx+33];文件名位置

add di,dx;指向文件名末尾
cmp word es:[di-2],';1';这里有个结束符叫什么版本号来着
jnz 没有版本号_1

dec dl;文件名长度不应该包含这东西
dec dl
jnz 没有版本号_1;文件名长度不应该等于0

inc dl;糟糕我们判断错误了这其实是文件名本身
inc dl;那就把他加回来

没有版本号_1:
lea di,es:[bx+33];重新取文件名位置
clc;清除进位
ret

项已读完_1:
and byte[标志],1111_1110b;下次则从头开始

属性错误:
stc
ret

iSO9660属性表:;
dw iSO9660文件-DOS起始
dw iSO9660文件夹-DOS起始

db 1;长度
iSO9660文件:;
db 0;属性

db 1;长度
iSO9660文件夹:;
db 2;属性



;输入
;AL =属性
;输出
;EAX =逻辑扇区号
;DX =文件名长度
;ES：Di =文件名位置
FAT32_1:
push ebx
push cx
push si
push ds
call FAT32获取一个项
pop ds
pop si
pop cx
pop ebx
jmp 返回



;将会修改EAX，EBX，CX，EDX，Si，Di寄存器
;输入
;AL =属性
;输出
;EAX =逻辑扇区号
;DX =文件名长度
;ES：Di =文件名位置
FAT32获取一个项:
mov bx,DOS段地址/10h
mov ds,bx;段地址，int13ah42的DS：Si，磁盘参数块需要
mov bx,缓存区_3/10h
mov es,bx;返回值
test byte[标志],1b;被测试位 =0则ZF =1
jnz 不要重置_2

;标记FAT文件属性
;mov byte[文件属性-DOStart],20h;文件
;mov byte[文件属性_2-DOStart],23h;隐藏的文件
;mov byte[文件属性_3-DOStart],20h;文件
;mov byte[文件属性_4-DOStart],20h;文件
;cmp al,0
;jz 属性正确

;mov byte[文件属性-DOStart],10h;文件夹
;mov byte[文件属性_2-DOStart],12h;隐藏的文件夹
;mov byte[文件属性_3-DOStart],30h;存档的文件夹
;mov byte[文件属性_4-DOStart],32h;隐藏存档的文件夹
;cmp al,1
;jz 属性正确

;mov [文件属性-DOStart],al;第一个匹配就行了
;mov [文件属性_2-DOStart],al
;mov [文件属性_3-DOStart],al
;mov [文件属性_4-DOStart],al
;cmp al,0FFh;全部都要
;jz 属性正确

;ret;属性错误，直接返回

;属性正确:
mov eax,[当前目录簇号];取
mov [当前簇号-DOS起始],eax;存
or byte[标志],1b;取消下次重置
mov word[当前扇区偏移量-DOS起始],0a00h-32;存
mov byte[t_u8_1-DOS起始],1;触发读取簇


不要重置_2:
mov bx,[当前扇区偏移量-DOS起始];取

本项已被删除:;下面也会跳到这里
call 推到下一个项
cmp byte es:[bx],0e5h;已被标记为删除
jz 本项已被删除

cmp byte es:[bx+11],0Fh;长目录的项固定值
jz 长目录项

;短目录项
mov al,es:[bx+11];取
cmp al,0;空项
jz 本项已被删除

call 对比文件属性
jc 本项已被删除;属性错误

mov [当前扇区偏移量-DOS起始],bx;刷
mov ax,ds;交
mov cx,es
mov es,ax
mov ds,cx
mov si,bx;名
mov di,DOS结束-DOS起始+2048;缓
mov cx,8;长
cmp byte[bx+12],0h
jnz no全部大写

处理文件名:
call 转成大写
call 分隔点.
call 转成大写
jmp 扩展名结束

no全部大写:;
cmp byte[bx+12],8h
jnz  no文件名全小写.扩展名全大写
call 转成小写
call 分隔点.
call 转成大写
jmp 扩展名结束

no文件名全小写.扩展名全大写:
cmp byte[bx+12],10h
jnz  no文件名全大写.扩展名全小写

call 转成小写
call 分隔点.
call 转成小写
jmp 扩展名结束

no文件名全大写.扩展名全小写:
cmp byte[bx+12],18h
jnz  no全部小写

call 转成小写
call 分隔点.
call 转成小写
jmp 扩展名结束

no全部小写:;
mov cx,11;取完全部
rep movsb
jmp 扩展名结束



;将会修改AL，CX，Si，Di寄存器
;输入
;DS：Si =原文件名
;输出
;ES：Di =处理后文件名
转成大写:;原字符全是大写，什么都不用处理
lodsb;取
cmp al,' '
jz 处理结束

stosb;存
loop 转成大写
处理结束 ret

转成小写:
lodsb;取
cmp al,' '
jz 处理结束_1

cmp al,'A'
jb 不能处理_1;小于则跳转

cmp al,'Z'
ja 不能处理_1;大于则跳转

add al,32;补差价

不能处理_1 stosb;存
loop 转成小写

处理结束_1 ret

分隔点.:
lea si,[bx+8];指向扩展名
mov cx,3;扩展名长度
cmp byte[si],' ';是空格就
jz 没有扩展名

mov al,'.';点
stosb;存
ret

没有扩展名:
inc sp;栈平衡
inc sp

扩展名结束:
push word[bx+20];获取簇号高位
push word[bx+26];获取簇号低位
pop eax;32位簇号
mov dx,di
sub dx,DOS结束-DOS起始+2048;文件名缓存区，DX =文件名长度
mov di,DOS结束-DOS起始+2048;Di =文件名位置
ret;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


长目录项:
mov word[待转换字符位置-DOS起始],DOS结束-DOS起始+2048+2+26;字符缓存区，+2不覆盖结束符，+26以应对鬼畜的字符存储方式
cmp byte es:[bx],41h;1∨40h=41h;项序号=1or40h=41固定值
jnz 多条长项

;单条长项
mov di,bx;save
call 推到下一个项
cmp byte es:[bx],0e5h;已被标记为删除
jz 本项已被删除

mov al,es:[bx+11];取
call 对比文件属性
jc 本项已被删除;属性不匹配，不是需要的项

mov dx,bx;save
mov bx,di;原
mov ax,ds;交
mov cx,es
mov es,ax
mov ds,cx
lea si,[bx+1];跳过项序号
mov di,es:[待转换字符位置-DOS起始];缓
call 取长目录项内字符
mov ax,0;结束符
stosw;存
mov bx,dx;
jmp 项结束


多条长项:;;;;1;;;;
mov di,bx;save
mov cl,es:[bx];第一个是特殊的项
cmp cl,40h
jb 不能⊕;小于则跳转

xor cl,40h;固定异或值

不能⊕ mov [t_u8_2-DOS起始],cl;存项序号，减计数

对比序号:
call 推到下一个项
dec cl;减
jz 对比结束

cmp cl,es:[bx];序号
jz 对比序号;续

jmp 本项已被删除;出现错误，序号不匹配

对比结束:
cmp byte es:[bx],0e5h;已被标记为删除
jz 本项已被删除

mov al,es:[bx+11];取
cmp al,0;空项
jz 本项已被删除

call 对比文件属性
jc 本项已被删除;属性不匹配，不是需要的项

;取长字符
mov bx,di;原
mov ax,ds;交
mov cx,es
mov es,ax
mov ds,cx
lea si,[bx+1];跳过项序号
mov di,es:[待转换字符位置-DOS起始];缓
call 取长目录项内字符;第一次有字符结束所以忽略进位
mov ax,0;结束符
stosw;存
mov dl,es:[t_u8_1-DOS起始];取，项序号

继续取项内字符:;;;;2;;;;，内循环
cmp bx,09e0h
jb 不要环回;小于则跳转

mov bx,0-32;环回缓存区并应对预推

不要环回 add bx,32;推
dec dl
jz 项结束;已经结束嘞
lea si,[bx+1];跳过项序号
add word es:[待转换字符位置-DOS起始],26;应对这鬼畜的字符存储方式，不会出现没填满26个坑的情况
mov di,es:[待转换字符位置-DOS起始];缓存区
call 取长目录项内字符
jnc 继续取项内字符

mov word es:[待转换字符位置-DOS起始],DOS结束-DOS起始+2048+2+26;出现错误，重置字符缓存区以废弃前面缓存的字符
mov word es:[DOS结束-DOS起始+2048+26],0;结束符
jmp 继续取项内字符


项结束:;;;;;;;;注意，没有校验和
push word[bx+20];获取簇号高位
push word[bx+26];获取簇号低位
mov ax,es
mov ds,ax
mov [当前扇区偏移量-DOS起始],bx;刷
mov si,[待转换字符位置-DOS起始];字符起始
mov di,si;Di被推到了后面，还原以不覆盖待转换字符
;dec si;减一以免取到下一个字符
cld;正序
jmp 插入;第一次插入不需要减2

继续转换_1:;转换成UTF8
jns wd2
stosb
jmp 持续插入

wd2:;
jc bwd3
stosw
jmp 持续插入

bwd3:;
stosb
shr eax,8;注意
stosw

持续插入 dec si
dec si

插入:
movzx eax,word[si]
cmp ax,0
jnz 继续转换_1

pop eax;32位簇号
mov dx,di;字符结束
mov di,[待转换字符位置-DOS起始];字符起始
sub dx,di;字符结束-字符起始=字符长度
ret


























;将会修改EAX，EBX，EDX，Si寄存器
;输入
;BX =本项
;输出
;BX =下一项
;注意，这里的难度有点大
;会浪费一个扇区大小的内存空间
推到下一个项:
add bx,32;推
cmp bx,09e0h;虽然缓存区顶部位于a00，但是我们在9e00时已经扫完项了，所以。。。
mov ax,bx;save
mov bx,0;如果到到达缓存区顶部，则需要环回至底部
ja 需要读盘;大于则跳转

mov bx,ax;预判失败，还原BX

不要环回_1:;嗯，缓存区还没满
mov ax,[扇区大小]
dec ax;二进制位全部变1
test bx,ax;当前扇区处理完了吗，被测试位 =1，ZF =0
jnz 不用读盘

需要读盘:
dec byte[t_u8_1-DOS起始];减
jnz 不用下一个簇

mov eax,[当前簇号-DOS起始];取
call 簇号转逻辑扇区号
mov [逻辑扇区号],eax;刷
mov [t_u8_1-DOS起始],dl
jc 结束了自带进位

mov eax,[当前簇号-DOS起始];取
call 计算下一个簇号
mov [当前簇号-DOS起始],eax;刷

mov eax,[逻辑扇区号];Revert再取

不用下一个簇:
mov eax,[逻辑扇区号];取
mov edx,0;LBA高位
or ebx,1001_0000_0000_0000_0000_0000_0000_0000b;段，不能修改在低位的偏移值
;add bx,[扇区大小-DOS起始];偏
call 读盘
inc dword[逻辑扇区号];推

不用读盘:
ret

结束了自带进位:
and byte[标志],1111_1110b;重置读取
pop ax;删call指令压的返回地址，随便弹一个寄存器都行
ret;直接返回



;将会修改AX，CX，Si，Di寄存器，DF标志位
;输入
;DS：Si =UTF16字符
;输出
;ES：Di =倒序的UTF16字符
取长目录项内字符:
mov cx,5;共10个BYTE

取项内字符_1:
 cld;正
 lodsw;取
 cmp ax,0;结束符
 jz 返回错误

 std;倒
 stosw;存
loop 取项内字符_1

add si,3;跳过1个表示长目录项的0F，1个表示子的项固定值0，1个校验位？
mov cx,6;共12个BYTE

取项内字符_2:
 cld;正
 lodsw;取
 cmp ax,0;结束符
 jz 返回错误

 std;倒
 stosw;存
loop 取项内字符_2

inc si;2个固定值0
inc si
mov cx,2;共4个BYTE

取项内字符_3:
 cld;正
 lodsw;取
 cmp ax,0;结束符
 jz 返回错误

 std;倒
 stosw;存
loop 取项内字符_3
ret

返回错误 stc
ret



;将会修改EAX，Ebx，EDX，Si寄存器
;输入
;EAX >簇号
;输出
;EAX >下一个簇号
;除法
;ax÷bl =al…ah，被除数÷除数 =商…余数
;EDX高：EAX低÷EBX =EAX…EDX
;算法
;簇号÷（扇区大小÷4）=余数是扇区内偏移，然后商×4=LBA号
计算下一个簇号:
push bx;save
movzx ebx,word[扇区大小]
shr bx,2;512÷4，每个扇区可保存的目录数
xor edx,edx;空
div ebx;EAX >扇区号，DX >目录内偏移
shl dx,2;×4
push dx;读盘会修改DX我们要提前保存

add eax,[t_u32_2];你得到了LBA号，FAT起始
cmp eax,[标记逻辑扇区号-DOS起始];在同一张FAT内？
jz 读取簇号;上次读过这张FAT表

mov [标记逻辑扇区号-DOS起始],eax
mov edx,0;LBA高位
mov ebx,8000_0000h;段地址
mov bx,DOS结束-DOS起始+1024;偏移地址，用于缓存FAT表，不能被其他东西覆盖
call 读盘;只需要读一个扇区的FAT表即可

读取簇号:
pop bx;恢复我们的FAT表内偏移
and byte[bx+3+DOS结束-DOS起始+1024],1111b;屏蔽前4位，FAT32其实只有28位簇号
mov eax,dword[bx+DOS结束-DOS起始+1024];读取我们需要的簇号
pop bx;
ret




;将会修改EAX,EDX寄存器
;输入
;EAX =目标簇号
;输出
;EAX =LBA号
;EDX_DL =簇占用的扇区数
;如果链表末端则设置进位，EAX，EDX不变，链表结束
;乘法
;al×bl =ax，被乘数×被乘数 =积
;EAX×EDX =EDX高：低EAX
;算法
;（簇号-2）×每个簇占用的扇区数+数据区起始扇区号=簇的LBA号
簇号转逻辑扇区号:
cmp eax,0FFF_FFF8h;如果链表结束
jae 链表末端;大于等于则跳转，这是簇链的结束标志

dec eax
dec eax

movzx edx,byte[t_u8_3];每个簇占用的扇区数，使用扩位传送覆盖DX的高位以进行32位乘法
push dx;只有这个寄存器未被使用
mul edx;edx是乘法的高位但我们不允许eax溢出到高位
pop dx;不用压桟EDX以节省空间

add eax,[t_u32_1];数据区起始扇区号
ret;此时进位未设置，除非参数错误

链表末端 stc;通过进位表示结束
ret









;----------------------------------------------------------------------------






;无输入
;无输出
重置文件读入状态:
;mov byte[重置读取-DOS起始],1
jmp 返回



;不会修改寄存器
;输入ECX高位=段地址，CX偏移
;输出
iSO9660读一个文件扇区:
push eax;+10
push ebx;+6
push dx;+4
push si;+2
push ds;+0
mov ax,DOS段地址/16
mov ds,ax

test byte[标志],1b;被测试位 =0则ZF =1
jnz 不要重置_1

or byte[标志],1b;设置为1下次就不会重新读文件扇区了
mov eax,[当前目录簇号]
mov [逻辑扇区号],eax

mov eax,[t_u32_2]
mov edx,0;清空除法高位
movzx ebx,word[扇区大小]
div ebx;edx高：eax低÷ebx =eax…edx
cmp dx,0
jz 没有超出_3;超出一个字节都需要读完整个扇区

inc ax

没有超出_3:
mov [t_u8_1],ax


不要重置_1:
cmp word[t_u8_1],0
jz 扇区已完

mov eax,[逻辑扇区号]
mov edx,0;LBA高位
mov ebx,ecx;缓存区址
call 读盘
inc dword[逻辑扇区号];推进到下一个扇区
dec word[t_u8_1]
and byte cs:[标志],1111_1011b

返回_1:
pop ds
pop si
pop dx
pop ebx
pop eax
ret;正常返回，下次还来

扇区已完:
and byte[标志],1111_1110b;下次则从头开始
or byte cs:[标志],100b;设置CF标志位
jmp 返回_1;读取完毕



;输入
;ECX =缓存区的段地址：偏移地址
;输出
FAT32_3:
push eax
push ebx
push edx
push si
push ds
mov ax,DOS段地址/16
mov ds,ax

test byte[标志],1b;被测试位 =0则ZF =1
jnz 不要重置_3


or byte[标志],1b;设置为1下次就不会重新读文件扇区了
mov eax,[当前目录簇号]
mov [当前簇号-DOS起始],eax;刷
mov byte[t_u8_1-DOS起始],1;触发计算簇


不要重置_3:
dec byte[t_u8_1-DOS起始];每个簇占用的扇区数
jnz  继续读取_1;还不用下一个簇

mov eax,[当前簇号-DOS起始]
call 簇号转逻辑扇区号
jc 读取完毕_1

mov [逻辑扇区号],eax;刷
mov [t_u8_1-DOS起始],dl

mov eax,[当前簇号-DOS起始]
call 计算下一个簇号
mov [当前簇号-DOS起始],eax;存

继续读取_1:
mov eax,[逻辑扇区号]
inc dword[逻辑扇区号];推进到下一个扇区
mov edx,0;LBA高位
mov ebx,ecx
call 读盘

Do返回_1:;
pop ds
pop si
pop edx
pop ebx
pop eax
jmp 返回

读取完毕_1:
and byte[标志],1111_1110b;已读完，下次重新开始
;自带进位
jmp Do返回_1






解析MBR:;MasterBootRecord:
mov eax,0;第一个扇区一般为MBR，也有可能是DBR
mov edx,0;LBA高位
mov ebx,9000_0000h;缓存区，段地址
mov bx,DOS结束-DOS起始;偏移地址，在此处放置扇区
call 读盘
cmp dword[bx+510],0AA55h;判断数
jz 分区表正常
mov si,未检测到分区表
call 打印
jmp $
未检测到分区表 db 'invalid partition table',13,10,'Try using the fs command directly',13,10,0

分区表正常 jmp $







;将会修改EAX，BX，ECX，ES寄存器
;输入DS：Si=UTF8字符串的文件名位置，EBX文件缓存区 如果只是打开路径或文件夹则不需要
;输出DS：Si未找到的文件名
iSO9660打开_1个文件或路径:
sub sp,40
;备份寄存器
mov [esp+0],ds;数据段_1
mov [esp+2],es
mov [esp+4],eax
mov [esp+8],ebx;文件缓存区_1
mov [esp+12],ecx
mov [esp+16],dx
mov [esp+18],si;这次的UTF8字符串类型的文件名位置_1
mov [esp+20],di
mov word[esp+22],0;第2项文件名长度_1
mov byte[esp+24],1;+24 上1串字符长度_1 应该是0但使用此值会导致某些BiOS清空全屏，所以使用1来解决
;mov word[esp+25],;光标位置_1
;mov word[esp+27],;第1项文件名长度_1
mov word[esp+29],si;下次的UTF8字符串类型的文件名位置_1
mov [esp+31],al
mov eax,cs:[当前目录簇号]
mov [esp+32],eax
mov eax,cs:[t_u32_2];iSO9660目录长度
mov [esp+36],eax
;多余的暂时存放;+16=项名长度，+18=iSO9660数据长度，+22=LBA


下_1个文件夹_1:
mov si,[esp+29];下次的UTF8字符串类型的文件名位置_1
cmp byte[si],0
jz 路径已结束_1

mov [esp+18],si;这次的UTF8字符串类型的文件名位置_1
mov cx,0FFFFh;扫描长度

寻找结束符_1:
lodsb
cmp al,'/'
jz 只要文件夹_1

cmp al,0
jz 需要读入文件_1

cmp al,'\'
jz 只要文件夹_1

loop 寻找结束符_1

mov ah,2;文件名没有结束符
mov si,[esp+18];这次的UTF8字符串类型的文件名位置_1
jmp 进位返回

需要读入文件_1:
or byte cs:[标志],1000b;置1这个位
jmp 不能覆盖需要读入文件的标志

只要文件夹_1:
and byte cs:[标志],1111_0111b;置0这个位

不能覆盖需要读入文件的标志:
mov [esp+29],si;下次的UTF8字符串类型的文件名位置_1
dec si;此时Si已指向结束符我们不要把结束符也算进去
;结束位置-起始位置=过程长度
sub si,[esp+18];这次的UTF8字符串类型的文件名位置_1
mov [esp+27],si;第1项文件名长度_1
cmp si,8
jbe 不需要短文件名;小于等于则跳转

mov si,[esp+18];这次的UTF8字符串类型的文件名位置_1
mov di,DOS段地址/10h;先把9个字符复制过去
mov es,di
mov di,缓存区_1
mov cx,9
cld;正序
rep movsb
mov di,缓存区_1;扫描复制过去的字符里的点
mov al,'.'
mov cx,9
mov bx,0FFFFh;用于标记是否找遇到过点

继续对比字符_1:
repne scasb
jnz 没有遇到点

mov bx,cx

没有遇到点:
cmp cx,0
jnz 继续对比字符_1

cmp bx,0FFFFh
jnz 有点

mov word[esp+22],8;先设置 第2项文件名长度_1 默认长度
;如果没有点则继续扫描源字符内的点，遇到第一个点后停止扫描并复制点后面的字符大于三个就只复制三个，小于或等于三则全部复制
mov di,9;总长度
mov es,[esp+0];数据段_1
mov cx,[esp+27];第1项文件名长度_1
sub cx,di;减去已扫描的长度得到剩余需要扫描的长度
add di,[esp+18];加上 这次的UTF8字符串类型的文件名位置_1 起始得到剩下部分的位置
repne scasb;遇到点则停止
jnz 不需要短文件名;没点

mov si,di;将点后的字符复制进缓存区
mov di,DOS段地址/10h
mov es,di
mov di,缓存区_1+9;不能覆盖之前复制进去的字符
mov byte es:[di-1],'.';写入1个点
mov dx,9;点前字符长度
jmp 复制后缀名

有点:;如果有点则复制点后面的字符大于3个就只复制3个，小于或等于3则全部复制
mov si,9;总长度
sub si,bx;减去剩余部分得到已扫描的长度
mov dx,si;点前字符长度
mov es,[esp+0];数据段_1
mov cx,[esp+27];第1项文件名长度_1
sub cx,si;减去已扫描的长度得到需要复制的长度
mov di,si;缓存区内偏移
add di,缓存区_1;加上缓存区地址得到需要复制到的位置
add si,[esp+18];加上 这次的UTF8字符串类型的文件名位置_1 起始得到剩下部分的位置

复制后缀名:
cmp cx,3
jbe 复制全部后缀名;小于等于则跳转

mov cx,3

复制全部后缀名:
add dx,cx;+点后字符长度
mov [esp+22],dx;第2项文件名长度_1
rep movsb

不需要短文件名:
call 获取光标位置
mov [esp+25],dx;更新 光标位置_1
test byte cs:[标志],1000b
mov cl,1
jz 只要文件夹_2

mov cl,0

只要文件夹_2:
mov ebx,[esp+32];LBA
mov eax,[esp+36];iSO9660目录长度

继续查找项_1:
call iSO9660获取一个项
jc 没有匹配项_1

mov [u32_1],eax;LBA
mov [u32_2],ecx;iSO9660数据长度
mov [u16_1],dx;项名长度
mov si,dx
mov dx,[esp+25];光标位置_1
movzx cx,byte[esp+24];上1串字符长度_1
call 重置光标并清除前文件名
mov cx,si
mov [esp+24],cl;更新 上1串字符长度_1
mov dx,di
call 显示项名
mov di,dx;项名位置
mov dx,si;项名长度
cmp dx,[esp+22];第2项文件名长度_1
mov bx,di;项名位置
jnz 试第_1项;第2项不匹配

;mov si,DOS段地址/10h
;mov ds,si
mov si,缓存区_1;第2项文件名位置
mov cx,dx;项名长度
repe cmpsb
jz 项名匹配

试第_1项:
cmp dx,[esp+27];第1项文件名长度_1
jnz 继续查找项_1;错误的文件名长度
mov cx,dx;项名长度
mov si,es
mov ds,si
mov si,bx;项名位置
call 指定长度的UTF8字符串内的小写字母转换为大写字母
mov di,bx;项名位置
mov ds,[esp+0];数据段_1
mov si,[esp+18];这次的UTF8字符串类型的文件名位置_1
mov cx,dx;项名长度
repe cmpsb
jnz 继续查找项_1

mov si,cs;上面修改了数据段
mov ds,si

项名匹配:
test byte[标志],1000b
jnz 需要读入文件_2

mov ebx,[u32_1];LBA
mov eax,[u32_2];iSO9660数据长度
mov [esp+32],ebx;LBA
mov [esp+36],eax;iSO9660目录长度
and byte cs:[标志],1111_1110b;要重新获取项喔
mov ds,[esp+0];数据段_1
mov bx,[esp+29];下次的UTF8字符串类型的文件名位置_1
mov al,[bx-1];显示分隔符
mov ah,14;功能号
mov bh,0;页码
int 10h
jmp 下_1个文件夹_1

需要读入文件_2:
push dword[esp+8];8+文件缓存区_1
push dword[u32_1];+4=LBA
push dword[u32_2];+0=iSO9660数据长度
mov ax,0FFFFh
mov dx,0;清空除法高位
div word[扇区大小];dx高：ax低÷[内存单元] =ax…dx
movzx ebp,ax


读入文件扇区_1:
sub dword[esp+0],0FFFFh
jc 不能读那么多扇区了_1;不够0FFFFh时会触发进位

mov ebx,缓存区_3
mov eax,[esp+4]
mov edx,0;LBA高位
mov cx,bp
call 读盘
add [esp+4],ebp
mov esi,ebx
mov edi,[esp+8]
mov ecx,0FFFFh
call 复制此处内存里的数据到内存的别处
add dword[esp+8],0FFFFh
jmp 读入文件扇区_1


不能读那么多扇区了_1:
mov ax,[esp+0];已经不够0FFFFh了我们要低位就行
add ax,0FFFFh
jz 刚好读完_1

mov dx,0;清空除法高位
mov di,ax
mov bp,[扇区大小]
div bp;dx高：ax低÷bp =ax…dx
dec bp
not bp;按位取反
and di,bp
cmp dx,0
jz 没有超出_4;超出一个字节都需要读完整个扇区

inc ax
not bp;按位取反
inc bp
add di,bp

没有超出_4:
mov ebx,缓存区_3
mov cx,ax
mov eax,[esp+4]
mov edx,0;LBA高位
call 读盘
mov esi,ebx
movzx ecx,di
mov edi,[esp+8]
call 复制此处内存里的数据到内存的别处

刚好读完_1:
and byte cs:[标志],1111_1110b;我们获取过文件项别忘了这个
add sp,12
jmp 不允许修改路径_1

路径已结束_1:;如果你没有输入文件夹名或或者没有找到文件夹则不会改变任何参数
mov ebx,[esp+32];LBA
mov eax,[esp+36];iSO9660目录长度
mov cs:[当前目录簇号],ebx;LBA
mov cs:[t_u32_2],eax;iSO9660目录长度

不允许修改路径_1:
mov ds,[esp+0];数据段_1
mov es,[esp+2]
mov eax,[esp+4]
mov ebx,[esp+8];文件缓存区_1
mov ecx,[esp+12]
mov dx,[esp+16]
mov si,[esp+18];这次的UTF8字符串类型的文件名位置_1
mov di,[esp+20]
jmp 退位返回


没有匹配项_1:
mov cx,[esp+24];上1串字符长度_1
mov dx,[esp+25];光标位置_1
call 重置光标并清除前文件名
mov bx,1
or byte cs:[标志],100b
jmp 进位返回





;输入
;AL =属性
;CX =文件名长度
;DS：Si =文件名位置
;输出
;EAX =簇号
FAT32_打开_1个文件或文件夹:
push ebx
push dx
push di
push es
push dword 1;+8，上一串字符长度应该是0但使用此值会导致某些BiOS清空全屏（应该是直接dec cx而没有做判断导致的）所以使用1来解决，+10，光标位置
push esi;+4，文件名位置
push ds;+2
push cx;+0！，文件名长度

call 获取光标位置
mov [esp+10],dx;刷，光标位置

继续查找项:
call FAT32获取一个项
jc 没有匹配项

mov esi,eax;Save簇
push dx;+0！，Save长
mov dx,[esp+10+2];光标位置
mov cx,[esp+8+2];上一串字符长度
call 重置光标并清除前文件名
mov cx,[esp];长
mov dx,di;Save名
call 显示项名
mov di,dx;原，名
pop dx;原，长
cmp dx,[esp];源文件名长度
jnz 继续查找项;错误的文件名长度

mov bx,di;Save名
mov cx,dx;长
call 指定长度的UTF8字符串内的小写字母转换为大写字母
mov di,bx;原，文件名
mov cx,dx;长
mov ds,[esp+2];段	
mov eax,esi;原，返回簇号
mov si,[esp+4];源文件名
repe cmpsb
jnz 继续查找项

没有匹配项:
pop cx
pop ds
pop esi
pop ebx;栈平衡，删压的上一串字符长度和光标位置
pop es
pop di
pop dx
pop ebx
jmp 返回





;AH，BX，CX，DX寄存器将会被修改
;输入
;无
;输出
获取光标位置:
mov ah,3;调用号
mov bh,0;页码
int 10h; AX =0000h(Phoenix BIOS)，CH =起始扫描线，CL =结束扫描线，DH =行（00h 位于顶部），DL =列（00h 位于左侧）
ret



;AX，BH寄存器将会被修改
;输入
;DX =光标位置
;CX =覆盖长度
;输出
重置光标并清除前文件名:
mov ah,2;功能号
mov bh,0;页码
int 10h
mov al,' ';用空格覆盖
mov ah,10;功能号
int 10h
ret



;AX，BH，CX，Di寄存器将会被修改
;输入
;ES：Di >项名
;CX长度
;输出
显示项名:
mov ah,14;功能号
mov bh,0;页码

显示路径_1 mov al,es:[di];取
 inc di;推
 int 10h
loop 显示路径_1

ret



;EAX，EBX，EDX，Di寄存器将会被修改
;输入
;EAX >待转换数值
;ES：Di >缓存区
;输出
;ES：Di >10进制ascall码，结尾为0，注意 倒序应使用std指令
;除法
;ax÷bl =al…ah，被除数÷除数 =商…余数
;Edx高：Eax低÷Ebx =Eax…Edx
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


;EAX，EBX，ECX，Si寄存器将会被修改
;输入，非数字符会发生？
;ES：Si =字符串，需带结束符
;输出
;EAX =数值
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
;EBX =待转换数值
;ES：Di =缓存区
;输出
;ES：Di =16进制ascall码，结尾为0，注意倒序应使用std指令
二进制转十六进制ascall码:
 mov al,bl
 shr ebx,4;显示了一位
 and al,0000_1111b;只保留低四位
 cmp al,10;是字母
 jb 小于则跳转

 add al,7;补齐，数字到字母之间隔了几个符号
 
小于则跳转 add al,'0';此0非彼0
 stosb;存入
 cmp ebx,0
jnz 二进制转十六进制ascall码

ret



_00～_7F_1:
shl ax,8;移动到AH顺便清空低位，因为大端的UTF16低位为零

写入字符_1:
stosw

;将会修改EAX，Si，Di寄存器
;输入DS：Si=UTF8字符串，需带结束符且至少为Byte大小，ES：Di缓存区
;输出ES：Di=UTF16字符串结尾，不含结束符
;test指令示例test al,0000_0100b;被测试位 =0则ZF =1
UTF8字符串转UTF16字符串:;
lodsb;读取一个UTF8字符
cmp al,0
jz UTF8字符串转UTF16字符串结束

test al,1000_0000b
jz _00～_7F_1

test al,0010_0000b
jz _80～_7FF_1

test al,0001_0000b
jz _800～_FFFF_1

test al,0000_1000b
jz _10000～_10FFFF_1

stc;转换时出现错误
ret

_80～_7FF_1:
and al,0001_1111b
mov ah,al
lodsb
shl al,2
shr ax,2
jmp 写入字符_1

_800～_FFFF_1:
and ax,0000_1111b
shl eax,16;移到EAX
lodsw
shl ah,2
shl al,2
shr eax,2
jmp 写入字符_1

_10000～_10FFFF_1:
and eax,0000_0111b;清空无用的位
mov ah,al; E0000_0000_E0000_0000 Ah0000_0xxx_AL0000_0000
lodsb
shl al,2;  E0000_0000_E0000_0000 Ah0000_0xxx_ALxxxx_xx00
shl eax,14;E0000_000x_Exxxx_xxxx Ah0000_0000_AL0000_0000
lodsb
mov ah,al; E0000_000x_Exxxx_xxxx AH00xx_xxxx_AL0000_0000
lodsb
shl al,2;  E0000_000x_Exxxx_xxxx Ah00xx_xxxx_ALxxxx_xx00
shl ax,2;  E0000_000x_Exxxx_xxxx AHxxxx_xxxx_ALxxxx_0000
shr eax,4; E0000_0000_E000x_xxxx AHxxxx_xxxx_ALxxxx_xxxx此时将得到unicode码
sub eax,10000h;将unicode码压缩到20位
shl eax,6; E0000_00xx_Exxxx_xxxx AHxxxx_xxxx_ALxx00_0000
shr ax,6;  E0000_00xx_Exxxx_xxxx AH0000_00xx_ALxxxx_xxxx
;and eax,000000_1111111111_000000_1111111111b
or eax,110110_0000000000_110111_0000000000b
stosd
jmp UTF8字符串转UTF16字符串

UTF8字符串转UTF16字符串结束:;
clc
ret



_00～_7F_2:
stosb

;EAX寄存器将会被修改
;输入DS：Si=UTF16字符串，需要结束符且至少为Word大小，ES：Di缓存区
;输出ES：Di=UTF8字符串结尾，不含结束符
;jbe指令示例cmp al,1 jbe,小于等于则跳转;被测试位 =0则ZF =1
;bswap指令把第一byte跟倒数第一byte互换，第二byte跟倒数第二byte互换
;┌-------┐
;│ ┌-┐ │
;00 00 00 00h
;bswap指令的互换关系如上图所示
;rol指令把最高bit移入最低bit并复制一份进CF标志位
;┌--------┐
;│<    <  │
; 101000000┘
;rol指令移动方向如上图所示
UTF16字符串转UTF8字符串:;
mov eax,0;清空高位
lodsw
cmp ax,0
jz UTF16字符串转UTF8字符串结束

cmp eax,7Fh;ascll有127个
jbe  _00～_7F_2

cmp eax,7FFh
jbe _80～_7FF_2

cmp eax,0FFFFh
jbe _800～_FFFF_2

_10000～_10FFFF_2:
and al,11_000000b;清空无用的位
bswap eax;小端转大端存储
lodsw
xchg ah,al;小端转大端存储
shl ax,6; E0000_00xx_Exxxx_xxxx Ahxxxx_xxxx_ALxx00_0000
shr eax,6;E0000_0000_E0000_xxxx Ahxxxx_xxxx_ALxxxx_xxxx
;and eax,1111_11111111_11111111b;清空无用的位
add eax,10000h;将unicode码解压到21位
shl eax,4;E0000_000x_Exxxx_xxxx Ahxxxx_xxxx_ALxxxx_0000
shr ax,2; E0000_000x_Exxxx_xxxx Ah00xx_xxxx_ALxxxx_xx00
shr al,2; Eh0000_000x_ELxxxx_xxxx Ah00xx_xxxx_AL00xx_xxxx
;or ax,10_000000_10_000000b
bswap eax;AL00xx_xxxx_Ah00xx_xxxx ELxxxx_xxxx_Eh0000_000x
rol ax,2; AL00xx_xxxx_Ah00xx_xxxx ELxxxx_xx00_Eh0000_0xxx
shr ah,2; AL00xx_xxxx_Ah00xx_xxxx EL00xx_xxxx_Eh0000_0xxx
;bswap eax;Eh0000_0xxx_EL00xx_xxxx Ah00xx_xxxx_AL00xx_xxxx
;or eax,11110_000_10_000000_10_000000_10_000000b
;bswap eax;大端转小端存储
or eax,10_000000_10_000000_10_000000_11110_000b
stosd
jmp UTF16字符串转UTF8字符串

_80～_7FF_2:
shl ax,2;Ah000x_xxxx_ALxxxx_xx00
shr al,2;AL00xx_xxxx
or ax,110_00000_10_000000b
xchg ah,al;大端转小端存储
stosw
jmp UTF16字符串转UTF8字符串

_800～_FFFF_2:
shl eax,4;E0000_0000_E0000_xxxx Ahxxxx_xxxx_ALxxxx_0000
shr ax,2;Ah00xx_xxxx_ALxxxx_xx00
shr al,2;AL00xx_xxxx
or eax,1110_0000_10_000000_10_000000b
bswap eax;大端转小端存储
shr eax,8;E0000_0000_E00xx_xxxx Ah00xx_xxxx_AL0000_xxxx
stosb
shr eax,8;E0000_0000_E0000_0000 Ah00xx_xxxx_AL00xx_xxxx
stosw
jmp UTF16字符串转UTF8字符串

UTF16字符串转UTF8字符串结束:;
clc
ret



;将会修改CX，Si寄存器
;DS：Si字符地址
;输出
UTF16字符串内的小写字母转成大写:;
 lodsw
 xchg ah,al;大小端转换
 cmp ax,'a'
 jb 不要转换_1;小于则跳转

 cmp al,'z'
 ja 不要转换_1;大于则跳转

 ;and byte[si-1],1101_1111b;转换为大写，原本就是则不变
 sub byte[si-1],32;lodsw把Si+2但我们只减1是因为大小端的原因

 不要转换_1:
loop UTF16字符串内的小写字母转成大写

ret



;将会修改CX，Si寄存器
;DS：Si字符地址
;输出
指定长度的UTF8字符串内的小写字母转换为大写字母:;
 lodsb
 test al,1000_0000b
 jnz 不要转换_2

 cmp al,'a'
 jb 不要转换_2;小于则跳转

 cmp al,'z'
 ja 不要转换_2;大于则跳转

 sub byte[si-1],32;

 不要转换_2:
loop 指定长度的UTF8字符串内的小写字母转换为大写字母

ret



;AL，CX，Di寄存器将会被修改
;输入CX字符长度，ES：Di字符位置
;输出
转成大写_1:
 mov al,es:[di];取
 cmp al,'A'
 jb 不要;小于则跳转

 cmp al,'z'
 ja 不要;大于则跳转

 cmp al,'[';在大写和小写之间隔了几个字符，我们需要额外处理
 jb 要;小于则跳转

 cmp al,'a'
 jb 不要;小于则跳转

 要 and byte es:[di],1101_1111b;转换为大写，原本就是则不变

 不要 inc di;推
loop 转成大写_1
ret



;将会修改AL，CX，Di寄存器
;输入
;CX =字符长度
;ES：Di =字符位置
;输出
带结束符的UTF16小写字母转换为大写字母:
mov di,si
jmp 插入_1

还未转换结束_1:
 cmp ax,'a'
 jb 直接写入_1;小于则跳转 不是小写字母

 cmp ax,'z'
 ja 直接写入_1;大于则跳转 不是小写字母

; 转换为小写字母_1:
 sub eax,32;注意 为什么是eax而不是ax

 直接写入_1:
 stosw

 插入_1:
 lodsw
loop 还未转换结束_1



;将会修改AH，DL，Si寄存器
;输入EAX=LBA低32位，EDX=LBA高32位，EBX高32位段地址+低32位偏移地址，CX要读取的块数
;输出
读盘:
push edx;[12]LBA高32位
push eax;[8]LBA低32位
;word[6]段地址
push ebx;[4]偏移地址
shl word[esp+2],12;×1000h
;byte[3]保留，必须为0，CX的高位就是这里的值应当清空CH寄存器，注意栈最小压Word
push cx;[2]要传输的扇区数0~127
;byte[1]保留，必须为0，这是参数块的高位，注意栈最小压Word
push byte 16;[0]参数块大小，注意栈最小压Word

mov ah,42h;调用号
mov dl,[驱动器号]
mov si,sp;注意栈是反过来的
int 13h;中断号
lea sp,[esp+16];从栈中删除参数块
jc $

ret



;将会修改CX，Di寄存器
;输入AL属性，Di属性表
;输出
;ZF=0=属性不同
对比文件属性:
movzx cx,byte[文件属性号];顺便清空高位
cmp cl,0FFh;全吃
jz 属性相同

shl cl,1;×2
add di,cx
mov di,[di]
push es
push DOS段地址/10h
pop es
movzx cx,byte[di-1];对比次数
repne scasb
pop es

属性相同:
ret



;将会修改AX，BH，Si寄存器
;DS：Si带结束符的字符串位置
;输出
打印:
mov ah,14;功能号
mov bh,0;页码
jmp 插入_3

继续打印:;每个指令都很重要确保他们被正确执行
 int 10h;中断号

 插入_3:
 lodsb;将DS：Si指向的内容放入AL然后Si+1
 cmp al,0
jnz 继续打印

ret



;将会修改ECX，DX，EDi，Si寄存器
;输入ECX数据字节长度，ESi数据，EDi要复制到的位置
;输出
复制此处内存里的数据到内存的别处:
mov dx,8
call 设置段寄存器的隐藏部分
mov ax,0
mov ds,ax
mov es,ax
mov al,cl
shr ecx,2;÷4，以便最高效复制
rep
db 67h;32位寻址
db 66h;32位操作数，+movsw=movsd
movsw
mov cl,al
and cl,11b;只保留低2位
rep
db 67h;32位寻址
movsb;如果CX为0则什么都不操作
mov dx,16
call 设置段寄存器的隐藏部分
mov dx,cs
mov ds,dx
sti;开中断
ret



;将会修改EAX，BX，DS，ES，FS，GS寄存器，iF标志位
;无输入
;输出
设置段寄存器的隐藏部分:
lgdt cs:[Gdtcfg-DOS起始];读入GDT长度及位置
mov eax,cr0
or al,1b
cli;关中断
mov cr0,eax
jmp short ProtectedMode;进入兼容模式

ProtectedMode:;
mov ds,dx
mov es,dx
mov fs,dx
mov gs,dx
and al,1111_1110b
mov cr0,eax
jmp DOS段地址/16:RealMode-DOS起始;进入实模式

RealMode:;
;sti;开中断
ret


Gdtcfg:;
dw GdtEnd-GdtStart-1;长度-1以忽略后1字节
dd GdtStart-DOS起始+DOS段地址;+基地址
GdtStart:;
dq 0h;听说设置个空的段描述符是为了防止从16位实地址模式切换到32位保护模式后忘记设置段寄存器引发的问题。

dw 0FFFFh;段长度
db 0,0,0;基地址
db 92h;10010010b;段属性
db 8Fh;1100_1111b;段属性_段长度1111b
db 0;基地址00h

dw 0FFFFh;段长度
db 0,0,0;基地址
db 92h;10010010b;段属性
db 0;1100_1111b;段属性_段长度1111b
db 0;基地址00h
GdtEnd:;












int0:
push si
mov si,除法错误-DOS起始
push ax
push bx
push DOS段地址/16;数据段
pop ds
call 打印
pop si
pop bx
pop ax
call 显示寄存器
jmp $

除法错误 db 10,'Division error',13,0


int_1:
push ds;+4
push ax;+2
mov ax,DOS段地址/16
mov ds,ax
push bx;+0！
mov bx,sp
or word ss:[bx+6+4],100h
push si
mov si,哞-DOS起始
call 打印
pop si
pop bx
pop ax
pop ds
iret

哞 db 'Moo~',0
;push bx
;pushf
;mov bx,sp
;or word ss:[bx],100h
;popf
;pop bx



;遇到错误指令或使用ud2指令触发
int6:
mov bx,DOS段地址/16
movzx esp,sp;清空高位
mov ds,bx
mov es,bx

mov di,DOS结束-DOS起始+2048;在此处放置转换的ascall码
mov ax,0a00h;换行+结束符
stosw

movzx eax,word[esp+2];iP，顺便清空高位
movzx ebx,word[esp];CS
shl ebx,4;×16
add ebx,eax;CS+iP
call 二进制转十六进制ascall码
mov si,_cs_ip-DOS起始
mov cx,11
rep movsb

mov si,di
dec si;减一以免取到下一个字符
std
call 打印
cld;恢复正序

mov si,错误的操作码-DOS起始
call 打印

pop bx;iP
pop fs;CS
inc sp;删除int指令压的标志
inc sp
mov ebx,fs:[bx]
mov al,0;结束符
stosb
call 二进制转十六进制ascall码
mov si,di
dec si;减一以免取到下一个字符
std
call 打印
cld;恢复正序

停:
 cli;会导致某些虚拟机报错
 hlt
jmp short 停

_cs_ip db '=Pi+61*SC',10,13
错误的操作码 db 13,'Undefined opcode_',0



;int8:
;mov si,DOS段地址/16
;mov ds,si
;mov si,双重错误-DOS起始
;call 打印
;jmp 停

;双重错误 db 13,10,'Double Fault',0



;#SS，栈溢出
;注意 当SP下溢时不会产生此中断，即SP=1然后执行push指令时处理器将会复位或重启
intC:
mov ebx,DOS段地址/16;顺便清空高位
mov ds,bx
mov es,bx

mov si,栈错误-DOS起始
call 打印

mov di,DOS结束-DOS起始+2048;在此处放置转换的ascall码
mov al,0;结束符
stosb

mov bx,ss
shl ebx,4;×16
add ebx,esp
add ebx,3;减int指令压的3个值
call 二进制转十六进制ascall码
mov si,_ss-DOS起始
mov cx,9
rep movsb

mov ebx,esp
add ebx,3;减int指令压的3个值
call 二进制转十六进制ascall码
mov si,_esp-DOS起始
mov cx,6
rep movsb
mov si,di
dec si;减一以免取到下一个字符
std
call 打印
cld;恢复正序
jmp 停

栈错误 db 13,10,'Stack fault',0
_ss db '=)61*SS(+'
_esp db '=PSE',13,10



intD:
push eax
push bx
push esi
push ds
jmp 停





















;将会修改EAX，EBX，EDX，Di寄存器
;输入
;无
;输出
显示寄存器:
push ds
push es
push edi;保
mov di,DOS段地址/16
mov ds,di
mov es,di

;push edi
mov di,DOS结束-DOS起始+4096;在此处放置转换的ascall码
push eax
push ebx
push ecx
push esi
mov ax,0a00h;结束符
stosw

mov ebx,ebp
call 二进制转十六进制ascall码
mov si,_EBP寄存器-DOS起始
mov cx,7
rep movsb

mov ebx,esp
add ebx,20;减去我们在栈里压的一些东西
call 二进制转十六进制ascall码
mov si,_ESP寄存器-DOS起始
mov cx,7
rep movsb

mov ax,bp;save
mov bp,sp;什么C语言行为
mov ebx,dword[bp+16];EDi的值
mov bp,ax;复
call 二进制转十六进制ascall码
mov si,_EDi寄存器-DOS起始
mov cx,7
rep movsb

pop ebx;ESi的值
call 二进制转十六进制ascall码
mov si,_ESi寄存器-DOS起始
mov cx,7
rep movsb

mov ebx,edx
call 二进制转十六进制ascall码
mov si,_EDX寄存器-DOS起始
mov cx,7
rep movsb

pop ebx;ECX的值
call 二进制转十六进制ascall码
mov si,_ECX寄存器-DOS起始
mov cx,7
rep movsb

pop ebx;原EBX的值
call 二进制转十六进制ascall码
mov si,_EBX寄存器-DOS起始
mov cx,7
rep movsb

pop ebx;EAX的值
call 二进制转十六进制ascall码
mov si,_EAX寄存器-DOS起始
mov cx,7
rep movsb
add sp,4;栈平衡

mov si,di
dec si;减一以免取到下一个字符
std
call 打印
cld;恢复正序
pop es
pop ds
ret

_EBP寄存器 db '> PBE  '
_ESP寄存器 db '> PSE  '
_EDi寄存器 db '> iDE',10,13
_ESi寄存器 db '> iSE  '
_EDX寄存器 db '> XDE  '
_ECX寄存器  db '> XCE  '
_EBX寄存器 db '> XBE  '
_EAX寄存器 db '> XAE',10,13



DOS结束:

数据起始 equ DOS结束-DOS起始

参数起始 equ 数据起始

标志 equ 参数起始+0
db 0;注意
驱动器号 equ 标志+1;db
文件系统类型号 equ 驱动器号+1;db
扇区大小 equ 文件系统类型号+1;dw
逻辑扇区号 equ 扇区大小+2;dd
t_u8_1 equ 逻辑扇区号+4;db
t_u8_2 equ t_u8_1+1;db
文件属性号 equ t_u8_2+1;db
当前扇区偏移量 equ 文件属性号+1;dw
待转换字符位置 equ 当前扇区偏移量+2;dw
当前簇号 equ 待转换字符位置+2;dd
标记逻辑扇区号 equ 当前簇号+4;ddzz
t_u8_3 equ 标记逻辑扇区号+4;db
t_u32_1 equ t_u8_3+1;dd
t_u32_2 equ t_u32_1+4;dd
当前目录簇号 equ t_u32_2+4;dd
u8_1 equ 当前目录簇号+4;db
u8_2 equ u8_1+1;db
u8_3 equ u8_2+1;db
u8_4 equ u8_3+1;db
u8_5 equ u8_4+1;db
u8_6 equ u8_5+1;db
u8_7 equ u8_6+1;db
u8_8 equ u8_7+1;db
u16_1 equ u8_8+1;dw
u16_2 equ u16_1+2;dw
u16_3 equ u16_2+2;dw
u16_4 equ u16_3+2;dw
u16_5 equ u16_4+2;dw
u16_6 equ u16_5+2;dw
u16_7 equ u16_6+2;dw
u16_8 equ u16_7+2;dw
u32_1 equ u16_8+2;dd
u32_2 equ u32_1+4;dd
u32_3 equ u32_2+4;dd
u32_4 equ u32_3+4;dd
u32_5 equ u32_4+4;dd
u32_6 equ u32_5+4;dd
u32_7 equ u32_6+4;dd
u32_8 equ u32_7+4;dd
参数结束 equ u32_8+4

数据结束 equ 参数结束