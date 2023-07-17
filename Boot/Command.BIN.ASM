;----------------------------------------------------------------------------
;命令处理，难度★★★★☆
;使用中断取字符，大部分BIOS会休眠CPU，但vmbox是个例外
;命令一般比较长所以将其放在缓存区的最后以免覆盖重要数据
;2023：6:19：8:1
;@cya
;----------------------------------------------------------------------------
;内存布局
;80000～8FFFF_Command.BIN
push 8000h
pop ds
dec sp;复
dec sp
pop es

push bx
push eax
movzx ebx,di;驱动器号
mov di,驱动器号的ascall;显示路径时会用到
call 二进制转十六进制ascall码
mov ax,es:[di-2];转换顺序
xchg ah,al
mov es:[di-2],ax
pop eax

pop bx;文件系统序号
mov [文件系统编号],bl
shl bx,1;×2
;cmp bx,4*2
add bx,文件系统类型表;+基地址
mov bx,[bx]
jmp bx;CS段，BX偏移

文件系统类型表:
dw 0;无法确定文件系统类型
dw iSO9660



iSO9660:
mov di,缓存区
mov word[预留参数长度],8
stosd;LBA号
mov eax,ecx;长度
stosd

mov si,iSO9660文件系统
;mov di,缓存区
push cx
mov cx,7
rep movsb
mov ax,2Fh;斜杠+结束符
stosw
mov [路径显示结束],di

mov ax,di
inc ax;用两个字节word来存储当前路径项的长度
inc ax
sub ax,缓存区;取偏移，别忘了减去基地址
stosw
mov es:[路径缓存区结束],di
mov es:[簇号缓存区结束],di;注意，会覆盖掉第一次的命令


滚回去:
mov sp,8000h
mov ds,sp
mov es,sp
mov ss,sp
mov esp,0FFFFh;顺便清空高位

没事别乱按回车:
mov si,显示驱动器号
call 打印

mov si,缓存区;用于显示路径

继续打印路径:
add si,[预留参数长度];跳过前面的数据
call 打印
cmp si,[路径显示结束]
jnz 继续打印路径

mov si,[簇号缓存区结束];用于取字符
mov di,si;用于存字符

等待指令:
 mov ah,0h;获取击键，如果为空则等待
 int 16h
 cmp al,8h
 jnz 不是退格

 cmp di,[簇号缓存区结束];不能覆盖到后面的簇数据
 jz 删到头了
 dec di;删个字符
 删到头了 mov bx,0h;先退个格
 mov ah,14;BIOS中断参数
 int 10h
 mov al,' ';补个空格
 int 10h
 mov al,8h;再次退格
 int 10h
jmp 等待指令;不要保存这个退格字符

 不是退格:
 mov bx,0h
 mov ah,14;BIOS中断参数
 int 10h

 stosb;保存输入
 cmp al,0dh;回车
jnz 等待指令;没按回车就继续处理指令

跳过空格 lodsb
 cmp al,' '
jz 跳过空格
cmp al,0dh
jz 没事别乱按回车


;----------------------------------------------------------------------------
;把所有前字母面相同的放入同一张表内，你需要先构建表，第一个byte是写入的位置，第二个word是数据，直到遇到0结束符
;将命令转换为命令缓存区内偏移，并取只为数据表内偏移，用于制表，然后循环直到命令完毕
;----------------------------------------------------------------------------
;mov bp,含run_2-数据表，用于调试
mov ah,0;可用于清空BX高位
mov bx,0;数据表+10h
mov dx,1;第一次是一定要制表的
处理指令:
 mov bp,ax;保护字符
 cmp bx,dx;如果跟上次一样就不要重复制表了
 jz 不用制表
 mov dx,bx;记住这次制的表

 mov eax,0;用于清空上次写入的数据
 mov di,命令缓存区
 mov cx,13
 rep stosd
    继续制作命令表:
     movzx di,byte[bx+数据表];取即将放入的偏移
     add di,命令缓存区;加上基地址，即将放入的位置
     mov ax,[bx+1+数据表];取数据，前面是放入的位置
     stosw
     add bx,3;di会加1这不重要，但我们要BX加3以取下一个数据
     cmp byte[bx+数据表],0;遇到结束符
    jnz 继续制作命令表


 不用制表:;在此处拦截不支持的字符
 mov bx,bp
 cmp bl,'A'
 jb 除了字母以外的都不要;小于则跳转
 cmp bl,'z'
 ja 除了字母以外的都不要;大于则跳转

 cmp bl,'[';在大写和小写之间隔了几个字符，我们需要额外处理
 jb 是字母;小于则跳转
 cmp bl,'`'
 ja 是字母;大于则跳转

 除了字母以外的都不要:
 mov si,不支持的命令
 call 打印
 jmp 没事别乱按回车;滚回去
 不支持的命令 db 10,'Unsupported command',10,0

 是字母:
 and bl,11011111b;转换为大写，原本就是则不变
 sub bl,'A';从字符转换为偏移
 cmp bl,26;小于1则会变FF
 ja 除了字母以外的都不要;大于则跳转
 shl bx,1;×2
 mov bx,[bx+命令缓存区];取下一个指令的位置
 cmp bx,0
 jz 除了字母以外的都不要

 lodsb
 cmp al,0dh;这个就是你按的回车，遇到了就意味着结束，不过也是新的开始
 jz 下下下
 cmp al,' ';是空格，接下来就应该是参数了吧，但需要交给相应的程序进行处理
jnz 处理指令;也不是空格就继续取命令

下下下:
test bx,8000h;我们给最终结果设置一个标记，如果没有这个标志将不采用
jz 除了字母以外的都不要
sub bx,8000h;减去我们设置的标记
mov bx,[bx+位置表];取最终地址
cmp bx,0
jz _0000;还没实现
jmp bx

命令字符缓存区开始 dw 0
路径显示结束 dw 0


_0000:
mov si,没有实现
call 打印
jmp 没事别乱按回车
没有实现 db 10,'Not achieved',10,0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

命令缓存区:;如果命令过多还是单独弄个表为妙，用TXT格式保存怎么样
A_1 dw 0
B_2 dw 0
C_3 dw 0;cd
D_4 dw 0;drvnum，dir，cd
E_5 dw 0
F_6 dw 0
G_7 dw 0
H_8 dw 0
i_9 dw 0
J_10 dw 0
K_11 dw 0
L_12 dw 0;Ls
M_13 dw 0
N_14 dw 0
O_15 dw 0;open，off
P_16 dw 0
Q_17 dw 0
R_18 dw 0;run
S_19 dw 0;Ls，shutdown
T_20 dw 0
U_21 dw 0
V_22 dw 0
W_23 dw 0
X_24 dw 0
Y_25 dw 0
Z_26 dw 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
数据表:;最好还是按顺序排序，当然也可以不用
db C_3-命令缓存区;放入缓存区的位置
dw 含cd-数据表;表内偏移

db D_4-命令缓存区;全部同上所诉
dw 含dirDrvnum_2-数据表

db F_6-命令缓存区
dw 含fs_2-数据表

db L_12-命令缓存区
dw 含LsLg-数据表

db O_15-命令缓存区
dw 含openOff_2-数据表

db R_18-命令缓存区
dw 含run_2-数据表

db S_19-命令缓存区
dw 含shutdown_2-数据表

db H_8-命令缓存区
dw 含help_2-数据表
db 0;结束符，可用
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
含cd:
db D_4-命令缓存区
dw cd-位置表+8000h;表内偏移，在最高位加个标记，用来表示这是最终值可以使用了
db 0;结束符
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
含dirDrvnum_2:
db i_9-命令缓存区
dw 含dir_3-数据表
db R_18-命令缓存区
dw 含Drvnum_3-数据表
db 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
含dir_3:
db R_18-命令缓存区
dw dir-位置表+8000h;全部同上所诉
db 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
含Drvnum_3:
db V_22-命令缓存区
dw 含Drvnum_3-数据表
db N_14-命令缓存区
dw 含Drvnum_3-数据表
db U_21-命令缓存区
dw 含Drvnum_3-数据表
db M_13-命令缓存区
dw drvnum-位置表+8000h
db 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
含LsLg:
db S_19-命令缓存区
dw Ls-位置表+8000h
db G_7-命令缓存区
dw lg-位置表+8000h
db 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
含openOff_2:
db F_6-命令缓存区
dw off_3-数据表;叠词词，恶心心
db P_16-命令缓存区
dw 含open_3-数据表
db 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
off_3:;只能新建一个表来处理叠词，有点浪费不过也只能这样了
db F_6-命令缓存区
dw off-位置表+8000h
db 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
含open_3:
db E_5-命令缓存区
dw 含open_3-数据表
db N_14-命令缓存区
dw open-位置表+8000h
db 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
含run_2:
db U_21-命令缓存区
dw 含run_2-数据表;0FFFFh，用于调试
db N_14-命令缓存区
dw run-位置表+8000h
db 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
含help_2:
db E_5-命令缓存区
dw 含help_2-数据表
db L_12-命令缓存区
dw 含help_2-数据表
db P_16-命令缓存区
dw help-位置表+8000h
db 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
含shutdown_2:
db H_8-命令缓存区
dw 含shutdown_2-数据表
db U_21-命令缓存区
dw 含shutdown_2-数据表
db T_20-命令缓存区
dw 含shutdown_2-数据表
db D_4-命令缓存区
dw 含shutdown_2-数据表
db O_15-命令缓存区
dw 含shutdown_2-数据表
db W_23-命令缓存区
dw 含shutdown_2-数据表
db N_14-命令缓存区
dw shutdown-位置表+8000h
db 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
含fs_2:
db S_19-命令缓存区
dw _fs-位置表+8000h
db 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


位置表:
Ls dw 实现_Ls
dir dw 实现_dir

drvnum dw 0
_fs dw 实现_fs
cd dw 实现_cd
shutdown dw 0
off dw 0
open dw 实现_open
run dw 实现_run
help dw 0

lg dw 实现_lg


实现_lg:
mov eax,1;MBR分区吗
mov edx,0;高位LBA
mov bx,0FFFFh
shl ebx,16;《段地址移到高位
mov bx,cs:[路径缓存区结束];偏移地址，在此处放置扇区
mov ecx,1;只读一个扇区
call 读盘

cmp dword cs:[路径缓存区结束+510],0AA55h
jz 分区表正常

mov si,告诉她们没有分区表
call 打印
jmp 滚回去
告诉她们没有分区表 db 'invalid partition table',13,10,'Try using the fs command directly',13,10,0

分区表正常:
mov cl,0;MBR最大支持4个分区
add bx,446;跳过前面的引导代码
下一个分区:
 inc cl
 cmp dword [bx+9],0;验证LBA号
 jz 没有个分区

 movzx eax,cl
 mov di,路径缓存区结束;将转换后的字符存储在这里
 call 二进制转十进制ascall码
 push bx;save
 call 打印

 mov si,活动
 cmp byte [bx],80h
 jz 是活动分区
 mov si,不活动

 是活动分区:
 call 打印
 pop bx

 mov si,未知文件系统
 cmp byte [bx+4],0h
 jz 显示文件系统类型

 mov si,FAT16
 cmp byte [bx+4],6h
 jz 显示文件系统类型

 mov si,FAT32
 cmp byte [bx+4],0bh
 jz 显示文件系统类型

 mov si,扩展
 cmp byte [bx+4],5h
 jz 显示文件系统类型

 mov si,NTFS
 cmp byte [bx+4],7h
 jz 显示文件系统类型

 mov si,扩展
 cmp byte [bx+4],0Fh
 jz 显示文件系统类型

 mov si,Linux
 cmp byte [bx+4],83h
 jz 显示文件系统类型
 mov si,未知文件系统
 
显示文件系统类型:
 push bx
 call 打印
 mov si,分区
 call 打印
 pop bx

 没有个分区:
 add bx,16;推进到下一个分区
 cmp cl,4
jnz 下一个分区;检测下一个分区

mov si,按数字选择分区
call 打印

mov ah,0h;获取击键
int 16h
cmp al,'4'
ja 大于则跳转_不操作
cmp al,'1'
jnb 不小于则跳转_操作

大于则跳转_不操作:
mov bx,0
mov ah,14;BIOS中断参数
int 10h;显示字符
不操作空壳:
mov si,不操作
call 打印
jmp 滚回去
不操作 db 'Not operate',13,10,0

不小于则跳转_操作:
mov bx,0
mov ah,14;BIOS中断参数
int 10h;显示字符

mov bx,cs:[路径缓存区结束]
sub al,'1';从字符变为数值
mov ah,0;清空高位以便进行加法
shl ax,4;×16
add bx,ax

cmp dword cs:[bx+446+8],0;检测LBA
jz 不操作空壳
mov eax,cs:[bx+446+8]
jmp 滚回去


活动 db '#Active ',0
不活动 db '#inactive ',0
未知文件系统 db 'Unknown file system',0
FAT16 db 'FAT16',0
FAT32 db 'FAT32',0
扩展 db 'Extend',0
NTFS db 'NTFS',0
Linux db 'Linux',0
分区 db ' Partition',13,10,0
按数字选择分区 db 'Select partitions numerically',13,10,0



实现_fs:
mov eax,16;iso9660主卷描述符
mov edx,0;高位LBA
mov bx,0FFFFh
shl ebx,16;《段地址移到高位
mov bx,cs:[路径缓存区结束];偏移地址，在此处放置扇区
mov ecx,1;只读一个扇区
call 读盘

cmp dword cs:[bx],01434430h;1_CD0
jnz 未检测到文件系统
cmp word cs:[bx+4],'01'
jnz 未检测到文件系统

push bx;int 10h会修改bx
mov si,iSO9660文件系统
call 打印
mov  si,按一使用设定
call 打印
pop bx

mov ah,0h;获取击键
int 16h
cmp al,'1'
jz 应用设定

mov si,妳按了其他键
call 打印
jmp 滚回去
妳按了其他键 db 'oijh',13,10,0

应用设定:
mov word cs:[扇区大小],2048
mov eax,cs:[bx+156+2];根目录的目录项+2双端格式的范围位置 (LBA)，2~8÷2
mov ecx,cs:[bx+156+10];根目录的目录项+10双端格式的数据长度（范围大小）
mov cs:[当前目录簇号],eax;save
mov cs:[iSO9660目录长度],ecx
jmp 滚回去

文件系统编号 db 0
iSO9660文件系统 db 'iSO9660',13,10,0
扇区大小 dw 0


iSO9660目录长度 dw 0


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




未检测到文件系统:
mov si,告诉她没检测到文件系统
call 打印
jmp 滚回去

告诉她没检测到文件系统 db '123456',13,10,0
按一使用设定 db '123456',13,10,0



实现_Ls:
实现_dir:
mov si,回车换行
call 打印
mov si,回车换行
call 打印
movzx bx,byte[文件系统编号]
shl bx,1;×2
add bx,文件系统类型表_1;加上基地址
mov bx,[bx];取最终地址
mov ax,9000h;文件名在DOS段内
mov fs,ax
mov ax,[路径缓存区结束];重置缓存区
mov [簇号缓存区结束],ax
jmp bx

文件系统类型表_1:
dw 不支持的文件系统
dw iso9660_列出
;dw FAT


不支持的文件系统:
mov si,不支持的文件系统_
call 打印
jmp 滚回去
不支持的文件系统_ db 10,'Unsupported file system',10,0


iso9660_列出:
mov al,0FFh;获取所有类型的文件

iso9660_显示文件名:
mov bx,4;获取一个文件项
int 21h
jc 项取完了
mov cx,dx;int21输出，文件名长度

显示完文件名:
 mov al,fs:[di]
 inc di;推
 mov bh,0;页码
 mov ah,14;BIOS中断参数
 int 10h;显示字符
loop 显示完文件名
mov si,回车换行
call 打印
jmp iso9660_显示文件名

项取完了 jmp 滚回去




实现_open:
实现_run:
mov si,换行
call 打印
movzx bx,byte [文件系统编号]
shl bx,1;×2
add bx,文件系统类型表_2;加上基地址
mov bx,[bx];取最终地址
mov word[目录项序号],0;清空计数
mov ax,9000h;文件名在DOS段内
mov fs,ax
mov ax,[路径缓存区结束];重置缓存区
mov [簇号缓存区结束],ax
jmp bx

文件系统类型表_2:
dw 不支持的文件系统
dw iso9660_读入
;dw FAT


iso9660_读入:
mov al,0;获取一个文件项
mov bx,4
int 21h
jc 滚回去
push dx;int21输出的文件名长度
jmp 第一次则插入

继续获取项:
mov bx,4;获取一个文件项
int 21h
jc 没了
push dx;int21输出的文件名长度

第一次则插入:
mov bx,[簇号缓存区结束]
cmp bx,0FFF0h
ja 没了_1;大于则跳转，簇号存不下了，注意栈平衡
mov [bx],eax;LBA号
mov [bx+4],ecx;数据长度
add word [簇号缓存区结束],8;推进到下一个位置

movzx eax,word[目录项序号]
inc word[目录项序号];推
push di;int21输出的字符位置
mov di,[簇号缓存区结束]
call 打印序号
pop di;文件名的位置，用于显示
pop dx;int21输出的文件名长度
call 打印文件文件或文件夹名
jmp 继续获取项


没了_1:
inc sp;平
inc sp
没了:
mov si,回车换行
call 打印
重新选择:
mov si,输入序列号选择打开文件
call 打印
mov di,[簇号缓存区结束];序号缓存区
mov si,di;续
call 取数字
jnz 你输入了序号

显示什么也没做:
mov si,什么也没做
call 打印
jmp 滚回去
什么也没做 db 10,'Did nothing',10,0

你输入了序号:
mov byte[di],0;结束符
call 十进制ascall码转二进制;EAX =数值

movzx ebx,word[簇号缓存区结束];使用movzx指令以便下面对比
sub bx,[路径缓存区结束]
shr bx,3;除以8
dec bx;减预推进
cmp eax,ebx;你输入的数字过大，甚至超过AX
jbe 输入的数字正常;小于等于则跳转
mov si,没有这样的选择
call 打印
jmp 重新选择
没有这样的选择 db 10,'No such option',13,10,0

输入的数字正常:
push ax;输入的序号
mov bx,1;存原参数
int 21h
push eax
push ecx

add sp,8;取栈更上面的数据
pop bx;输入的序号
sub sp,10;原
shl bx,3;×8
add bx,[路径缓存区结束]
mov eax,[bx];根目录的目录项+2双端格式的范围位置 (LBA)，2~8÷2
mov ecx,[bx+4];根目录的目录项+10双端格式的数据长度（范围大小）
mov bx,5;设置参数
int 21h

mov eax,50_0000h;读入的位置

iso9660_继续读入:
push dx
push eax
mov bx,7
int 21h
pop eax
pop dx;扇区大小
pushf;压标志位
add ax,dx;推
popf
jnc iso9660_继续读入

pop ecx
pop eax
mov bx,5;设置参数
int 21h

jmp 0:500h

输入序列号选择打开文件 db 10,'Enter the serial number to choose to open the file #',0





实现_cd:
mov si,换行
call 打印
movzx bx,byte[文件系统编号]
shl bx,1;×2
add bx,文件系统类型表_3;加上基地址
mov bx,[bx];取最终地址
mov ax,9000h;文件名在DOS段内
mov fs,ax
mov ax,[路径缓存区结束];重置缓存区
mov [簇号缓存区结束],ax
jmp bx

文件系统类型表_3:
dw 不支持的文件系统
dw iso9660_实现cd
;dw FAT



iso9660_实现cd:
mov si,[路径缓存区结束]
跳过空格_2 lodsb
cmp al,' '
jz 跳过空格_2
inc si;现在si指向d字符，我们跳过他
mov cx,si;save
跳过空格_3 lodsb;开始处理cd命令后面的数据
cmp al,' '
jz 跳过空格_3
cmp al,0dh
jz 不是返回上一级目录
cmp al,'.'
jnz 不是返回上一级目录
lodsb
cmp al,0dh
jz 刷新当前目录

cmp al,'.';cd ..
jnz 不是返回上一级目录;不是
跳过空格_4 lodsb
cmp al,' '
jz 跳过空格_4
cmp al,0dh
jnz 不是返回上一级目录;暗藏悬只因

mov bx,[路径缓存区结束]
sub bx,[bx-2];在项的尾部存储着本项长度
cmp bx,缓存区;到头了
jnz 后退可行
mov si,无路可退
call 打印
jmp 滚回去
无路可退 db 10,'No retreat',13,10,0


刷新当前目录 mov bx,[路径缓存区结束];取本项来刷新
后退可行:
mov [路径缓存区结束],bx;新的位置，忽略前面
sub bx,[bx-2];取本项参数，在上面已经退了一个项
mov eax,[bx];LBA
mov ecx,[bx+4];长度
mov bx,5;设置文件系统参数
int 21h
jmp 滚回去

不是返回上一级目录:;;;;;;;;;;
mov ax,[路径缓存区结束]
push ax;-2，项缓存区结束
push 0;-0，项计数
mov al,1;文件夹项
mov bx,4
int 21h
jnc 第一次则插入_1
add sp,4;删
jmp 滚回去

获取文件夹项:
mov bx,4
int 21h
jc 没了_2

第一次则插入_1:
mov bx,ss:[esp+2];项缓存区结束
mov [bx],eax;簇号
mov [bx+4],ecx;长度
mov [bx+8],dx;文件夹名长度
add bx,10;推
push di;-2，续
push  dx;-0

继续复制字符:
dec dx
js 字符复制结束;最高位为1，负数则跳转
mov al,fs:[di]
inc di;推
mov [bx],al
inc bx;推
jmp 继续复制字符

字符复制结束:
mov ss:[esp+2+2+2],bx;刷
movzx eax,word ss:[esp+2+2];项计数
inc word ss:[esp+2+2];推
mov di,bx;项缓存区结束后用于序号字符缓存区
call 打印序号
pop dx;长
pop di;字
call 打印文件文件或文件夹名
jmp 获取文件夹项

没了_2:
mov bx,[路径缓存区结束]
cmp bx,ss:[esp+2];项缓存区结束
jz $;缓存区是空的，没有文件夹项


重新选择_1:
mov si,输入序列号选择打开文件
call 打印
mov di,ss:[esp+2];项缓存区结束后用于数字字符缓存区
mov si,di;续
call 取数字
jz 显示什么也没做
mov byte[di],0;结束符，并覆盖回车13
call 十进制ascall码转二进制;EAX =数值
movzx ebx,word ss:[esp];项计数，使用movzx指令以便下面对比
cmp eax,ebx
jbe 输入的数字正常_1;小于等于则跳转
mov si,没有这样的选择
call 打印
jmp 重新选择_1

输入的数字正常_1:
mov bx,[路径缓存区结束]

推进项:;注意，以后需要建立快速索引表
dec ax;项计数
js 推进结束;最高位为1，负数则跳转
add bx,10;推，跳过3个参数
add bx,[bx-2];跳过文件名
jmp 推进项

推进结束:
mov eax,[bx];簇号
mov ecx,[bx+4];长度
mov bx,5;设置文件系统参数
int 21h
mov cx,[bx+8];文件夹名长度
mov si,bx
add si,10;推，跳过3个参数












jmp $



call 显示寄存器




mov si,cx;恢复
inc si;跳过cd命令前的一个空格
跳过空格_5 lodsb
cmp al,' '
jz 跳过空格_5
mov di,[路径缓存区结束]
mov bx,di
add di,[预留参数长度];预留参数位置
mov ax,0
继续复制:
inc ax;记录字符数
movsb
cmp byte[si],0dh;直到遇到回车符，否则还没结束
jnz 继续复制
mov cx,ax;字符长度
add ax,[预留参数长度];加上参数位置
inc ax;加上斜杠和结束符
inc ax
mov [bx],ax
mov ax,2Fh;斜杠和结束符
stosw
mov [路径缓存区结束],di;更新

mov si,bx;路径字符
push si;原路径
;cx字符长度















当前目录字符长度 dw 0
路径缓存区结束 dw 0;在此之后是路径
预留参数长度 dw 0
簇号缓存区结束 dw 0

读盘:


;EAX，EBX，EDX，Si，Di寄存器将会被修改
;输入
;EAX =序号
;Di =字符缓存区
;输出
;显示序号#
打印序号:
call 二进制转十进制ascall码
mov word es:[di],0d0ah;回车
mov si,di
inc si;推进到0a字符
std;倒
call 打印
cld;正
mov al,'#'
mov bh,0;页码
mov ah,14;BIOS中断参数
int 10h;显示字符
ret



;AX，BH，Di寄存器将会被修改
;输入
;FS：Di =字符串
;DX =字符长度
;输出
;显示字符串
打印文件文件或文件夹名:
 dec dx
 jns 继续打印_1
 ret
 继续打印_1 mov al,fs:[di]
 inc di;推
 mov bh,0;页码
 mov ah,14;BIOS中断参数
 int 10h;显示字符
jmp 打印文件文件或文件夹名



;AX，BH，Di寄存器将会被修改
;输入
;ES：Di =缓存区
;输出
;ES：Di =数字ascall
;ZF =1，没有输入数字
取数字:
push di;缓存区起始，禁止越界

取数字_1:
 mov ah,0h;获取击键，如果为空则等待
 int 16h
 cmp al,8h
 jnz 不是退格_1

 cmp di,ss:[esp];不能覆盖到后面的簇数据
 jz 删到头了_1
 dec di;删个字符
 删到头了_1 mov bh,0h;先退个格
 mov ah,14;BIOS中断参数
 int 10h
 mov al,' ';补个空格
 int 10h
 mov al,8h;再次退格
 int 10h
jmp 取数字_1;不要保存这个退格字符

 不是退格_1:
 cmp al,0dh
 jz 是回车
 cmp al,'9'
 ja 取数字_1;大于则跳转
 cmp al,'0'
 jb 取数字_1;小于则跳转
 是回车:

 mov bh,0h;页码
 mov ah,14;BIOS中断参数
 int 10h

 stosb;保存输入
 cmp al,0dh;回车
jnz 取数字_1;没按回车就继续处理指令
dec di;删写入的回车
inc sp;删
inc sp
cmp di,ss:[esp-2];删了个回车，缓存区是空的，直接按回车就是取消
ret



;AX，BX，Si寄存器将会被修改
;输入
;Si =字符串，需带结束符
;输出
;显示字符串
继续打印:;每个指令都很重要确保他们被正确执行
 xor bx,bx
 mov ah,14;BIOS中断参数
 int 10h;显示字符

 打印:
 lodsb;将DS：SI指向的内容放入al然后SI+1
 or al,al;判断al中的字符值是否 =0
jnz 继续打印
ret

回车换行 db 13
换行 db 10,0



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



;将会修改EAX，EBX，EDX，DI寄存器
;输入
;无
;输出
显示寄存器:
push edi
mov di,[簇号缓存区结束];在此处放置转换的ascall码
push eax
push ebx
push ecx
push esi
mov ax,0a00h;结束符
stosw

mov ebx,ebp
call 二进制转十六进制ascall码
mov si,_EBP寄存器
mov cx,7
rep movsb

mov ebx,esp
add ebx,20;减去我们在栈里压的一些东西
call 二进制转十六进制ascall码
mov si,_ESP寄存器
mov cx,7
rep movsb

mov bp,sp;什么C语言行为
mov ebx,dword[bp+16];EDI的值
call 二进制转十六进制ascall码
mov si,_EDI寄存器
mov cx,7
rep movsb

pop ebx;ESI的值
call 二进制转十六进制ascall码
mov si,_ESI寄存器
mov cx,7
rep movsb

mov ebx,edx
call 二进制转十六进制ascall码
mov si,_EDX寄存器
mov cx,7
rep movsb

pop ebx;ECX的值
call 二进制转十六进制ascall码
mov si,_ECX寄存器
mov cx,7
rep movsb

pop ebx;原EBX的值
call 二进制转十六进制ascall码
mov si,_EBX寄存器
mov cx,7
rep movsb

pop ebx;EAX的值
call 二进制转十六进制ascall码
mov si,_EAX寄存器
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












目录项序号 dw 0
当前目录簇号 dw 0




显示驱动器号 dw 0d0ah;回车换行
驱动器号的ascall dw 0
db '/',0;分隔符+结束符
缓存区: