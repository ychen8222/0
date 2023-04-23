;这是个加载程序，也就是引导的第二阶段
;2023年
;该死的win系统损坏，害得我丢失亿些东西，只能重新写了



call $+3
pop si
add si,DOSstart;准备复制到BIOS后方
mov bx,cs
shl bx,4;段转偏移
add si,bx
mov bx,0h
mov ds,bx
dec bx;AX变FFFF
mov es,bx
mov di,10h
mov cx,DOSend-DOSstart
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
mov ax,int35-DOSstart+10h
mov [84h],ax
jmp 0FFFFh:10h;进入命令处理程序



DOSstart:
mov sp,0FFFFh
mov ds,sp
mov es,sp
mov ss,sp
mov di,cs:[缓存区]
mov si,di

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
缓存区 dw DOSend-DOSstart+10h;取我们的缓存区，在此之前是路径


准备_处理指令:
mov bx,命令表+10
处理指令:
lodsb
cmp al,0dh
jz 指令结束
cmp al,' '
jz 指令结束

and al,11011111b;转换为大写，原本就是则不变
sub al,20h;转换为偏移
add bl,al
mov bl,cs:[bl]


jmp 处理指令
命令表:

A db 0
B db _Lim-命令表;mb_r
C db ;c_d
D db ;cd，d_ir
E db 0
F db 0
G db 0
H db 0
i db 0
J db _dir-命令表
K db 0
L db _Lim-命令表;L_s
M db _Lim-命令表;m_br
N db 0
O db ;o_pen
P db 0
Q db 3
R db 0
S  db 0
T db 1
U db 2
V db 0
W db 0
X db 0
Y db 0
Z db 0


i:

S  db 0


位置表:
Ls dw 
dir dw
mbr dw
cd dw
shutdown dw
off dw
open dw
run dw

指令结束:
cmp bx,0

jmp bx










DOSend: