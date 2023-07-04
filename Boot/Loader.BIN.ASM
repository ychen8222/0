;============================================================================
;集成文件系统，难度★★★★★
;垃圾NASM编译器不支持双org，需要额外计算相对位置
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

mov fs:[2h],ax;现在写入我们的中断程序
mov bx,int0-DOSstart;加上我们的基地址10h
mov fs:[0h],bx

mov fs:[26],ax;段
mov bx,int6-DOSstart
mov fs:[24],bx;偏

mov fs:[54],ax;52+2=54
mov bx,intD-DOSstart
mov fs:[52],bx;13×4=52

mov fs:[86h],ax
mov bx,int21-DOSstart
mov fs:[84h],bx


mov es:[驱动器号-DOSstart],dl;保存驱动器号
cmp bp,0aa55h;由我们的引导扇区过传来的判断数
jnz 无法确定文件系统类型
cmp dh,4
ja 无法确定文件系统类型;大于则跳转

movzx bx,dh;由我们的引导扇区过传来的文件系统编号
shl bx,1;×2
add bx,文件系统
pop bp;弹基地址
add bx,bp
mov bx,[bx]
add bx,bp;加基地址
jmp bx

文件系统:
dw 无法确定文件系统类型
dw iso9660
dw Joliet
dw 无法确定文件系统类型;UDF
dw FAT32



iso9660:
mov byte es:[文件系统编号-DOSstart],1
mov word es:[扇区大小-DOSstart],2048
mov eax,fs:[7c00h+3]
mov es:[当前目录簇号-DOSstart],eax
mov eax,fs:[7c00h+3+4]
mov es:[iSO9660目录长度-DOSstart],eax


movzx di,dl;驱动器号
mov bx,1;获取文件系统参数
int 21h
pushad;push all压栈全部寄存器

mov ax,9000h
mov es,ax
mov word[第一个文件名+bp],Boot+3
mov word[第二个文件名+bp],BOOT+3
mov word[文件名长度+bp],4
call 获取文件项
jc 没有找到_2

mov bx,5;设置文件系统参数
int 21h
sub si,3
call 打印

mov word[第一个文件名+bp],Command
mov word[第二个文件名+bp],COMMAND
mov word[文件名长度+bp],11
call 获取文件项
jc 没有找到_2

mov bx,5;设置文件系统参数
int 21h
call 打印


popad;获取扇区大小
pushad;续
mov eax,8000_0000h

没有找到_1:
push dx
push eax
mov bx,7
int 21h
pop eax
pop dx;扇区大小
pushf;压标志位
add ax,dx;推
popf
jnc 没有找到_1


popad;传递参考数据
push bx
mov bx,5;设置为根
int 21h
pop bx
jmp 8000h:0h;进入命令处理程序


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
repe cmpsb
pop di
mov si,[第一个文件名+bp]
jz 找到了


cmp word[第二个文件名+bp],0
jz 获取文件项;没有段文件名
mov si,[第二个文件名+bp]
add si,bp
mov cx,[文件名长度+bp]
repe cmpsb
mov si,[第二个文件名+bp]
jnz 获取文件项;没有找到
没有找到:
找到了:
mov cx,[原CX值+bp]
pushf;不能破坏标志位
add si,bp
popf
ret


没有找到_2:
dec si;漏出我们的换行
dec si
call 打印
mov si,None
call 打印
jmp $

第一个文件名 dw 0
第二个文件名 dw 0
原CX值 dw 0
文件名长度 dw 0

Boot db 13,10,'/Boot/',0
BOOT db 13,10,'/BOOT/',0
Command db 'Command.BIN',0
COMMAND db 'COMMAND.BIN',0
;OCommand db 0,'C',0,'o',0,'m',0,'m',0,'a',0,'n',0,'d',0,'.',0,'B',0,'I',0,'N'
None db 'None',0


Joliet:
ud2
call 显示寄存器
jmp $







FAT32:
mov edi,0ffffffh
mov gs:[edi],eax
mov gs:[edi],al



mov al,2
mov bx,2;修改文件系统编号
int 21h
mov ax,fs:[7c00h+11]
mov es:[扇区大小-DOSstart],ax
mov al,fs:[7c00h+13]
mov es:[每个簇占用的扇区数-DOSstart],al
mov eax,fs:[7c00h+44]
mov es:[当前目录簇号-DOSstart],eax
mov eax,fs:[7c00h+52+4];820，fat表起始
mov es:[iSO9660目录长度-DOSstart],eax
mov eax,fs:[7c00h+52+8];1fe838，第一个数据扇区，全部值
mov es:[FAT数据区起始-DOSstart],eax




aaaa:
mov bx,4;获取一个文件项
int 21h
mov si,di
mov ax,9000h
mov ds,ax


mov al,10
 xor bx,bx
 mov ah,14;BIOS中断参数
 int 10h;显示字符
mov al,13
 int 10h;显示字符
mov cx,dx
mmu lodsb


 xor bx,bx
 mov ah,14;BIOS中断参数
 int 10h;显示字符
loop mmu
jmp $

jnc aaaa



jmp $
ud2












无法确定文件系统类型:
CALL 显示寄存器
jmp $
jmp 8000h:0h;进入命令处理程序





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
mov sp,9000h
mov ss,sp
mov esp,0FFFbh
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
dw 获取文件系统信息-DOSstart;1
dw 修改文件系统编号-DOSstart;2

dw 设置重新读取文件扇区-DOSstart;3
dw 获取一个文件项-DOSstart;4
dw 设置文件系统参数-DOSstart;5

dw 重置文件读入状态-DOSstart;6
dw 读入文件扇区-DOSstart;7


;----------------------------------------------------------------------------
;输入
;无
;输出
;BX >文件系统编号
获取文件系统信息:
mov eax,cs:[当前目录簇号-DOSstart]
movzx bx,cs:[文件系统编号-DOSstart]
mov ecx,cs:[iSO9660目录长度-DOSstart]
mov dx,cs:[扇区大小-DOSstart]
jmp 返回

;输入
;AL >文件系统编号
修改文件系统编号:
mov cs:[文件系统编号-DOSstart],al
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
add bx,文件系统_1-DOSstart
cmp bx,3*2
stc;设置进位
ja 返回;大于则跳转
mov si,9000h
mov ds,si;段地址，int13ah42的DS：SI，磁盘参数块需要
mov bx,[bx]
jmp bx

文件系统_1:
dw 0;null，错误处理
dw iSO9660_1-DOSstart
dw FAT32_1-DOSstart
;dw -DOSstart



;输入
;无
;输出
;EAX >LBA
;ECX >扇区数据长度
;DX >文件名长度
;9000h：DI >文件名
iSO9660_1:
push si
push bx
cmp byte[重置读取-DOSstart],0;标志
jz 不要重置
mov byte[重置读取-DOSstart],0;设置为0下次就不会重新读文件扇区了
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
mov byte[重置读取-DOSstart],1;下次则从头开始
stc;设置进位
pop bx
pop si
jmp 返回

还没读完:
dec word[循环次数-DOSstart]
mov eax,[LBA-DOSstart]
inc dword[LBA-DOSstart];推进到下一个扇区
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
mov si,[di];取这个项的长度
add [当前扇区偏移量-DOSstart],si;预先推进到下一个项
mov eax,[di+2];2双端格式的范围位置 (LBA)，2~8÷2
mov ecx,[di+10];双端格式的数据长度（范围大小）
add di,33;指向文件名长度
movzx dx,byte [di-1];取文件名长度
clc;清除进位
pop bx
pop si
jmp 返回




;输入
;无
;输出
;CX >文件名长度
;EAX >LBA
;DS：SI >文件名位置
FAT32_1:
cmp byte[重置读取-DOSstart],0;标志
jz 不要重置_2
mov byte[重置读取-DOSstart],0;设置为0下次就不会重新读文件扇区了
mov eax,[当前目录簇号-DOSstart]
mov [当前簇号-DOSstart],eax
;mov eax,[当前簇号-DOSstart]
call 簇转LBA
mov [LBA-DOSstart],eax
dec dl;减去一次
mov [循环次数-DOSstart],dl;每个簇占用的扇区数

mov edx,0;清空LBA高位
mov ebx,9000_0000h;缓存区，段地址
mov bx,DOSEnd-DOSstart;偏移地址，在此处放置扇区
call 读盘
mov [当前扇区偏移量-DOSstart],bx
inc dword[LBA-DOSstart]

;;;;;;jmp $
不要重置_2:;探索项；；；；
mov bx,[当前扇区偏移量-DOSstart]
mov ax,DOSEnd-DOSstart
add ax,[扇区大小-DOSstart]
cmp bx,ax;当前扇区处理完了吗
jb 还可以继续取值;小于则跳转

本项已被删除:;下面跳到这里
call 推到下一个项
还可以继续取值 mov [当前扇区偏移量-DOSstart],bx;不会错误
mov si,bx
cmp byte[bx],0e5h;删除的标志
jz 本项已被删除
cmp byte[bx+11],0Fh;长目录项固定值
jnz 本项已被删除;不是长目录项

;是长目录项
mov di,DOSEnd-DOSstart+2048;+2+26;字符缓存区，+2不覆盖结束符，+26以应对鬼畜的字符存储方式
mov ax,0;填充上一次的数据以保证结束符准确
mov cx,14
rep stosw
mov [待转换字符-DOSstart],di
cmp byte[bx],41h;1∨40h=41h
jnz 是多条长项
inc si;跳过项的序号
call 取项内字符
jmp 项结束


是多条长项:
mov al,[bx];第一个是特殊的项;;;;1;;;;
and al,40h;∧固定值
;dec al;减计数
mov [循环次数-DOSstart+1],al;项序号
mov si,bx
inc si;跳过项的序号
mov [待转换字符-DOSstart],di
call 取项内字符;第一次有字符结束所以忽略进位
;jmp 推到下一个项;此项已取完，注意

继续取项内字符:;;;;2;;;;，内循环
dec byte[循环次数-DOSstart+1];项序号
mov al,[循环次数-DOSstart+1]
cmp [bx],al
jnz 此项正常

此项异常:
mov di,DOSEnd-DOSstart+2048;+2+26;字符缓存区，+2不覆盖结束符，+26以应对鬼畜的字符存储方式
mov ax,0;填充上一次的数据以保证结束符准确
mov cx,14
rep stosw
mov [待转换字符-DOSstart],di;更新
call 推到下一个项
jmp 继续取项内字符

此项正常:;;;;
mov si,bx
inc si;跳过项的序号
add word[待转换字符-DOSstart],26;应对这鬼畜的字符存储方式，不会出现没填满26个坑的情况
mov di,[待转换字符-DOSstart];缓存区
call 取项内字符
jc 此项异常;没填满
cmp byte[循环次数-DOSstart+1],1;项序号
jnz 继续取项内字符;已经结束嘞

项结束:
call 推到下一个项
push word[bx+20];获取簇号高位
push word[bx+26];获取簇号低位

add bx,32;任意一个项占用的长度
mov [当前扇区偏移量-DOSstart],bx
mov si,[待转换字符-DOSstart];字符起始
mov di,si;DI被推到了后面，还原以不覆盖待转换字符
;dec si;减一以免取到下一个字符
cld;正序
jmp 插♂入;第一次插♂入不需要减

继续转换_1:
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

mov dx,di;字符结束
mov di,[待转换字符-DOSstart];字符起始
sub dx,di;字符结束-字符起始=字符长度
pop eax;转换为32位簇号
;jmp $
jmp 返回;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


推到下一个项:
add bx,32;任意一个项占用的长度
mov ax,DOSEnd-DOSstart
add ax,[扇区大小-DOSstart]
cmp bx,ax;当前扇区处理完了吗
jb 不用读盘;小于则跳转
dec byte[循环次数];;;;3;;;;
jnz 不用下一个簇

mov eax,[当前簇号-DOSstart]
call 计算下一个簇号
mov [当前簇号-DOSstart],eax;存
call 簇转LBA
jc 返回;结束了
mov [LBA-DOSstart],eax
mov [循环次数-DOSstart],dl

不用下一个簇:
mov eax,[LBA-DOSstart]
mov edx,0;清空LBA高位
mov ebx,9000_0000h;缓存区，段地址
mov bx,DOSEnd-DOSstart;偏移地址，在此处放置扇区
call 读盘
inc dword[LBA-DOSstart]
不用读盘 ret





;将会修改AX，CX，SI，DI寄存器，DF标志位
;输入
;DS：SI =UTF16字符
;输出
;ES：DI =倒序的UTF16字符
取项内字符:
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





重置读取 db 1;第一次一定要重置
LBA dd 0
循环次数 dw 0;有些会分一半来用
当前扇区偏移量 dw 0
待转换字符 dw 0








;将会修改EAX,EDX寄存器
;输入
;EAX >目标簇号
;输出
;EAX >LBA号
;EDX_DL >簇占用的扇区数
;如果链表末端则设置进位，EAX，EDX不变，链表结束
;乘法
;al×bl =ax，被乘数×被乘数 =积
;EAX×EDX =EDX高：低EAX
;算法
;（簇号-2）×每个簇占用的扇区数+数据区起始扇区号 =簇的lba号
簇转LBA:
cmp eax,0FFFFFF8h;如果链表结束
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


;给定一个簇号，找出下一个簇号
;簇号÷（扇区大小×4） =商×4，扇区号……余数，目录内偏移
;输入
;EAX >簇号
;输出
;EAX >下一个簇号
;除法
;ax÷bl =al……ah，被除数÷除数 =商……余数
;EDX高：EAX低÷EBX =EAX……EDX
;算法
;扇区大小÷4
计算下一个簇号:
movzx ebx,word[扇区大小-DOSstart]
shr bx,2;512÷4，每个扇区可保存的目录数
xor edx,edx;清空高位
div ebx;EAX >扇区号，DX >目录内偏移
shl dx,2
push dx;读盘会修改DX我们要提前保存

add eax,[iSO9660目录长度-DOSstart];你得到了LBA号，FAT表起始
cmp eax,[标记LBA号-DOSstart];在同一张fat表内？
jz 读取簇号;上次读过这张FAT表
mov [标记LBA号-DOSstart],eax
mov bx,fs;
mov edx,0;清空LBA高位
mov ebx,9000_0000h;缓存区，段地址
mov bx,DOSEnd-DOSstart;偏移地址
add bx,[扇区大小-DOSstart];过一个扇区，不能被覆盖
call 读盘;只需要读一个扇区的FAT表即可

读取簇号:
pop di;恢复我们的FAT表内偏移
and byte fs:[di+3],0Fh;屏蔽前4位，FAT32其实只有28位簇号
mov eax,dword fs:[di];读取我们需要的簇号
ret

当前簇号 dd 0
标记LBA号 dd 0













;输入
;无
;输出
; >文件参数
设置文件系统参数:
movzx bx,cs:[文件系统编号-DOSstart]
shl bx,1;×2
add bx,文件系统_2-DOSstart
cmp bx,3*2
stc;设置进位
ja 返回;大于则跳转
mov bx,cs:[bx]
jmp bx

文件系统_2:
dw 0;null，错误处理
dw iSO9660_2-DOSstart
dw FAT32_2-DOSstart
;dw -DOSstart


;输入
;EAX >LBA
;ECX >文件长度
;输出
;无
iSO9660_2:
mov cs:[当前目录簇号-DOSstart],eax
mov cs:[iSO9660目录长度-DOSstart],ecx
mov byte cs:[重置读取-DOSstart],1
jmp 返回


;输入
;EAX >簇号
;输出
;无
FAT32_2:
mov cs:[当前目录簇号-DOSstart],eax
mov byte cs:[重置读取-DOSstart],1
jmp 返回


当前目录簇号 dd 0
iSO9660目录长度 dd 0




;输入
;无
;输出
;无
重置文件读入状态:
mov byte cs:[文件读入状态-DOSstart],1
jmp 返回

;----------------------------------------------------------------------------





;输入
;EA段|AX偏 EAX >缓存区
;输出
;EAX >缓存区
读入文件扇区:
movzx bx,cs:[文件系统编号-DOSstart]
shl bx,1;×2
add bx,文件系统_3-DOSstart
cmp bx,3*2
stc;设置进位
ja 返回;大于则跳转
mov si,9000h
mov ds,si;段地址，int13ah42的DS：SI，磁盘参数块需要
mov bx,[bx]
jmp bx

文件系统_3:
dw 0;null，错误处理
dw iSO9660_3-DOSstart
;dw FAT32_3-DOSstart
;dw -DOSstart


iSO9660_3:
push eax;参数，缓存区
cmp byte[文件读入状态-DOSstart],0;标志
jz 不要重置_1
mov byte[文件读入状态-DOSstart],0;设置为0下次就不会重新读文件扇区了
mov eax,[当前目录簇号-DOSstart]
mov [LBA-DOSstart],eax

mov eax,[iSO9660目录长度-DOSstart]
mov edx,0;清空除法高位
movzx ebx,word[扇区大小-DOSstart]
div ebx;edx高：eax低÷ebx =eax……edx
cmp dx,0
jz 没有超出_3;超出一个字节都需要读完整个扇区
inc ax
没有超出_3 mov[循环次数_1-DOSstart],ax

不要重置_1:
cmp word[循环次数_1-DOSstart],0
jnz 继续读取
mov byte[文件读入状态-DOSstart],1;下次则从头开始
add sp,4
stc;设置进位
jmp 返回

继续读取:
dec word[循环次数_1-DOSstart]
mov eax,[LBA-DOSstart]
inc dword[LBA-DOSstart];推进到下一个扇区
pop ebx;参数，缓存区
mov edx,0;清空LBA高位
call 读盘
jmp 返回

文件读入状态 db 1
循环次数_1 dw 0

;----------------------------------------------------------------------------














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
;ES：SI =字符串，需带结束符
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
;DS：DI =缓存区
;输出
;DS：DI =16进制ascall码，结尾为0，注意倒序应使用std指令
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
;;，标记为只有AL
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



;AX，SI，DI寄存器将会被修改
;输入
;DS：SI =字符
;输出
;ES：DI =缓存区
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




;将会修改EAX，DX，SI寄存器
;从硬盘读取一个扇区数据
;输入
;EAX =LBA低32位
;EDX =LBA高32位
;EBX =高32位段地址+低32位偏移地址
;输出
;EBX =目标位置
读盘:;读硬盘调用+增加dpa包是加扇区
;nop;注意Bug
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



















返回:
pop ds
pop sp
mov ss,cs:[0FFFdh];还原栈
retf;iret是int指令专用返回












继续打印:;每个指令都很重要确保他们被正确执行
 xor bx,bx
 mov ah,14;BIOS中断参数
 int 10h;显示字符

 打印:
 lodsb;将DS：SI指向的内容放入al然后SI+1
 or al,al;判断al中的字符值是否 =0
jnz 继续打印
ret


int0:
push si
mov si,除法错误-DOSstart
push ax
push bx
push 9000h;数据段
pop ds
call 打印
pop si
pop bx
pop ax
call 显示寄存器
jmp $
除法错误 db 10,'Division error',13,0



int6:;遇到错误指令或使用ud2指令可手动触发
mov ebx,9000h;顺便清空高位
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
cli
hlt
jmp short 停


_cs_ip db '=PI+61*SC',10,13
错误的操作码 db 13,'Wrong opcode _',0






intD:;下次支持其他段寄存器
push eax
push bx
push esi
push ds

movzx esi,sp;不能使用ESP
mov ds,ss:[si+12+2];段，跳过压的寄存器
mov si,ss:[si+12];偏
mov al,[si];取操作码

mov si,9000h
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
mov si,显示段寄存器-DOSstart-2;-2以显示回车换行
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
mov bx,24;第3个描述符
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
no3 and al,11111110b
mov cr0,eax
jmp 9000h:RealMode-DOSstart

RealMode:
in al,92h;打开A20
or al,10b
out 92h,al

inc sp;先删ds
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

db 13,10
显示段寄存器 dw 0
db ' is set to big real mode',0

Gdtcfg:
dw GdtEnd-GdtStart-1;长度-1以忽略后一字节
dd GdtStart-DOSstart+90000h;+基地址
GdtStart:
dq 0h

dw 0FFFFh;段长度
db 0,0_,09;基地址09_0000h
db 10011010b;段属性
db 0000_1111b;段属性_段长度1111b
db 0;基地址00h

;大实模式描述符
dw 0FFFFh;段长度
db 0,0,0;基地址
db 10010010b;段属性
db 1100_1111b;段属性_段长度1111b
db 0;基地址00h
GdtEnd:






;将会修改EAX，EBX，EDX，DI寄存器
;输入
;无
;输出
显示寄存器:
push ds
push es
push edi;保
mov di,9000h
mov ds,di
mov es,di

;push edi
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

mov bp,sp;什么C语言行为
mov ebx,dword[bp+16];EDI的值
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
_EDI寄存器 db '> iDE',10,13
_ESI寄存器 db '> iSE  '
_EDX寄存器 db '> XDE  '
_ECX寄存器  db '> XCE  '
_EBX寄存器 db '> XBE  '
_EAX寄存器 db '> XAE',10,13









DOSEnd:




