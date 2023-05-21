;======================================================================
;这是个加载程序，也就是引导的第二阶段
;我不会使用一些不直观的指令比如，xor ax,ax
;2023年
;该死的win系统损坏，害得我丢失亿些东西，只能重新写了
;----------------------------------------------------------------------
call 自定位
自定位 pop si
sub si,自定位
push si
add si,DOSstart
mov ax,cs
shl ax,4;段转偏移
add si,ax
add ss:[esp],ax;为什么必须要ESP
mov ax,0
mov ds,ax
dec ax;AX变FFFFh
mov es,ax
mov di,10h

in al,92h;别忘了打开A20
or al,10b
out 92h,al

mov cx,DOSEnd-DOSstart
test cx,11b
jz 刚好复制完
mov ax,cx
and cx,11b;只保留低二位
rep movsb
mov cx,ax;恢复

刚好复制完:
shr cx,2;除以4，以便最高效复制
rep movsd

mov ax,0FFFFh
mov [36h],ax;现在写入我们的中断程序
mov bx,int8-DOSstart+10h;加上我们的基地址10h
mov [34h],bx

mov [86h],ax
mov bx,int21-DOSstart+10h
mov [84h],bx

mov ax,0d0ah;写入回车换行
stosw
mov es:[驱动器号-DOSstart+10h],dl;保存驱动器号
movzx ebx,dl
call 二进制转十六进制ascall码
mov ax,es:[di-2]
xchg ah,al
mov es:[di-3],ax;驱动器号的的字符，覆盖掉转换为字符时前面放置的0结束符
dec di;覆盖掉前面的字符

cmp bp,0aa55h;由我们的引导扇区过传来的判断数
jnz 无法确定文件系统类型
cmp dh,2
ja 无法确定文件系统类型;大于则跳转

mov al,'\'
stosb
movzx bx,dh;由我们的引导扇区过传来的文件系统代号
shl bx,1;乘以2
add bx,文件系统类型表_1
add bx,ss:[esp];加上我们在上面保存的基地址
mov bx,[bx]
add bx,ss:[esp];加上我们在上面保存的基地址
push 0;默认压word
push bx
retf

文件系统类型表_1:
dw 无法确定文件系统类型
dw iso9660_1


iso9660_1:
mov si,iso9660文件系统
add si,ss:[esp];加上我们在上面保存的基地址
写入文件系统的字符 movsb
cmp byte [si],13
jnz 写入文件系统的字符
mov byte es:[文件系统代号-DOSstart+10h],1
mov word [扇区大小-DOSstart+10h],2048
jmp 进入DOS












进入DOS:
mov ah,0
mov al,'\'
stosw
add es:[路径缓存区结束-DOSstart+10h],di
无法确定文件系统类型:
jmp 0FFFFh:10h;进入命令处理程序


;------------------------------------------------------------
;垃圾NASM编译器不支持双org，只能额外计算相对位置
;使用中断取命令字符，聪明的BIOS会休眠CPU，目前我发现vmbox不够聪明
;命令一般比较长所以将其放在缓存区的最后以免覆盖重要数据
;------------------------------------------------------------
DOSstart:
mov sp,0FFFFh
mov ds,sp
mov es,sp
mov ss,sp

没事别乱按回车:
mov si,DOSEnd-DOSstart+10h
call 打印

mov si,[扇区大小-DOSstart+10];用于取字符
shl si,1;乘以2
add si,word [路径缓存区结束-DOSstart+10h]
mov di,si;用于存字符

等待指令:
 mov ah,0h;获取击键，如果为空则等待
 int 16h
 cmp al,8h
 jnz 不是退格

 cmp di,[路径缓存区结束-DOSstart+10h];不能影响到后面的路径
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


;------------------------------------------------------------
;把所有前字母面相同的放入同一张表内，你需要先构建表，第一个byte是写入的位置，第二个word是数据，直到遇到0结束符
;将命令转换为命令缓存区内偏移，并取只为数据表内偏移，用于制表，然后循环直到命令完毕
;------------------------------------------------------------
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
 mov di,命令缓存区-DOSstart+10h
 mov cx,13
 rep stosd
    继续制作命令表:
     movzx di,byte [bx+数据表-DOSstart+10h];取即将放入的偏移
     add di,命令缓存区-DOSstart+10h;加上基地址，即将放入的位置
     mov ax,[bx+1+数据表-DOSstart+10h];取数据，前面是放入的位置
     stosw
     add bx,3;di会加1这不重要，但我们要BX加3以取下一个数据
     cmp byte [bx+数据表-DOSstart+10h],0;遇到结束符
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
 mov si,不支持的命令-DOSstart+10h
 call 打印
 jmp 没事别乱按回车;滚回去
 不支持的命令 db 10,'Unsupported command',10,0

 是字母:
 and bl,11011111b;转换为大写，原本就是则不变
 sub bl,'A';从字符转换为偏移
 cmp bl,26;小于1则会变FF
 ja 除了字母以外的都不要;大于则跳转
 shl bx,1;乘以2
 mov bx,[bx+命令缓存区-DOSstart+10h];取下一个指令的位置
 cmp bx,0
 jz 除了字母以外的都不要

 lodsb
 cmp al,0dh;这个就是你按的回车，遇到了就意味着结束，不过也是新的开始
 jz 下下下
 cmp al,' ';是空格，接下来就应该是参数了吧，但需要交给相应的程序进行处理
jnz 处理指令

下下下:
test bx,8000h;我们给最终结果设置一个标记，如果没有这个标志将不采用
jz 除了字母以外的都不要
sub bx,8000h;减去我们设置的标记
mov bx,[bx+位置表-DOSstart+10h];取最终地址
cmp bx,0
jz _0000;还没实现
jmp bx


_0000:
mov si,没有实现-DOSstart+10h
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
Ls dw 实现_Ls-DOSstart+10h
dir dw 实现_dir-DOSstart+10h

drvnum dw 0
_fs dw 实现_fs-DOSstart+10h
cd dw 0
shutdown dw 0
off dw 0
open dw ABCD-DOSstart+10h
run dw ABCD-DOSstart+10h
help dw 0

lg dw 实现_lg-DOSstart+10h


实现_lg:
mov eax,1;MBR分区吗
mov edx,0;高位LBA
mov bx,0FFFFh
shl ebx,16;段地址移到高位
mov bx,cs:[路径缓存区结束-DOSstart+10h];偏移地址，在此处放置扇区
mov ecx,1;只读一个扇区
call 读盘

cmp dword cs:[路径缓存区结束-DOSstart+10h+510],0AA55h
jz 分区表正常

mov si,告诉她们没有分区表
call 打印
jmp DOSstart-DOSEnd+10h;滚回去
告诉她们没有分区表 db 'invalid partition table',13,10,'Try using the fs command directly',13,10,0

分区表正常:
mov cl,0;MBR最大支持4个分区
add bx,446;跳过前面的引导代码
下一个分区:
 inc cl
 cmp dword [bx+9],0;验证LBA号
 jz 没有个分区

 movzx eax,cl
 mov di,路径缓存区结束-DOSstart+10h;将转换后的字符存储在这里
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

 mov si,未知文件系统-DOSstart+10h
 cmp byte [bx+4],0h
 jz 显示文件系统类型

 mov si,FAT16-DOSstart+10h
 cmp byte [bx+4],6h
 jz 显示文件系统类型

 mov si,FAT32-DOSstart+10h
 cmp byte [bx+4],0bh
 jz 显示文件系统类型

 mov si,扩展-DOSstart+10h
 cmp byte [bx+4],5h
 jz 显示文件系统类型

 mov si,NTFS-DOSstart+10h
 cmp byte [bx+4],7h
 jz 显示文件系统类型

 mov si,扩展-DOSstart+10h
 cmp byte [bx+4],0Fh
 jz 显示文件系统类型

 mov si,Linux-DOSstart+10h
 cmp byte [bx+4],83h
 jz 显示文件系统类型
 mov si,未知文件系统-DOSstart+10h
 
显示文件系统类型:
 push bx
 call 打印
 mov si,分区-DOSstart+10h
 call 打印
 pop bx

 没有个分区:
 add bx,16;推进到下一个分区
 cmp cl,4
jnz 下一个分区;检测下一个分区

mov si,按数字选择分区-DOSstart+10h
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
mov si,不操作-DOSstart+10h
call 打印
jmp DOSstart
不操作 db 'Not operate',13,10,0

不小于则跳转_操作:
mov bx,0
mov ah,14;BIOS中断参数
int 10h;显示字符

mov bx,cs:[路径缓存区结束-DOSstart+10h]
sub al,'1';从字符变为数值
mov ah,0;清空高位以便进行加法
shl ax,4;乘以16
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
shl ebx,16;段地址移到高位
mov bx,cs:[路径缓存区结束-DOSstart+10h];偏移地址，在此处放置扇区
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
jmp DOSstart-DOSEnd+10h;滚回去
妳按了其他键 db 'oijh',13,10,0

应用设定:
mov word cs:[扇区大小-DOSstart+10h],2048
mov eax,cs:[bx+156+2];根目录的目录项+2双端格式的范围位置 (LBA)，2~8÷2
mov ecx,cs:[bx+156+10];根目录的目录项+10双端格式的数据长度（范围大小）
mov cs:[当前目录号-DOSstart+10h],eax;save
mov cs:[iso9660目录长度-DOSstart+10h],ecx
jmp DOSstart-DOSEnd+10h;滚回去

文件系统代号 db 69h
iso9660文件系统 db 'iSO9660',13,10,0



;cmp FAT







未检测到文件系统:
mov si,告诉她没检测到文件系统
call 打印
jmp DOSstart-DOSEnd+10h;滚回去

告诉她没检测到文件系统 db '123456',13,10,0
按一使用设定 db '123456',13,10,0





实现_Ls:
实现_dir:
movzx bx,byte cs:[文件系统代号-DOSstart+10h]
shl bx,1;乘以2
add bx,文件系统代号-DOSstart+10h;加上基地址
mov bx,cs:[bx];取最终地址
jmp 不支持的文件系统

文件系统类型表:
dw 不支持的文件系统-DOSstart+10h
dw iso9660-DOSstart+10h
dw FAT-DOSstart+10h
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

不支持的文件系统:
mov si,不支持的文件系统_
call 打印
jmp DOSstart;滚回去
不支持的文件系统_ db '12345678',13,10,0


iso9660:
mov word cs:[目录扇区结束-DOSstart+10h],0;清空计数
mov word cs:[目录项序号-DOSstart+10h],0
mov eax,cs:[当前目录号-DOSstart+10h]
mov eax,cs:[iso9660目录长度-DOSstart+10h]
mov edx,0;清空除法高位
movzx ebx,word cs:[扇区大小-DOSstart+10h]
div ebx;edx高：eax低÷ebx =eax……edx
mov ecx,eax;循环次数

iso9660_下一个扇区:
 push ecx

 mov edx,0;清空LBA高位
 mov bx,0FFFFh
 shl ebx,16;段地址移到高位
 mov bx,cs:[路径缓存区结束-DOSstart+10h];偏移地址，在此处放置目录项扇区
 mov ecx,1;只读一个扇区
 call 读盘

 inc eax;推进到下一个扇区
 push eax;LBA号

    小于则跳转_cd1下一个项:
     cmp word es:[di],0;这个项的长度
     jz 触底
     push word es:[di];取这个项的长度

     cmp byte es:[di+32],0;文件名长度
     jz 没有文件名

     mov eax,es:[di+2];2双端格式的范围位置 (LBA)，2~8÷2
     mov ecx,es:[di+10];双端格式的数据长度（范围大小）
     add word cs:[目录扇区结束-DOSstart+10h],8;推进到下一个项的位置
     mov bx,cs:[目录扇区结束-DOSstart+10h];在此处保存簇号
     mov cs:[bx],eax;save
     mov cs:[bx+4],ecx

     push di;di会被多次修改
     inc word cs:[bp+目录项序号-DOSstart]
     movzx eax,word cs:[bp+目录项序号-DOSstart]
     call 二进制转十进制ascall码
     mov al,10;先回车
     mov ah,13
     stosw
     mov si,di;字符的位置
     std;倒序读取
     call 打印

     pop di
     dec sp;再次保留di
     dec sp
     movzx cx,byte es:[di+32];取文件名长度
     add di,33;指向实际文件名
     mov al,'#'
     stosb
     cld;恢复正序

        显示完文件名:
         mov al,es:[di];文件名的一个字符
         inc di

         mov bx,0
         mov ah,14;BIOS中断参数
         int 10h;显示字符
        loop 显示完文件名
        pop di

     没有文件名:
     pop ax
     add di,ax
     cmp di,[bp+目录扇区结束-DOSstart];逐一扇区进行处理
    jb 小于则跳转_cd1下一个项

 pop eax;弹出LBA号
 pop ecx;循环次数
 dec ecx
jnz iso9660_下一个扇区
触底:
jmp DOSstart-DOSEnd+10h;滚回去
































int21:
push ax
mov ax,ss
cmp ax,0FFFFh
pop ax
jz 不改变栈
mov cs:[0FFFdh],sp;保存原栈
mov cs:[0FFFbh],ss
mov sp,0FFFFh
mov ss,sp
sub sp,4

不改变栈:
push eax
push ecx
push edx
push esi
push edi
push ebp
push ds
push es
pushf


FAT:
mov word cs:[bp+目录项序号-DOSstart],0
mov ax,[bp+路径缓存区结束-DOSstart]
add ax,[bp+扇区大小-DOSstart]
mov [bp+目录扇区结束-DOSstart],ax;用于快速进入目录



mov eax,[bp+当前目录号-DOSstart]
call 簇转LBA

下一个扇区_32:

mov bx,0FFFFh
shl ebx,16;段地址移到高位
mov bx,[bp+目录扇区结束-DOSstart];在此之后放置目录项扇区
mov cx,0
mov edx,0;清空LBA高位
call 读盘

mov di,[bp+目录扇区结束-DOSstart]
sub di,32
不正常的项:
add di,32
mov ax,[bp+目录扇区结束-DOSstart]
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
shl di,1;乘以2
add di,[bp+目录扇区结束-DOSstart]
mov eax,0
mov ax,cs:[bp+目录项序号-DOSstart]




ABCD mov eax,0FFFFFFFh
call 二进制转十进制ascall码
dec di;减一以免取到下一个字符
mov si,di
std
call 打印
cld;恢复正序

mov al,' '
 xor bx,bx
 mov ah,14;BIOS中断参数
 int 10h;显示字符
jmp DOSstart













短文件名:

add di,32;20h，DI指向下一个文件条目的32字节结构体开头处




;[bp+扇区大小-DOSstart]

;unREAL:








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
 div ebx
 add dl,'0';此0非彼0
 xchg al,dl
 stosb;存入
 mov al,dl;恢复AL

 cmp eax,0
jnz 不为零则跳转
ret


;EAX，EBX寄存器将会被修改
;输入
;EBX >待转换数值
;DS：DI >缓存区
;输出
;DS：DI >16进制ascall码，结尾为0，注意倒序应使用std指令
二进制转十六进制ascall码:
mov al,0;用于标记结束
stosb
还没完成:
 mov al,bl
 shr ebx,4;显示了一位
 and al,00001111b;只保留低四位
 cmp al,10;是字母
 jb 小于则跳转
 add al,7;补齐，数字到字母之间隔了几个符号
 小于则跳转 add al,'0';此0非彼0
 stosb;存入
 cmp ebx,0
jnz 还没完成
ret


;CX，SI，DI寄存器将会被修改
;输入
;CX >
;DS：SI >
;ES：DI >
; 复制数据:;加了这么多指令还能提速吗
; cmp cx,4
; jb 小于则跳转_太小的数就没必要了
; push cx
; shr cx,2;以4倍速度复制
; rep movsd
; pop cx
; test cx,11b
; jz 刚好复制完
; and cx,11b;只保留低二位
; 小于则跳转_太小的数就没必要了:
; rep movsb
; 刚好复制完:
; ret


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



当前目录号 db 69h
iso9660目录长度 dd 0
目录项序号 dw 0
目录扇区结束 dw 0






实现_drvnum:




实现_cd:
路径缓存区结束 dw DOSEnd-DOSstart+10;在此之前是路径，为什么要+更多的值，令人疑惑的，注意









jnc 不设置进位
popf
stc;设置进位
pushf
不设置进位:
popf
pop es
pop ds
pop ebp
pop edi
pop esi
pop edx
pop ecx
pop eax
pop ss
mov sp, cs:[0FFFdh];还原栈
retf


;将会修改EBX，DX，SI寄存器
;从硬盘读取一个扇区数据
;输入
;EAX >LBA低32位
;EDX >LBA高32位
;EBX >高32位段地址+低32位偏移地址
;ECX >读入扇区数
;输出
;EBX >目标位置
读盘:;读硬盘调用+增加dpa包是加扇区
mov cs:[bp+偏移地址-DOSstart],bx
shr ebx,16;将段地址从高位移下来
mov cs:[bp+段地址-DOSstart],bx
mov cs:[bp+LBA低位-DOSstart],eax
mov cs:[bp+LBA高位-DOSstart],edx
jmp 没用到高位;第一次读取不要操作

继续读取:
mov bx,[bp+扇区大小-DOSstart]
add cs:[bp+偏移地址-DOSstart],bx
inc dword cs:[bp+LBA低位-DOSstart]

jnc 没用到高位
dec dword cs:[bp+LBA低位-DOSstart];触发溢出我们将其拉回来
inc dword cs:[bp+LBA高位-DOSstart]

没用到高位:
mov si,参数块-DOSstart+10h
mov dl,cs:[bp+驱动器号-DOSstart]
mov ah,42h;扩展调用
int 13h
jc 读盘错误;发生错误后就没必要继续读取了
dec ecx
jnz 继续读取
读盘错误:;进位会被设置
ret

参数块 db 16;[0]参数块大小
db 0;[1]保留，必须为0
db 1;[2]要传输的块数0~127
db 0;[3]保留，必须为0
偏移地址 dw 0;[4]
段地址 dw 0;[6]
LBA低位 dd 0;[8]低32位
LBA高位 dd 0;[12]高32位

驱动器号 db 0
扇区大小 dw 0


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
mov bp,Gdtinfo-DOSstart+10h

in al,92h;打开A20
or al,10b
out 92h,al

lgdt cs:[bp];读入GDT长度及位置
mov eax,cr0
or al,1b
cli
mov cr0,eax
jmp 8:pmode-DOSstart+10h
pmode:
mov bp,16
mov gs,bp
and al,11111110b
mov cr0,eax
jmp 0FFFFh:unreal-DOSstart+10h
unreal:
popf;不需要sti
pop bp
pop eax
retf

Gdtinfo:
dw GdtEnd-GdtStart-1;长度-1以忽略后一字节
dd GdtStart-DOSstart+10h+0FFFFh
GdtStart:
dq 0h
db 0xff, 0xff, 0, 0, 0, 10011010b, 00000000b, 0
db 0xff, 0xff, 0, 0, 0, 10010010b, 11001111b, 0
GdtEnd:










DOSEnd:











