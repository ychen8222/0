;----------------------------------------------------------------------------
;垃圾NASM编译器不支持双org，只能额外计算相对位置
;使用中断取命令字符，聪明的BIOS会休眠CPU，目前我发现vmbox不够聪明
;命令一般比较长所以将其放在缓存区的最后以免覆盖重要数据
;----------------------------------------------------------------------------
jmp $
返回:
pop ds
pop sp
mov ss,cs:[0FFFdh];还原栈
jnc 不设置进位
add sp,4
popf;弹标志位
stc;进位
pushf
sub sp,4
不设置进位 iret;int指令专用返回

;movhps  xmm0, qword ptr [bx+si]
;fcomp5  st, st
;out     dx, ax
;ud2

movzx ebx,dl
mov di,驱动器号的ascall-DOSstart;显示路径时会用到
call 二进制转十六进制ascall码
mov ax,es:[di-2];转换顺序
xchg ah,al
mov es:[di-2],ax

mov word[预留参数长度-DOSstart],10

mov di,DOSEnd-DOSstart
mov word es:[当前目录字符长度-DOSstart],19;别忘完了斜杠和结束符
mov ax,0;后一项的长度
stosw
mov eax,fs:[7c00h+3]
mov es:[当前目录簇号-DOSstart],eax
stosd
mov eax,fs:[7c00h+3+4]
mov es:[iSO9660目录长度-DOSstart],eax
stosd

mov si,iso9660文件系统
add si,ss:[esp];加上我们在上面保存的基地址
mov cx,7
rep movsb


jmp 进入DOS







进入DOS:
mov ax,2Fh;斜杠+结束符
stosw
mov es:[路径缓存区结束-DOSstart],di
add di,2048
mov es:[簇号临时缓存区结束-DOSstart],di












mov sp,9000h
mov ds,sp
mov es,sp
mov ss,sp
mov esp,0FFFFh

没事别乱按回车:
mov si,显示驱动器号-DOSstart
call 打印

mov si,DOSEnd-DOSstart

继续打印路径:
add si,10;跳过前面的数据
call 打印
cmp si,[路径缓存区结束-DOSstart]
jnz 继续打印路径

mov si,[簇号临时缓存区结束-DOSstart];用于取字符
mov di,si;用于存字符

等待指令:
 mov ah,0h;获取击键，如果为空则等待
 int 16h
 cmp al,8h
 jnz 不是退格

 cmp di,[簇号临时缓存区结束-DOSstart];不能覆盖到后面的簇数据
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
mov bx,0;数据表-DOSstart+10h
mov dx,1;第一次是一定要制表的
处理指令:
 mov bp,ax;保护字符
 cmp bx,dx;如果跟上次一样就不要重复制表了
 jz 不用制表
 mov dx,bx;记住这次制的表

 mov eax,0;用于清空上次写入的数据
 mov di,命令缓存区-DOSstart
 mov cx,13
 rep stosd
    继续制作命令表:
     movzx di,byte[bx+数据表-DOSstart];取即将放入的偏移
     add di,命令缓存区-DOSstart;加上基地址，即将放入的位置
     mov ax,[bx+1+数据表-DOSstart];取数据，前面是放入的位置
     stosw
     add bx,3;di会加1这不重要，但我们要BX加3以取下一个数据
     cmp byte[bx+数据表-DOSstart],0;遇到结束符
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
 mov si,不支持的命令-DOSstart
 call 打印
 jmp 没事别乱按回车;滚回去
 不支持的命令 db 10,'Unsupported command',10,0

 是字母:
 and bl,11011111b;转换为大写，原本就是则不变
 sub bl,'A';从字符转换为偏移
 cmp bl,26;小于1则会变FF
 ja 除了字母以外的都不要;大于则跳转
 shl bx,1;×2
 mov bx,[bx+命令缓存区-DOSstart];取下一个指令的位置
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
mov bx,[bx+位置表-DOSstart];取最终地址
cmp bx,0
jz _0000;还没实现
jmp bx

命令字符缓存区开始 dw 0

显示驱动器号 dw 0d0ah;回车换行
驱动器号的ascall dw 0
db '/',0;分隔符+结束符

_0000:
mov si,没有实现-DOSstart
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
Ls dw 实现_Ls-DOSstart
dir dw 实现_dir-DOSstart

drvnum dw 0
_fs dw 实现_fs-DOSstart
cd dw 实现_cd-DOSstart
shutdown dw 0
off dw 0
open dw 实现_open-DOSstart
run dw 实现_run-DOSstart
help dw 0

lg dw 实现_lg-DOSstart


实现_lg:
mov eax,1;MBR分区吗
mov edx,0;高位LBA
mov bx,0FFFFh
shl ebx,16;《段地址移到高位
mov bx,cs:[路径缓存区结束-DOSstart];偏移地址，在此处放置扇区
mov ecx,1;只读一个扇区
call 读盘

cmp dword cs:[路径缓存区结束-DOSstart+510],0AA55h
jz 分区表正常

mov si,告诉她们没有分区表
call 打印
jmp DOSstart-DOSEnd;滚回去
告诉她们没有分区表 db 'invalid partition table',13,10,'Try using the fs command directly',13,10,0

分区表正常:
mov cl,0;MBR最大支持4个分区
add bx,446;跳过前面的引导代码
下一个分区:
 inc cl
 cmp dword [bx+9],0;验证LBA号
 jz 没有个分区

 movzx eax,cl
 mov di,路径缓存区结束-DOSstart;将转换后的字符存储在这里
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

 mov si,未知文件系统-DOSstart
 cmp byte [bx+4],0h
 jz 显示文件系统类型

 mov si,FAT16-DOSstart
 cmp byte [bx+4],6h
 jz 显示文件系统类型

 mov si,FAT32-DOSstart
 cmp byte [bx+4],0bh
 jz 显示文件系统类型

 mov si,扩展-DOSstart
 cmp byte [bx+4],5h
 jz 显示文件系统类型

 mov si,NTFS-DOSstart
 cmp byte [bx+4],7h
 jz 显示文件系统类型

 mov si,扩展-DOSstart
 cmp byte [bx+4],0Fh
 jz 显示文件系统类型

 mov si,Linux-DOSstart
 cmp byte [bx+4],83h
 jz 显示文件系统类型
 mov si,未知文件系统-DOSstart
 
显示文件系统类型:
 push bx
 call 打印
 mov si,分区-DOSstart
 call 打印
 pop bx

 没有个分区:
 add bx,16;推进到下一个分区
 cmp cl,4
jnz 下一个分区;检测下一个分区

mov si,按数字选择分区-DOSstart
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
mov si,不操作-DOSstart
call 打印
jmp DOSstart
不操作 db 'Not operate',13,10,0

不小于则跳转_操作:
mov bx,0
mov ah,14;BIOS中断参数
int 10h;显示字符

mov bx,cs:[路径缓存区结束-DOSstart]
sub al,'1';从字符变为数值
mov ah,0;清空高位以便进行加法
shl ax,4;×16
add bx,ax

cmp dword cs:[bx+446+8],0;检测LBA
jz 不操作空壳
mov eax,cs:[bx+446+8]
jmp DOSstart


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
mov bx,cs:[路径缓存区结束-DOSstart];偏移地址，在此处放置扇区
mov ecx,1;只读一个扇区
call 读盘

cmp dword cs:[bx],01434430h;1_CD0
jnz 未检测到文件系统
cmp word cs:[bx+4],'01'
jnz 未检测到文件系统

push bx;int 10h会修改bx
mov si,iso9660文件系统
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
jmp DOSstart-DOSEnd;滚回去
妳按了其他键 db 'oijh',13,10,0

应用设定:
mov word cs:[扇区大小-DOSstart],2048
mov eax,cs:[bx+156+2];根目录的目录项+2双端格式的范围位置 (LBA)，2~8÷2
mov ecx,cs:[bx+156+10];根目录的目录项+10双端格式的数据长度（范围大小）
mov cs:[当前目录簇号-DOSstart],eax;save
mov cs:[iSO9660目录长度-DOSstart],ecx
jmp DOSstart-DOSEnd;滚回去

文件系统编号 db 0
iso9660文件系统 db 'iSO9660',13,10,0










未检测到文件系统:
mov si,告诉她没检测到文件系统
call 打印
jmp DOSstart-DOSEnd;滚回去

告诉她没检测到文件系统 db '123456',13,10,0
按一使用设定 db '123456',13,10,0



实现_Ls:
实现_dir:
movzx bx,byte [文件系统编号-DOSstart]
shl bx,1;×2
add bx,文件系统类型表-DOSstart;加上基地址
mov bx,[bx];取最终地址
jmp bx

文件系统类型表:
dw 不支持的文件系统-DOSstart
dw iso9660_列出-DOSstart
;dw FAT-DOSstart


不支持的文件系统:
mov si,不支持的文件系统_-DOSstart
call 打印
jmp DOSstart;滚回去
不支持的文件系统_ db 10,'Unsupported file system',10,0


iso9660_列出:
mov si,_#前面的数字是序号-DOSstart
call 打印

mov word [目录项序号-DOSstart],0;清空计数
mov bx,[路径缓存区结束-DOSstart]
add bx,2048;相当于mov [$],$
mov [bx],bx
mov eax,[iSO9660目录长度-DOSstart]
mov edx,0;清空除法高位
movzx ebx,word [扇区大小-DOSstart]
div ebx;edx高：eax低÷ebx =eax……edx
mov ecx,eax;循环次数
jz 没有超出;超出一个字节都需要读完整个扇区
inc ecx
没有超出 mov eax,[当前目录簇号-DOSstart]

iso9660_下一个扇区:
 push ecx
 mov edx,0;清空LBA高位
 mov ebx,90000000h;缓存区，段地址
 mov bx,[路径缓存区结束-DOSstart];偏移地址，在此处放置扇区
 call 读盘
 inc eax;推进到下一个扇区
 push eax;LBA号

 add bx,[bx];跳过一个.目录
 add bx,[bx];跳过一个..目录
 mov di,bx
    小于则跳转_cd1下一个项:
     cmp word [di],0;这个项的长度
     jz 触底
     push word [di];取这个项的长度

     mov eax,[di+2];2双端格式的范围位置 (LBA)，2~8÷2
     mov ecx,[di+10];双端格式的数据长度（范围大小）
     mov bx,[簇号临时缓存区结束-DOSstart]
     mov [bx],eax;LBA号
     mov [bx+4],ecx;数据长度
     add word [簇号临时缓存区结束-DOSstart],8;推进到下一个位置

     push di
     movzx eax,word [目录项序号-DOSstart]
     call 二进制转十进制ascall码
     inc word [目录项序号-DOSstart]
     mov ax,0d0ah;回车
     stosw
     mov si,di;字符的位置
     dec si;减一以免取到下一个字符
     std;倒序读取
     call 打印
     pop di
     dec sp;再次保留di
     dec sp

     add di,32;指向文件名长度，+1=实际文件名
     movzx cx,byte [di];取文件名长度
     inc cx;加一以显示我们的字符
     mov byte [di],'#';显示个符号用于分隔，会覆盖掉文件名长度，但我们已经取值了
     cld;恢复正序
        显示完文件名:
         mov al,[di];文件名的一个字符
         inc di

         mov bx,0
         mov ah,14;BIOS中断参数
         int 10h;显示字符
        loop 显示完文件名
        pop di

     没有文件名:
     pop ax;推进到下一个项
     add di,ax
     mov ax,[路径缓存区结束-DOSstart]
     add ax,[扇区大小-DOSstart]
     cmp di,ax;当前扇区处理完了吗
    jb 小于则跳转_cd1下一个项

 触底:
 pop eax;弹出LBA号
 pop ecx;循环次数
 dec ecx
jnz iso9660_下一个扇区

mov al,10;换行
mov bx,0
mov ah,14;BIOS中断参数
int 10h;显示字符
jmp DOSstart;滚回去

_#前面的数字是序号 db 10,'The number in front of the # is the serial number',10,0

簇号临时缓存区结束 dw 0
























实现_open:
实现_run:
movzx bx,byte [文件系统编号-DOSstart]
shl bx,1;×2
add bx,文件系统类型表_2-DOSstart;加上基地址
mov bx,[bx];取最终地址
jmp bx

文件系统类型表_2:
dw 不支持的文件系统-DOSstart
dw iso9660_读入-DOSstart
;dw FAT-DOSstart


iso9660_读入:
mov ax,[簇号临时缓存区结束-DOSstart]
sub ax,2048;用于缓存扇区的空间
mov bx,[路径缓存区结束-DOSstart]
cmp bx,ax
jnz 序号可用
mov si,请先使用ls或dir命令-DOSstart
call 打印
jmp DOSstart;滚回去
请先使用ls或dir命令 db 10,'Please use ls or dir command first',10,0

序号可用:
mov si,输入序列号选择打开文件-DOSstart
call 打印
mov si,[簇号临时缓存区结束-DOSstart];序号缓存区
mov di,si

等待数字:
 mov ah,0h;获取击键，如果为空则等待
 int 16h
 cmp al,8h
 jnz 不是退格_1

 cmp di,[簇号临时缓存区结束-DOSstart];不能覆盖到后面的簇数据
 jz 删到头了_1
 dec di;删个字符
 删到头了_1 mov bx,0h;先退个格
 mov ah,14;BIOS中断参数
 int 10h
 mov al,' ';补个空格
 int 10h
 mov al,8h;再次退格
 int 10h
jmp 等待数字;不要保存这个退格字符

 不是退格_1:
 cmp al,0dh
 jz 回车可过
 cmp al,'9'
 ja 等待数字;大于则跳转
 cmp al,'0'
 jb 等待数字;小于则跳转
 回车可过:

 mov bx,0h
 mov ah,14;BIOS中断参数
 int 10h

 stosb;保存输入
 cmp al,0dh;回车
jnz 等待数字;没按回车就继续处理指令

cmp byte [si],0dh;直接按回车就是取消
jnz 你输入了序号
mov si,什么也没做-DOSstart
call 打印
jmp DOSstart;滚回去
什么也没做 db 10,'Did nothing',10,0

你输入了序号:
mov byte [di-1],0;使用结束符覆盖回车符

call 十进制ascall码转二进制

movzx ebx,word [簇号临时缓存区结束-DOSstart]
sub bx,[路径缓存区结束-DOSstart]
sub bx,2048;用于缓存扇区的空间
shr bx,3;除以8
cmp eax,ebx
jbe 输入的数字正常;小于等于则跳转
mov si,没有这样的选择-DOSstart
call 打印
jmp 序号可用;重新选择
没有这样的选择 db 10,'No such option',13,10,0

输入的数字正常:
mov bx,ax
shl bx,3;×8
add bx,[路径缓存区结束-DOSstart]

mov  eax,[bx+2048+4]
mov edx,0;清空除法高位
movzx ecx,word [扇区大小-DOSstart]
div ecx
mov ecx,eax
cmp edx,0
jz 没有超出_1;超出一个字节都需要读完整个扇区
inc ecx
没有超出_1 mov eax,[bx+2048];LBA号
movzx edi,word [扇区大小-DOSstart]
shl edi,12;《
mov ebx,500000h;段地址

iso9660_继续读入:
 mov edx,0;清空LBA高位
 push eax
 call 读盘
 pop eax
 inc eax;推进到下一个扇区
 add ebx,edi
loop iso9660_继续读入

jmp 0:500h

输入序列号选择打开文件 db 10,'Enter the serial number to choose to open the file #',0





实现_cd:
movzx bx,byte [文件系统编号-DOSstart]
shl bx,1;×2
add bx,文件系统类型表_3-DOSstart;加上基地址
mov bx,[bx];取最终地址
jmp bx

文件系统类型表_3:
dw 不支持的文件系统-DOSstart
dw iso9660_实现cd-DOSstart
;dw FAT-DOSstart


iso9660_实现cd:
mov si,[簇号临时缓存区结束-DOSstart]
跳过空格_2 lodsb
cmp al,' '
jz 跳过空格_2
inc si;现在si指向d字符，我们跳过他
cmp byte[si+1],' ';你有可能遇到灵异事件，即空格文件夹
mov byte[标志],0;先清空标志，以防误判
jnz 不是空格文件夹
mov byte[标志],1
不是空格文件夹 mov cx,si;save
跳过空格_3 lodsb;开始处理cd命令后面的数据
cmp al,' '
jz 跳过空格_3

cmp al,0dh;如果你你什么路径都没输入则
jnz 不是空格
cmp byte[标志],1
jz 不是返回上一级目录;你是用安卓的MT管理器创建的空格文件夹吗
jmp DOSstart;滚回去

不是空格:
cmp al,'.'
jnz 不是返回上一级目录

lodsb
cmp al,0dh;什么也没做
jz DOSstart;滚回去

cmp al,'.';cd ..
jnz 不是返回上一级目录;不是
跳过空格_4 lodsb
cmp al,' '
jz 跳过空格_4
cmp al,0dh
jnz 不是返回上一级目录;暗藏悬只因

mov bx,[路径缓存区结束-DOSstart]
sub bx,[当前目录字符长度-DOSstart]
cmp word[bx],0;没有字符了所以no行
jnz 后退可行
mov si,无路可退-DOSstart
call 打印
jmp DOSstart;滚回去
无路可退 db 10,'No retreat',13,10,0

后退可行:
mov ax,[bx];这里保存了后面的字符长度，你修改为0即可锁定后退
mov [当前目录字符长度-DOSstart],ax
sub bx,ax;跳过字符
mov eax,[bx-8]
mov es:[当前目录簇号-DOSstart],eax
mov eax,[bx-4]
mov es:[iSO9660目录长度-DOSstart],eax


jmp DOSstart;滚回去


不是返回上一级目录:
mov si,cx;恢复
inc si;跳过cd命令前的一个空格
cmp byte[标志],1
jz 是空格文件夹
跳过空格_5 lodsb
cmp al,' '
jz 跳过空格_5
mov di,[路径缓存区结束-DOSstart]
mov bx,di
add di,[预留参数长度-DOSstart];预留参数位置
mov ax,0
继续复制:
inc ax;记录字符数
movsb
cmp byte[si],0dh;直到遇到回车符，否则还没结束
jnz 继续复制
mov cx,ax;字符长度
add ax,[预留参数长度-DOSstart];加上参数位置
inc ax;加上斜杠和结束符
inc ax
mov [bx],ax
mov ax,2Fh;斜杠和结束符
stosw
mov [路径缓存区结束-DOSstart],di;更新

mov si,bx;路径字符
push si;原路径
;cx字符长度
mov bx,4;功能号，搜索
int 21h




是空格文件夹:
jmp 显示寄存器

当前目录字符长度 dw 0
路径缓存区结束 dw 0;在此之后是路径
标志 db 0;该死，我们不能用stc指令进行标记，因为会被cmp指令破坏
预留参数长度 dw 0












