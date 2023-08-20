;============================================================================
;集成文件系统
;垃圾NASM编译器不支持双org，需要额外计算相对位置
;我不会使用一些不直观的指令比如，xor ax,ax

;2023年
;该死的win系统损坏，害得我丢失亿些东西，只能重新写了
;----------------------------------------------------------------------------
;内存布局
DOS的基地址 equ 80000h;～8FFFF_Loader.BiN
缓存区 equ 90000h;～9b000


call 自定位

自定位 pop si
sub si,自定位
push si
add si,DOSstart
mov ax,cs
mov ds,ax;DS =CS
mov ax,DOS的基地址/16;复制到的位置
mov es,ax
mov di,0

mov fs,di;DS，ES段寄存器已被占用

mov cx,DOSEnd-DOSstart
mov bl,cl;save
shr cx,2;除以4，以便最高效复制
rep movsd;如果CX为0则什么都不操作
mov cl,bl;恢复
and cl,11b;只保留低二位
rep movsb;如果CX为0则什么都不操作


mov fs:[2],ax;现在写入我们的中断程序
mov bx,int0-DOSstart
mov fs:[0],bx

mov fs:[6],ax;段
mov bx,int_1-DOSstart
mov fs:[4],bx;偏

mov fs:[26],ax;24+2=26
mov bx,int6-DOSstart
mov fs:[24],bx;6×4=24

mov fs:[50],ax
mov bx,intC-DOSstart
mov fs:[48],bx

mov fs:[54],ax
mov bx,intD-DOSstart
mov fs:[52],bx

mov fs:[86h],ax
mov bx,int21-DOSstart
mov fs:[84h],bx


mov es:[驱动器号-DOSstart],dl;保存驱动器号
cmp bp,0AA55h;由我们的引导扇区过传来的判断数
jnz 无法确定文件系统类型

mov al,dh;修改文件系统编号
mov bx,2
int 21h
jc 无法确定文件系统类型
movzx bx,dh;由我们的引导扇区过传来的文件系统编号
shl bx,1;×2
mov bp,sp
movzx esp,bp;清空高位
pop bp;弹基地址
add bx,bp;加基地址
mov bx,[bx+文件系统];取值
add bx,bp;加基地址
jmp bx;跳转

文件系统:
dw 无法确定文件系统类型
dw iSO9660
dw FAT32
dw Joliet
dw 无法确定文件系统类型;UDF




iSO9660:
mov word es:[扇区大小-DOSstart],2048
mov eax,fs:[7c00h+3]
mov es:[当前目录簇号-DOSstart],eax
mov eax,fs:[7c00h+3+4]
mov es:[iSO9660目录长度-DOSstart],eax

mov bx,1;获取文件系统参数
int 21h
push bx
push di
push ecx;+6
push eax;+2
push dx;+0！

mov si,换行
add si,bp
call 打印

mov ax,BOOT
add ax,bp;加基地址
mov cx,4
mov dx,BOOT
add dx,bp;加基地址
mov si,4
mov di,1;文件夹
mov bx,9;打开一个文件或文件夹
int 21h
mov si,dx;没找到时显示的字符
jc 没有找到

mov bx,5;设置文件系统参数
int 21h
mov al,'/'
mov ah,14
mov bh,0;页码
int 10h

mov ax,COMMAND
add ax,bp;加基地址
mov cx,11
mov dx,COMMAND
add dx,bp;加基地址
mov si,11
mov di,0;文件
mov bx,9;打开一个文件或文件夹
int 21h
mov si,dx;没找到时显示的字符
jc 没有找到

mov bx,5;设置文件系统参数
int 21h
mov ecx,7000_0000h
sub cx,[esp];减应对推

继续读入:
add cx,[esp];推
mov bx,7
int 21h
jnc 继续读入

pop dx
pop eax
pop ecx
pop di
mov bx,5;设置为根
int 21h
pop bx;后弹出，这样就不会被调用功能号修改了
jmp 7000h:0h;进入命令处理程序





没有找到:
push si;原字符
mov si,None
add si,bp
call 打印
pop si
add si,bp
call 打印
mov si,换行
add si,bp
call 打印
int 18H;返回BiOS
jmp 停



换行 db 13,10,0
None db ' None ',0
BOOT db 'BOOT',0
COMMAND db 'COMMAND.BIN',13,10,0



Joliet:
ud2
call 显示寄存器
jmp $






FAT32:
mov ax,fs:[7c00h+11]
mov es:[扇区大小-DOSstart],ax
mov al,fs:[7c00h+13]
mov es:[每个簇占用的扇区数-DOSstart],al
mov eax,fs:[7c00h+44]
mov es:[当前目录簇号-DOSstart],eax
mov eax,fs:[7c00h+52+4];820，FAT起始
mov es:[iSO9660目录长度-DOSstart],eax
mov eax,fs:[7c00h+52+8];1Fe838，第一个数据扇区，全部值
mov es:[FAT数据区起始-DOSstart],eax
mov al,fs:[7c00h+64]
mov es:[驱动器号-DOSstart],al

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
mov bx,9;打开一个文件或文件夹
int 21h
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
mov bx,9;打开一个文件或文件夹
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










无法确定文件系统类型:
mov si,未知文件系统
;add si,bp
call 打印
CALL 显示寄存器
jmp $
jmp 8000h:0h;进入命令处理程序
未知文件系统 db '?File System?'




DOSstart:;Disk Operating System
int21:
mov cs:[0FFFbh],eax;保
pop eax;弹iP+CS
inc sp;删压的标志位，注意栈只能压word
inc sp
push eax;压返回地址
mov eax,cs:[0FFFbh];原
mov cs:[0FFFdh],ss
mov cs:[0FFFbh],sp;保存原栈
mov sp,DOS的基地址/16
mov ss,sp
mov esp,0FFFbh;顺便清空高位
cmp bx,10;最大支持几个功能-1
ja 带进位返回;大于则跳转

shl bx,1;×2
mov bx,cs:[bx+功能-DOSstart]
cmp bx,寻址表结束-DOSstart;地址已经不在表内所以不需要再次定位
JAE 不分文件系统;等于大于则跳转

push si;save
movzx si,byte cs:[文件系统编号-DOSstart];使用DS段寄存器
shl si,1;×2
mov bx,cs:[bx+si];BX是基地址，Si是表内偏移
pop si;原

不分文件系统 jmp bx;跳CS：BX

带进位返回 stc

返回:
pop sp;还原栈
mov ss,cs:[0FFFdh]
retf;iret是int指令专用返回


功能:
dw 0;获取功能号信息
dw 获取文件系统信息-DOSstart;1
dw 修改文件系统编号-DOSstart;2
dw 设置重新读取文件扇区-DOSstart;3
dw 获取一个文件项-DOSstart;4
dw 设置文件系统参数-DOSstart;5
dw 重置文件读入状态-DOSstart;6
dw 读入文件扇区-DOSstart;7
dw 解析MasterBootRecord-DOSstart;8
dw 打开一个文件或文件夹-DOSstart;9

获取一个文件项:
dw 0;null
dw iSO9660_1-DOSstart
dw FAT32_1-DOSstart

读入文件扇区:
dw 0;null
dw iSO9660_3-DOSstart
dw FAT32_3-DOSstart

打开一个文件或文件夹:
dw 0;null
dw iSO9660_4-DOSstart
dw FAT32_4-DOSstart

寻址表结束:;结束位置跟下面一项的地址重复了，所以需要大于等于跳转



;----------------------------------------------------------------------------
;输入
;无
;输出
;BX >文件系统编号
获取文件系统信息:;获取文件系统参数
mov eax,cs:[当前目录簇号-DOSstart]
movzx bx,cs:[文件系统编号-DOSstart]
cmp byte cs:[文件系统编号-DOSstart],1
jnz 不是iSO9660
mov ecx,cs:[iSO9660目录长度-DOSstart]
不是iSO9660 mov dx,cs:[扇区大小-DOSstart]
mov di,cs:[驱动器号-DOSstart];仅低位有效
jmp 返回

;输入
;AL >文件系统编号
修改文件系统编号:
cmp al,2
ja 带进位返回;大于则跳转
mov cs:[文件系统编号-DOSstart],al
clc;清除进位
jmp 返回

文件系统编号 db 0



;输入
;无
设置重新读取文件扇区:
mov byte cs:[重置读取-DOSstart],0
jmp 返回




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
call 获取一个iSO9660项
pop ds
pop si
pop ebx
jmp 返回



;输入
;AL =需要输入一次文件属性
;输出
;EAX >LBA
;ECX >扇区数据长度
;DX >文件名长度
;ES：Di >文件名
获取一个iSO9660项:
mov bx,DOS的基地址/16
mov ds,bx;段地址，int13ah42的DS：Si，磁盘参数块需要
mov es,bx;需要返回
test byte[标志-DOSstart],1b;被测试位 =0则ZF =1
jnz 不要重置


mov byte[文件属性-DOSstart],al;标记为文件
mov byte[文件属性_2-DOSstart],al
mov byte[文件属性_3-DOSstart],al
mov byte[文件属性_4-DOSstart],al
cmp al,0
jz 属性正确_1

mov byte[文件属性-DOSstart],2;错误的文件夹标记
mov byte[文件属性_2-DOSstart],2
mov byte[文件属性_3-DOSstart],2
mov byte[文件属性_4-DOSstart],2 
cmp al,1
jz 属性正确_1

mov [文件属性-DOSstart],al;第一个匹配就行了
;mov [文件属性_2-DOSstart],al
;mov [文件属性_3-DOSstart],al
;mov [文件属性_4-DOSstart],al
cmp al,0FFh;全部都要
jz 属性正确_1

stc;设置进位
ret

属性正确_1:
or byte[标志-DOSstart],1b;取消下次重置
mov eax,[当前目录簇号-DOSstart]
mov [逻辑扇区号-DOSstart],eax

mov eax,[iSO9660目录长度-DOSstart]
mov edx,0;清空除法高位
movzx ebx,word [扇区大小-DOSstart]
div ebx;edx高：eax低÷ebx =eax…edx
cmp dx,0
jz 没有超出_2;超出一个字节都需要读完整个扇区

inc ax

没有超出_2 mov [循环次数-DOSstart],ax
mov word[当前扇区偏移量-DOSstart],0FFFFh


不要重置:
mov di,[当前扇区偏移量-DOSstart]
mov ax,DOSEnd-DOSstart
add ax,[扇区大小-DOSstart]
cmp di,ax;当前扇区处理完了吗
jb 取一个项;小于则跳转

读下一个扇区:
cmp word[循环次数-DOSstart],0
jnz 还没读完

mov byte[标志-DOSstart],0;下次则从头开始
stc;设置进位
ret

还没读完:
dec word[循环次数-DOSstart]
mov eax,[逻辑扇区号-DOSstart]
inc dword[逻辑扇区号-DOSstart];推进到下一个扇区
mov edx,0;LBA高位
mov ebx,8000_0000h;缓存区，段地址
mov bx,DOSEnd-DOSstart;偏移地址，在此处放置扇区
call 读盘
add bx,[bx];跳过一个.目录
add bx,[bx];跳过一个..目录
mov [当前扇区偏移量-DOSstart],bx;刷
mov di,bx

取一个项:
cmp word [di],0;这个项的长度为0则
jz 读下一个扇区;触底

mov si,[di];取这个项的长度
add [当前扇区偏移量-DOSstart],si;原项+现项=预先推进到下一个项
add di,33;预先指向文件名长度
mov al,[di-33+25]
call 对比文件属性
jc 不要重置;不符合类型

mov eax,[di-33+2];2双端格式的范围位置 (LBA)，2~8÷2
mov ecx,[di-33+10];双端格式的数据长度（范围大小）
movzx dx,byte [di-1];取文件名长度
clc;清除进位
ret



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
call 获取一个FAT32项
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
获取一个FAT32项:
mov bx,DOS的基地址/16
mov ds,bx
mov bx,缓存区/16;段
mov es,bx
test byte[标志-DOSstart],1b;被测试位 =0则ZF =1
jnz 不要重置_2

;标记FAT文件属性
mov byte[文件属性-DOSstart],20h;文件
mov byte[文件属性_2-DOSstart],23h;隐藏的文件
mov byte[文件属性_3-DOSstart],20h;文件
mov byte[文件属性_4-DOSstart],20h;文件
cmp al,0
jz 属性正确

mov byte[文件属性-DOSstart],10h;文件夹
mov byte[文件属性_2-DOSstart],12h;隐藏的文件夹
mov byte[文件属性_3-DOSstart],30h;存档的文件夹
mov byte[文件属性_4-DOSstart],32h;隐藏存档的文件夹
cmp al,1
jz 属性正确

mov [文件属性-DOSstart],al;第一个匹配就行了
;mov [文件属性_2-DOSstart],al
;mov [文件属性_3-DOSstart],al
;mov [文件属性_4-DOSstart],al
cmp al,0FFh;全部都要
jz 属性正确

ret;属性错误，直接返回

属性正确:
mov eax,[当前目录簇号-DOSstart];取
mov [当前簇号-DOSstart],eax;存
or byte[标志-DOSstart],1b;取消下次重置
mov word[当前扇区偏移量-DOSstart],0a00h-32;存
mov byte[循环次数-DOSstart],1;触发读取簇


不要重置_2:
mov bx,[当前扇区偏移量-DOSstart];取

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

mov [当前扇区偏移量-DOSstart],bx;刷
mov ax,ds;交
mov cx,es
mov es,ax
mov ds,cx
mov si,bx;名
mov di,DOSEnd-DOSstart+2048;缓
mov cx,8;长
cmp byte[bx+12],0h
jnz no全部大写

处理文件名:
call 转成大写
call 分隔点.
call 转成大写
jmp 扩展名结束

no全部大写:
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

no全部小写:
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
sub dx,DOSEnd-DOSstart+2048;文件名缓存区，DX =文件名长度
mov di,DOSEnd-DOSstart+2048;Di =文件名位置
ret;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


长目录项:
mov word[待转换字符-DOSstart],DOSEnd-DOSstart+2048+2+26;字符缓存区，+2不覆盖结束符，+26以应对鬼畜的字符存储方式
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
mov di,es:[待转换字符-DOSstart];缓
call 取长目录项内字符
mov ax,0;结束符
stosw;存
mov bx,dx;revert
jmp 项结束


多条长项:;;;;1;;;;
mov di,bx;save
mov cl,es:[bx];第一个是特殊的项
cmp cl,40h
jb 不能⊕;小于则跳转

xor cl,40h;固定异或值

不能⊕ mov [项循环次数-DOSstart],cl;存项序号，减计数

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
mov di,es:[待转换字符-DOSstart];缓
call 取长目录项内字符;第一次有字符结束所以忽略进位
mov ax,0;结束符
stosw;存
mov dl,es:[项循环次数-DOSstart];取，项序号

继续取项内字符:;;;;2;;;;，内循环
cmp bx,09e0h
jb 不要环回;小于则跳转

mov bx,0-32;环回缓存区并应对预推

不要环回 add bx,32;推
dec dl
jz 项结束;已经结束嘞
lea si,[bx+1];跳过项序号
add word es:[待转换字符-DOSstart],26;应对这鬼畜的字符存储方式，不会出现没填满26个坑的情况
mov di,es:[待转换字符-DOSstart];缓存区
call 取长目录项内字符
jnc 继续取项内字符

mov word es:[待转换字符-DOSstart],DOSEnd-DOSstart+2048+2+26;出现错误，重置字符缓存区以废弃前面缓存的字符
mov word es:[DOSEnd-DOSstart+2048+26],0;结束符
jmp 继续取项内字符


项结束:;;;;;;;;注意，没有校验和
push word[bx+20];获取簇号高位
push word[bx+26];获取簇号低位
mov ax,es
mov ds,ax
mov [当前扇区偏移量-DOSstart],bx;刷
mov si,[待转换字符-DOSstart];字符起始
mov di,si;Di被推到了后面，还原以不覆盖待转换字符
;dec si;减一以免取到下一个字符
cld;正序
jmp 插♂入;第一次插♂入不需要减2

继续转换_1:;转换成UTF8
call UTF16转UTF8
jns wd2
stosb
jmp 持续插♂入
wd2 jc bwd3
stosw
jmp 持续插♂入
bwd3 stosb
shr eax,8;注意
stosw

持续插♂入 dec si
dec si
插♂入 movzx eax,word[si]
cmp ax,0
jnz 继续转换_1

pop eax;32位簇号
mov dx,di;字符结束
mov di,[待转换字符-DOSstart];字符起始
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
mov ax,[扇区大小-DOSstart]
dec ax;二进制位全部变1
test bx,ax;当前扇区处理完了吗，被测试位 =1，ZF =0
jnz 不用读盘

需要读盘:
dec byte[循环次数-DOSstart];减
jnz 不用下一个簇

mov eax,[当前簇号-DOSstart];取
call 簇号转逻辑扇区号
mov [逻辑扇区号-DOSstart],eax;刷
mov [循环次数-DOSstart],dl
jc 结束了自带进位

mov eax,[当前簇号-DOSstart];取
call 计算下一个簇号
mov [当前簇号-DOSstart],eax;刷

mov eax,[逻辑扇区号-DOSstart];revert，再取

不用下一个簇:
mov eax,[逻辑扇区号-DOSstart];取
mov edx,0;LBA高位
or ebx,1001_0000_0000_0000_0000_0000_0000_0000b;段，不能修改在低位的偏移值
;add bx,[扇区大小-DOSstart];偏
call 读盘
inc dword[逻辑扇区号-DOSstart];推

不用读盘 ret

结束了自带进位 mov byte[标志-DOSstart],0;重置读取
pop ax;删call指令压的返回地址，随便弹一个寄存器都行
ret;直接返回



;将会修改AX，CX，Si，Di寄存器，DF标志位
;输入
;DS：Si =UTF16字符
;输出
;ES：Di =倒序的UTF16字符
取长目录项内字符:
mov cx,5;共10个byte

取项内字符_1:
 cld;正
 lodsw;取
 cmp ax,0;结束符
 jz 返回错误

 std;倒
 stosw;存
loop 取项内字符_1

add si,3;跳过1个表示长目录项的0F，1个表示子的项固定值0，1个校验位？
mov cx,6;共12个byte

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
mov cx,2;共4个byte

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



重置读取 db 0
标志 db 0;第一次一定要重置
逻辑扇区号 dd 0
LBA dd 0
循环次数 db 0
项循环次数 db 0
当前扇区偏移量 dw 0
待转换字符 dw 0
文件属性 db 0
文件属性_2 db 0
文件属性_3 db 0
文件属性_4 db 0



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
movzx ebx,word[扇区大小-DOSstart]
shr bx,2;512÷4，每个扇区可保存的目录数
xor edx,edx;空
div ebx;EAX >扇区号，DX >目录内偏移
shl dx,2;×4
push dx;读盘会修改DX我们要提前保存

add eax,[iSO9660目录长度-DOSstart];你得到了LBA号，FAT起始
cmp eax,[标记LBA号-DOSstart];在同一张FAT内？
jz 读取簇号;上次读过这张FAT表

mov [标记LBA号-DOSstart],eax
mov edx,0;LBA高位
mov ebx,8000_0000h;段地址
mov bx,DOSEnd-DOSstart+1024;偏移地址，用于缓存FAT表，不能被其他东西覆盖
call 读盘;只需要读一个扇区的FAT表即可

读取簇号:
pop bx;恢复我们的FAT表内偏移
and byte[bx+3+DOSEnd-DOSstart+1024],1111b;屏蔽前4位，FAT32其实只有28位簇号
mov eax,dword[bx+DOSEnd-DOSstart+1024];读取我们需要的簇号
pop bx;revert
ret

当前簇号 dd 0
标记LBA号 dd 0



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
jae 链表末端;等于大于则跳转，这是簇链的结束标志

dec eax
dec eax

movzx edx,byte[每个簇占用的扇区数-DOSstart];使用扩位传送覆盖DX的高位以进行32位乘法
push dx;只有这个寄存器未被使用
mul edx;edx是乘法的高位但我们不允许eax溢出到高位
pop dx;不用压桟EDX以节省空间

add eax,[FAT数据区起始-DOSstart];数据区起始扇区号
ret;此时进位未设置，除非参数错误

链表末端 stc;通过进位表示结束
ret

每个簇占用的扇区数 db 0
FAT数据区起始 dd 0



;不会修改寄存器
;输入
;AL =属性
;输出
;CF =1=属性错误
对比文件属性:
cmp byte[文件属性-DOSstart],0FFh;任何属性都要
jz 属性匹配

cmp al,[文件属性-DOSstart]
jz 属性匹配

cmp al,[文件属性_2-DOSstart]
jz 属性匹配

cmp al,[文件属性_3-DOSstart]
jz 属性匹配

cmp al,[文件属性_4-DOSstart]
jz 属性匹配

stc;设置进位
ret

属性匹配 clc;清除进位
ret




;----------------------------------------------------------------------------

;输入
;EAX =当前目录簇号
;ECX =iSO9660目录长度，不是iSO9660则无视他
;输出
;无
设置文件系统参数:
cmp byte cs:[文件系统编号-DOSstart],1
jnz 不是iSO9660_1
mov cs:[iSO9660目录长度-DOSstart],ecx;或FAT表起始
不是iSO9660_1 mov cs:[当前目录簇号-DOSstart],eax
mov byte cs:[标志-DOSstart],0
jmp 返回

当前目录簇号 dd 0
iSO9660目录长度 dd 0



;输入
;无
;输出
;无
重置文件读入状态:
mov byte[重置读取-DOSstart],1
jmp 返回





;输入
;EC段|CX偏 ECX=缓存区
;输出
;读出一个扇区
;读入文件扇区:
iSO9660_3:
push eax
push ebx
push dx
push si
push ds
mov ax,DOS的基地址/16
mov ds,ax

test byte[标志-DOSstart],1b;被测试位 =0则ZF =1
jnz 不要重置_1

or byte[标志-DOSstart],1b;设置为1下次就不会重新读文件扇区了
mov eax,[当前目录簇号-DOSstart]
mov [逻辑扇区号-DOSstart],eax

mov eax,[iSO9660目录长度-DOSstart]
mov edx,0;清空除法高位
movzx ebx,word[扇区大小-DOSstart]
div ebx;edx高：eax低÷ebx =eax…edx
cmp dx,0
jz 没有超出_3;超出一个字节都需要读完整个扇区

inc ax

没有超出_3 inc ax;预推应对预减
mov[循环次数-DOSstart],ax

不要重置_1:
mov eax,[逻辑扇区号-DOSstart]
inc dword[逻辑扇区号-DOSstart];推进到下一个扇区
mov edx,0;LBA高位
mov ebx,ecx;缓存区址
call 读盘
dec word[循环次数-DOSstart]
pop ds
pop si
pop dx
pop ebx
pop eax
jnz 返回;正常返回，下次还来

mov byte[标志-DOSstart],0;下次则从头开始
jmp 带进位返回;读取完毕



;输入
;ECX =缓存区的段地址：偏移地址
;输出
FAT32_3:
push eax
push ebx
push edx
push si
push ds
mov ax,DOS的基地址/16
mov ds,ax

test byte[标志-DOSstart],1b;被测试位 =0则ZF =1
jnz 不要重置_3


or byte[标志-DOSstart],1b;设置为1下次就不会重新读文件扇区了
mov eax,[当前目录簇号-DOSstart]
mov [当前簇号-DOSstart],eax;刷
mov byte[循环次数-DOSstart],1;触发计算簇


不要重置_3:
dec byte[循环次数-DOSstart];每个簇占用的扇区数
jnz  继续读取_1;还不用下一个簇

mov eax,[当前簇号-DOSstart]
call 簇号转逻辑扇区号
jc 读取完毕_1

mov [逻辑扇区号-DOSstart],eax;刷
mov [循环次数-DOSstart],dl

mov eax,[当前簇号-DOSstart]
call 计算下一个簇号
mov [当前簇号-DOSstart],eax;存

继续读取_1:
mov eax,[逻辑扇区号-DOSstart]
inc dword[逻辑扇区号-DOSstart];推进到下一个扇区
mov edx,0;LBA高位
mov ebx,ecx
call 读盘

Do返回_1:
pop ds
pop si
pop edx
pop ebx
pop eax
jmp 返回

读取完毕_1:
mov byte[标志-DOSstart],0;已读完，下次重新开始
;自带进位
jmp Do返回_1






解析MasterBootRecord:
mov eax,0;第一个扇区一般为MBR，也有可能是DBR
mov edx,0;LBA高位
mov ebx,9000_0000h;缓存区，段地址
mov bx,DOSEnd-DOSstart;偏移地址，在此处放置扇区
call 读盘
cmp dword[bx+510],0AA55h;判断数
jz 分区表正常
mov si,未检测到分区表
call 打印
jmp $
未检测到分区表 db 'invalid partition table',13,10,'Try using the fs command directly',13,10,0

分区表正常 jmp $








;输入
;AX =第一个文件名位置
;CX =第一个文件名长度
;DX =第二个文件名位置
;Si =第二个文件名长度
;Di =文件属性
;输出
;EAX =LBA号
;ECX =数据长度
iSO9660_4:
push ebx
push di
push es
push ax;+12，1名
push dword 1;+8 =上一串字符长度应该是0但使用此值会导致某些BiOS清空全屏（应该是直接dec cx而没有做判断导致的）所以使用1来解决，+10 =光标位置
push dx;+6，2名
push ds;+4 =段地址
push cx;+2 =1长
push si;+0！ =2长

call 获取光标位置
mov [esp+10],dx;刷，光标位置
mov ax,di;需要一次文件属性

继续查找项_1:
call 获取一个iSO9660项
jc 没有匹配项_1

push ax;save，+4 =LBA
push cx;+2 =iSO9660数据长度
push dx;+0！ =名长

mov dx,[esp+4+2+10];光标位置
mov cx,[esp+4+2+8];上一串字符长度
call 重置光标并清除前文件名
mov cx,[esp];save，长
mov dx,di;save，名
call 显示项名
mov di,dx;revert，名

pop dx;revert，名长
pop cx;iSO9660数据长度
pop ax;LBA
cmp dx,[esp+2];源文件1名长度
jnz 试第二项;第一项不匹配

mov ds,[esp+4];段	
mov si,[esp+12];源文件名1
mov bx,di;save，名
repe cmpsb
jz 没有匹配项_1;找到了，项名匹配

mov di,bx;revert，名

试第二项:
cmp dx,[esp];源文件2名长度
jnz 继续查找项_1;错误的文件名长度

push ax;save，LBA
push cx;iSO9660数据长度
mov cx,dx;长
mov bx,di;名
call 转成大写_1
mov di,bx;revert，名
pop cx;iSO9660数据长度
pop ax;LBA
xchg cx,dx
mov ds,[esp+4];段	
mov si,[esp+6];源文件名2
repe cmpsb
mov cx,dx;iSO9660数据长度
jnz 继续查找项_1

没有匹配项_1:
pop si
pop cx
pop ds
pop dx
pop ebx;栈平衡，删压的上一串字符长度和光标位置
pop bx;删压的第一个文件名位置，不能破坏LBA
pop es
pop di
pop ebx
jmp 返回















;输入
;AL =属性
;CX =文件名长度
;DS：Si =文件名位置
;输出
;EAX =簇号
FAT32_4:
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
call 获取一个FAT32项
jc 没有匹配项

mov esi,eax;save，簇
push dx;+0！，save，长
mov dx,[esp+10+2];光标位置
mov cx,[esp+8+2];上一串字符长度
call 重置光标并清除前文件名
mov cx,[esp];长
mov dx,di;save，名
call 显示项名
mov di,dx;原，名
pop dx;原，长
cmp dx,[esp];源文件名长度
jnz 继续查找项;错误的文件名长度

mov bx,di;save，名
mov cx,dx;长
call 转成大写_1
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
mov bl,al;save，属性
mov ah,3;调用号
mov bh,0;页码
int 10h; AX =0000h(Phoenix BIOS)，CH =起始扫描线，CL =结束扫描线，DH =行（00h 位于顶部），DL =列（00h 位于左侧）
mov al,bl;原
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
;输出
显示项名:
mov ah,14;功能号
mov bh,0;页码

显示路径_1 mov al,es:[di];取
 inc di;推
 int 10h
loop 显示路径_1
ret



;AL，CX，Di寄存器将会被修改
;输入
;CX =字符长度
;ES：Di =字符位置
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







;----------------------------------------------------------------------------

;EAX，EBX，EDX，Di寄存器将会被修改
;输入
;EAX >待转换数值
;ES：Di >缓存区
;输出
;ES：Di >10进制ascall码，结尾为0，注意倒序应使用std指令
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



;EAX寄存器将会被修改
;输入
;EAX_AX =UTF16字符
;输出
;SF =0，含AL
;SF =1，含AX
;SF =1+CF =1，含AL+AX
;AL_AX =UTF8字符
UTF16转UTF8:
cmp eax,128;ascll7Fh个
jns 不是英文;EAX<128，则SF=1，因为被反转0172-0128=9998，负数则跳转
;，标记为只有AL
ret

不是英文:
cmp eax,800h;注意，为什么要这样做
jnc 超过word
shl eax,2
shr al,2
or eax,1100000010000000b
xchg al,ah;大端转小端存储
cmp eax,0FFFFFFFFh;SF =1
ret

超过word:;注意，我完全不知道在干什么
shl eax,4
shr ax,2
shr al,2
or eax,111000001000000010000000b
bswap eax;大端转小端存储
shr eax,8
;stosb
;shr eax,8;注意
;stosw
cmp eax,0FFFFFFFFh;SF =1
stc;CF =1，标记为+AL
ret



;AX，Si，Di寄存器将会被修改
;输入
;DS：Si =字符
;输出
;ES：Di =缓存区
UTF8转UTF16:
lodsb;读取一个UTF8字符
cmp al,0
jz UTF8转换结束

shl ax,8;移动到AH
stosw
jmp UTF8转UTF16;继续转换

stc

UTF8转换结束 ret




;将会修改EAX，DX，Si寄存器
;从硬盘读取一个扇区数据
;输入
;EAX =LBA低32位
;EDX =LBA高32位
;EBX =高32位段地址+低32位偏移地址
;输出
读盘:;读硬盘调用+增加dpa包是加扇区
;nop;注意Bug，参数正确但有时候依然无法读入扇区
mov [偏移地址-DOSstart],ebx;低位段地址，高位偏移地址
mov [LBA低位-DOSstart],eax
mov [LBA高位-DOSstart],edx
mov si,参数块-DOSstart
mov dl,[驱动器号-DOSstart]
mov ah,42h;扩展调用
int 13h
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


;----------------------------------------------------------------------------


继续打印:;每个指令都很重要确保他们被正确执行
 mov bh,0;页码
 mov ah,14;BiOS中断参数
 int 10h;显示字符

 打印:
 lodsb;将DS：Si指向的内容放入al然后Si+1
 or al,al;判断al中的字符值是否 =0
jnz 继续打印
ret



int0:
push si
mov si,除法错误-DOSstart
push ax
push bx
push DOS的基地址/16;数据段
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
mov ax,DOS的基地址/16
mov ds,ax
push bx;+0！
mov bx,sp
or word ss:[bx+6+4],100h
push si
mov si,哞-DOSstart
call 打印
pop si
pop bx
pop ax
pop ds
iret

哞 db 'Moo~',0
; push bx
; pushf
; mov bx,sp
; or word ss:[bx],100h
; popf
; pop bx



int6:;遇到错误指令或使用ud2指令触发
mov ebx,DOS的基地址/16;顺便清空高位
mov ds,bx
mov es,bx

mov di,DOSEnd-DOSstart+2048;在此处放置转换的ascall码
mov eax,0a00h;换行+结束符，顺便清空高位
stosw

pop ax;iP
mov ebx,0
pop bx;CS
sub sp,4;复
shl ebx,4;×16
add ebx,eax;+iP
call 二进制转十六进制ascall码
mov si,_cs_ip-DOSstart
mov cx,11
rep movsb

mov si,di
dec si;减一以免取到下一个字符
std
call 打印
cld;恢复正序

mov si,错误的操作码-DOSstart
call 打印

pop bx;iP
pop fs;CS
inc sp;删int指令压的标志，遵循栈平衡的优良传统
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
 ;cli;会导致某些虚拟机报错
 hlt
jmp short 停

_cs_ip db '=Pi+61*SC',10,13
错误的操作码 db 13,'Undefined opcode_',0



intC:;#SS，栈溢出
mov ebx,DOS的基地址/16;顺便清空高位
mov ds,bx
mov es,bx

mov si,栈错误-DOSstart
call 打印

mov di,DOSEnd-DOSstart+2048;在此处放置转换的ascall码
mov al,0;结束符
stosb

mov bx,ss
shl ebx,4;×16
add ebx,esp
add ebx,3;减int指令压的3个值
call 二进制转十六进制ascall码
mov si,_ss-DOSstart
mov cx,9
rep movsb

mov ebx,esp
add ebx,3;减int指令压的3个值
call 二进制转十六进制ascall码
mov si,_esp-DOSstart
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



intD:;下次支持其他段寄存器
push eax
push bx
push esi
push ds

in al,92h;打开A20
or al,10b
out 92h,al

movzx esi,sp;不能使用ESP
mov ds,ss:[si+12+2];段，跳过压的寄存器
mov si,ss:[si+12];偏
mov al,[si];取操作码

mov si,DOS的基地址/16
mov ds,si

mov word[显示段寄存器-DOSstart],'ES'
mov si,0;判断数
cmp al,26h
jz 是这个段寄存器了

mov word[显示段寄存器-DOSstart],'FS'
mov si,1;判断数
cmp al,64h
jz 是这个段寄存器了

mov word[显示段寄存器-DOSstart],'GS'
mov si,2;判断数
cmp al,65h
jz 是这个段寄存器了

mov word[显示段寄存器-DOSstart],'DS'
mov si,3;这个也要判断数

;不能使用CS，SS（36），因为无法ret
是这个段寄存器了:
push si;保
mov si,显示段寄存器-DOSstart-1;-1以显示回车换行
call 打印

mov si,Gdtcfg-DOSstart
lgdt [si];读入GDT长度及位置
pop si;原
mov eax,cr0
or al,1b
cli;关中断
mov cr0,eax
jmp 8:ProtectedMode-DOSstart

ProtectedMode:
mov bx,16;第2个描述符
cmp si,0

jnz no0

mov ES,bx

no0 cmp si,1

jnz no1

mov FS,bx

no1 cmp si,2

jnz no2

mov GS,bx

no2 cmp si,3

jnz no3

mov DS,bx

no3 and al,1111_1110b
mov cr0,eax
jmp DOS的基地址/16:RealMode-DOSstart

RealMode:
inc sp;先删DS
inc sp
cmp word[显示段寄存器-DOSstart],'DS'
jz 是_ds

dec sp;判断错误，撤销操作
dec sp
pop ds

是_ds:;判断正确，继续
pop esi
pop bx
pop eax
iret;已压标志，不需要指令sti打开中断

db 10;换行
显示段寄存器 dw 0;字符？
db ' is set to big real mode',13,0

Gdtcfg:
dw GdtEnd-GdtStart-1;长度-1以忽略后一字节
dd GdtStart-DOSstart+DOS的基地址;+基地址
GdtStart:
dq 0h;听说设置个空的段描述符是为了防止从16位实地址模式切换到32位保护模式后忘记设置段寄存器引发的问题。

;保护模式
dw 0FFFFh;段长度
db 0,0_,DOS的基地址/10000h;08;基地址00_0000h
db 10011010b;段属性
db 0000_0000b;段属性_段长度0000b
db 0;基地址00h

;大实模式
dw 0FFFFh;段长度
db 0,0,0;基地址
db 10010010b;段属性
db 1100_1111b;段属性_段长度1111b
db 0;基地址00h
GdtEnd:






;将会修改EAX，EBX，EDX，Di寄存器
;输入
;无
;输出
显示寄存器:
push ds
push es
push edi;保
mov di,DOS的基地址/16
mov ds,di
mov es,di

;push edi
mov di,DOSEnd-DOSstart+4096;在此处放置转换的ascall码
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

mov ax,bp;save
mov bp,sp;什么C语言行为
mov ebx,dword[bp+16];EDi的值
mov bp,ax;复
call 二进制转十六进制ascall码
mov si,_EDi寄存器-DOSstart
mov cx,7
rep movsb

pop ebx;ESi的值
call 二进制转十六进制ascall码
mov si,_ESi寄存器-DOSstart
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









DOSEnd: