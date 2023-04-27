;这是个加载程序，也就是引导的第二阶段
;我不会使用一些不直观的指令比如，xor ax,ax
;2023年
;该死的win系统损坏，害得我丢失亿些东西，只能重新写了



call $+3
pop si
add si,DOSstart-3;并减去call指令占用的位置
mov bx,cs
shl bx,4;段转偏移
add si,bx
mov bx,0h
mov ds,bx
dec bx;AX变FFFF
mov es,bx
mov di,10h
mov cx,DOSEnd-DOSstart
mov dx,cx
shr cx,2;除以4，以便最高效复制
and dx,1111b;只保留低四位
add cx,dx;由于位移除法会丢失余数我们加上

in al,92h;别忘了打开A20
or al,10b
out 92h,al
rep movsd

mov [36h],bx;现在写入我们的中断程序
mov ax,int8-DOSstart+10h;加上我们的基地址10h
mov [34h],ax

mov [86h],bx
mov ax,int21-DOSstart+10h
mov [84h],ax
jmp 0FFFFh:10h;进入命令处理程序

DOSstart:;垃圾nasm编译器不支持双org
mov sp,0FFFFh
mov ds,sp
mov es,sp
mov ss,sp
mov di,cs:[缓存区]
mov si,di

; mov ebx,8ffbbch
; mov di,DOSEnd-DOSstart+10h
; call 二进制转十六进制ascall码
; std
; mov si,di
; dec si;减一以免取到下一个字符
; jmp 打印


; 继续打印:;每个指令都很重要确保他们被正确执行
 ; xor Bx,Bx
 ; mov ah,14;BIOS中断参数
 ; int 10h;显示字符

 ; 打印:
 ; lodsb;将DS：SI指向的内容放入al然后SI+1
 ; or al,al;判断al中的字符值是否 =0
 ; jnz 继续打印
; jmp $

stosb
等待指令:
mov ah,0h
int 16h
cmp al,8h

jnz 不是退格
dec di;删个字符
mov bx,0h
mov ah,0eh
int 10h
mov al,' '
int 10h
mov al,8h;再次退格

不是退格:
mov bx,0h
mov ah,0eh
int 10h

stosb;保存输入
cmp al,0dh
jz 准备_处理指令
jmp 等待指令
缓存区 dw DOSEnd-DOSstart+10h;取我们的缓存区，在此之前是路径


准备_处理指令:
lodsb
cmp al,0dh
jz 指令结束
push ax
mov bx,命令数据-DOSstart+10h;人类从1开始计数，我们也一样，null 0留给程序用
jmp 继续制作命令表

处理指令:;输入错误的字符可能导致意外执行
lodsb
cmp al,0dh
jz 指令结束
cmp al,' '
jz 指令结束
push ax;保存字符

继续制作命令表:
mov ax,cs:[bx];低位是数据，高位是偏移
movzx di,al;能清空di高位吗
add di,命令表-DOSstart+10h+1;加上基地址，即将放入的位置
stosb
inc bx;di会加1，但我们要bx加2以取下一个数据
inc bx
cmp byte cs:[bx],0;遇到结束符
jnz 继续制作命令表;还没完

pop ax
and al,11011111b;转换为大写，原本就是则不变
sub al,20h;从字符转换为偏移
movzx bx,al
add bx,命令表-DOSstart+10h+1;加上基地址
mov bl,cs:[bx];取下一个指令的位置
jmp 处理指令

指令结束:
cmp bl,11
ja 指令结束
mov bh,0
shl bx,1;乘以2
add bx,位置表-DOSstart+10h;加上基地址
mov bx,cs:[bx];取最终地址
jmp bx

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
命令表:;如果命令过多还是单独弄个表为妙，用TXT格式保存怎么样
db 0;null
A_1 db 0;这是字符
db 0;这是数据
B_2 db 0;mbr
db 0;这是数据
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
M_13 dw 0;mbr
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
命令数据:
db C_3-命令表;最好还是按顺序排序，当然也可以不用
db 含cd-命令数据

db D_4-命令表
db 含dirDrvnum_2-命令数据

db F_6-命令表
db 含fs_2-命令数据

db G_7-命令表
db 含gpt_2-命令数据

db L_12-命令表
db 含Ls-命令数据

db M_13-命令表
db 含mbr-命令数据

db O_15-命令表
db 含openOff_2-命令数据

db R_18-命令表
db 含run_2-命令数据

db S_19-命令表
db 含shutdown_2-命令数据

db H_8-命令表
db 含help_2-命令数据
db 0;结束符，可用
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
含cd:
db D_4-命令表
db cd-位置表
db 0;结束符
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
含dirDrvnum_2:
db i_9-命令表
db 含dir_3-命令表
db R_18-命令表
db 含Drvnum_3
db 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
含dir_3:
db R_18-命令表
db dir-位置表
db 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
含Drvnum_3:
db M_13-命令表
db 含Drvnum_3-命令表
db N_14-命令表
db 含Drvnum_3-命令表
db U_21-命令表
db 含Drvnum_3-命令表
db V_22-命令表
db drvnum-位置表
db 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
含Ls:
db S_19-命令表
db 0
db 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
含mbr:
db B_2-命令表
db mbr-位置表
db 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
含openOff_2:
db F_6-命令表
db off_3-命令表;叠词词，恶心心
db P_16-命令表
db 含open_3-命令表
db 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
off_3:;以后我们会处理叠词的，现在暂时忽略
db F_6-命令表
db off-位置表
db 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
含open_3:
db E_5-命令表
db 含open_3-命令表
db N_14-命令表
db open-位置表
db 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
含run_2:
db U_21-命令表
db 含run_2-命令表
db N_14-命令表
db run-位置表
db 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
含help_2:
db E_5-命令表
db 含help_2-命令表
db 含help_2-命令表
db L_12-命令表
db 含help_2-命令表
db P_16-命令表
db help-位置表
db 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
含shutdown_2:
db H_8-命令表
db 含shutdown_2-命令表
db U_21
db 含shutdown_2-命令表
db T_20
db 含shutdown_2-命令表
db D_4-命令表
db 含shutdown_2-命令表
db O_15-命令表
db 含shutdown_2-命令表
db W_23
db 含shutdown_2-命令表
db N_14-命令表
db shutdown-位置表
db 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
含fs_2:
db S_19-命令表
db _fs-位置表
db 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
含gpt_2:
db P_16-命令表
db 含gpt_2-命令表
db T_20-命令表
db gpt-位置表
db 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

位置表:
Ls dw 0
dir dw 0
drvnum dw 0
mbr dw 0
_fs dw 0
gpt dw 0
cd dw 0
shutdown dw 0
off dw 0
open dw 0
run dw 0
help dw 0





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

mov bp,int21-DOSstart+10h;堆，覆盖整个程序
cmp bx,7
;ja 功能号太大
shl bx,1;乘以2
add bx,功能表-DOSstart+10h
mov bx,cs:[bx+2];人类从1开始计数，我们也一样
jmp bx
功能表:
dw 实现_Ls-DOSstart+10h
dw 实现_dir-DOSstart+10h

dw 实现_dir-DOSstart+10h
dw 实现_dir-DOSstart+10h
dw 实现_dir-DOSstart+10h




mov byte cs:[bp+目录序号-DOSstart],0
实现_Ls:
实现_dir:

























;call 十六进制转十进制ascall码







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

; ;EAX，EBX寄存器将会被修改
; ;输入
; ;EBX >待转换数值
; ;DS：DI >缓存区
; ;输出
; ;DS：DI >16进制ascall码，结尾为0，注意倒序应使用std指令
; 二进制转十六进制ascall码:
; mov al,0;用于标记结束
; stosb
; 还没完成:
 ; mov al,bl
 ; shr ebx,4;显示了一位
 ; and al,00001111b;只保留低四位
 ; cmp al,9;是字母
 ; jbe 小于等于则跳转

 ; add al,7;补齐，数字到字母之间隔了几个符号

 ; 小于等于则跳转:
 ; add al,'0';此0非彼0
 ; stosb;存入
 ; cmp ebx,0
; jnz 还没完成
; ret


文件系统 db 0
当前目录簇号 dw 0
目录序号 db 0







实现_drvnum:

实现_mbr:

实现_fs:

实现_gpt:

实现_cd:










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
;CX >读入扇区数
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
loop 继续读取
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











