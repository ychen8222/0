;============================================================================
;iSO文件的引导扇区\
@ychen

;2023年3月
;编写完成\
@cya

;26日
;添加检索文件夹\
@cya

;6月22日
;支持iSO9660的变体Joliet\
@cya
;----------------------------------------------------------------------------

;内存布局
缓存区_1 equ 500h
缓存区_2 equ 2000h
org 7c00h;～？=iSO.Bin


mov ax,0
mov ds,ax
mov es,ax
mov ss,ax
mov esp,7c00h;清空高位

mov ax,4b01h;获取光盘仿真状态，与AX=4b00h相同但不终止仿真
mov si,缓存区_1
mov [驱动器号],dl
int 13h
jnc 判断仿真模式;CF被设置

mov si,消息光盘错误
jmp 打印并退出
消息光盘错误 db 13,10,'Disc error',0

判断仿真模式:
cmp byte [si+1],0;=无仿真，1=仿真1.2M软盘，2=仿真1.44M软盘，3=仿真2.88M软盘，4=仿真硬盘
jz 对比驱动器号

mov si,消息光盘处于仿真模式
jmp 打印并退出
消息光盘处于仿真模式 db 13,10,'Disc is in an emulation mode',0

对比驱动器号:
mov dl,[si+2];DS：Si规格包已填充
cmp [驱动器号],dl;驱动器号应该相同
jz 判断文件系统类型

mov si,消息驱动器号不同
jmp 打印并退出
消息驱动器号不同 db 13,10,'Drive letters are different',0


判断文件系统类型:
mov ebp,16;必须从第16扇区开始
mov ebx,缓存区_1;清空高位
mov dh,0FFh;最大判断次数

下一个卷:
 mov eax,ebp
 call 读盘
 inc ebp;准备读取下一个卷，一个扇区为一个卷
 mov si,二卷
 mov di,缓存区_1
 mov cx,6
 repe cmpsb
 jnz 不会是Joliet

 mov si,Joliet标识
 mov di,缓存区_1+58h;偏移，不知道为什么要放在这里
 mov cx,3
 repe cmpsb
 jz Joliet文件系统

 不会是Joliet:
 dec dh;不能被JZ指令跳过
 cmp byte[缓存区_1],0FFh;最后一个卷
 jz 尝试扩展卷

 cmp dh,0
jnz 下一个卷

jmp iSO9660文件系统;終了

尝试扩展卷:
mov eax,ebp
call 读盘
inc ebp;准备读取下一个卷，一个扇区为一个卷
mov si,扩展描述
;mov di,1;没有序号
mov cx,5
repe cmpsb
jnz iSO9660文件系统;没有扩展卷则直接跳走

下一个扩展卷:
 mov eax,ebp
 call 读盘
 inc ebp;准备读取下一个卷，一个扇区为一个卷

 mov si,扩展描束;结束标识
 ;mov di,1;没有序号
 mov cx,5
 repe cmpsb
 jz iSO9660文件系统;終了

 mov si,UDFS标识
 xor di,di
 mov cx,4
 repe cmpsb
; jz UDFS文件系统

dec dh
jnz 下一个扩展卷


iSO9660文件系统:
mov byte[文件系统类型],1;标记为iSO9660文件系统
mov eax,16;再次读取iSO9660主卷描述符
;mov bx,缓存区_1
call 读盘
mov si,缓存区_1+1;+1跳过卷描述符前面表示卷号的Byte
mov ax,2020h;2个空格
mov [si+5],ax;覆盖掉不知道什么东西以免影响显示
call 打印
mov si,换行
call 打印
mov ax,[缓存区_1+128]
mov [扇区大小],ax
mov ebx,[缓存区_1+156+2];根目录的目录项+2双端格式的范围位置 (LBA)，2~8÷2
mov eax,[缓存区_1+156+10];根目录的目录项+10双端格式的数据长度（范围大小）
mov [根目录逻辑扇区],ebx;备份Loader需要的参数
mov [根目录大小],eax;RootSize
mov cx,BOOT
mov dl,1;获取的类型为文件夹
mov si,4;文件夹名长度
call iSO9660对比项
jc 没有找到BOOT文件夹

call 打印斜杠
mov cx,LOADER
mov dl,0;获取的类型为文件
mov si,10;文件名长度
call iSO9660对比项
jc 没有找到LOADER文件

mov ecx,缓存区_1
call iSO9660读入扇区
mov eax,[根目录大小]
mov bx,[扇区大小]
mov ecx,[根目录逻辑扇区]
mov dl,[驱动器号]
mov dh,[文件系统类型]
mov bp,0AA55h;我们的标识
jmp 0:缓存区_1



Joliet文件系统:
mov byte[文件系统类型],3;标记为Joliet文件系统
mov si,缓存区_1+6+2;+6跳过卷描述符前面表示卷号的Byte和CD001还有+2跳过不知道是什么的东西
mov ax,2020h;2个空格
mov [si-2],ax;-2覆盖掉不知道什么东西以免影响显示

UTF16字符前面的_0填充为空格:;
lodsw
cmp ax,0
jz UTF16字符前面的_0已经填充完了

mov byte[si-2],' ';-2以抵消lodsw的推进并填充空格
jmp UTF16字符前面的_0填充为空格

UTF16字符前面的_0已经填充完了:;
mov si,缓存区_1+1;+1跳过卷描述符前面表示卷号的Byte
call 打印
mov si,换行
call 打印
mov ax,[缓存区_1+128]
mov [扇区大小],ax
mov ecx,[缓存区_1+156+2];根目录的目录项+2双端格式的范围位置 (LBA)，2~8÷2
mov eax,[缓存区_1+156+10];根目录的目录项+10双端格式的数据长度（范围大小）
mov [根目录逻辑扇区],ebx;备份Loader需要的参数
mov [根目录大小],eax;RootSize
mov si,BOOT
mov dl,1;需要文件夹
call Joliet的检索文件或文件夹
jc 没有找到BOOT文件夹

call 打印斜杠
mov si,LOADER
mov dl,0;需要文件
call Joliet的检索文件或文件夹
jc 没有找到LOADER文件

mov ebx,ecx
mov ecx,缓存区_1
call iSO9660读入扇区
mov eax,[根目录大小]
mov bx,[扇区大小]
mov ecx,[根目录逻辑扇区]
mov dl,[驱动器号]
mov dh,[文件系统类型]
mov bp,0AA55h;我们的标识
jmp 0:缓存区_1



没有找到BOOT文件夹:
mov si,BOOT;用于显示没有检索到
jmp 显示没有找到的文件或文件夹

没有找到LOADER文件:
mov si,LOADER;用于显示没有检索到
jmp 显示没有找到的文件或文件夹


;将会修改AX，BH，Si寄存器
;输入DS：Si文件或文件夹名的位置
;输出
显示没有找到的文件或文件夹:
mov [u16_1],si
mov si,NONE
call 打印
mov si,[u16_1]

打印并退出:
call 打印
int 18h;返回BiOS



;将会修改EAX，EBX，CX，DX，Si，Di寄存器
;输入EAX数据长度，EBX逻辑扇区号，CX文件名位置，DL属性，Si文件名长度
;输出EAX数据长度，EBX逻辑扇区号
iSO9660对比项:
sub sp,8
mov byte[esp+0],0;第1项文件名长度
mov [esp+1],cx;第2项文件名位置
mov [esp+3],si;第2项文件名长度
mov word[esp+5],0;光标位置
mov byte[esp+7],1;上1项字符长度 应该是0但使用此值会导致某些BiOS清空全屏，所以使用1来解决
mov bp,ax
mov [u16_1],bx
mov [u8_1],dl
cmp si,8
jbe 不需要短文件名;小于等于则跳转

mov di,缓存区_2
mov cx,9
cld;正序
rep movsb
mov di,缓存区_2;扫描复制过去的字符里的点
mov al,'.'
mov cx,9
mov bh,0FFh;用于标记是否找遇到过点
继续对比字符:
repne scasb
jnz 没有遇到点

mov bh,cl

没有遇到点:
cmp cl,0
jnz 继续对比字符

cmp bh,0FFh
jnz 有点

mov byte[esp+0],8;先设置 第1项文件名长度 默认长度
;没点则继续扫描源字符内的点，如果遇到第一个点后停止扫描并复制点后面的字符大于三个就只复制三个，小于或等于三则全部复制
mov di,9;总长度
mov cx,[esp+3];第2项文件名长度
sub cx,di;减去已扫描的长度得到剩余需要扫描的长度
add di,[esp+1];加上 第2项文件名位置 起始得到剩下部分的位置
repne scasb;遇到点则停止
jnz 不需要短文件名;没点

mov si,di;将点后的字符复制进缓存区
mov di,缓存区_2+9;不能覆盖之前复制进去的字符
mov byte[di-1],'.';写入1个点
mov bh,9;点前字符长度
jmp 复制后缀名

有点:;如果有点则复制点后面的字符大于3个就只复制3个，小于或等于3则全部复制
mov dl,9;总长度
sub dl,bh;减去剩余部分得到已扫描的长度
mov bh,dl;同时也是点前字符长度
mov cl,[esp+3];第2项文件名长度 CX高位已被清空
sub cl,dl;减去已扫描的长度得到需要复制的长度
movzx di,dl;缓存区内偏移
add di,缓存区_1;加上缓存区地址得到需要复制到的位置
movzx si,dl;第2项文件名内偏移
add si,[esp+1];加上 第2项文件名位置 起始得到剩下部分的位置

复制后缀名:
cmp cl,3
jbe 复制全部后缀名;大于等于则跳转

mov cl,3

复制全部后缀名:
add bh,cl;+点后字符长度
rep movsb
mov [esp+0],bh;第1项文件名长度

不需要短文件名:
call 获取光标位置
mov [esp+5],dx;刷新 光标位置
mov ax,bp
mov bx,[u16_1]
mov cl,[u8_1]

继续对比:
call iSO9660获取一个项
jc 项已完结

mov [u32_1],eax;逻辑扇区号
mov ebp,ecx;iSO9660数据长度
mov dx,[esp+5];光标位置
movzx cx,byte[esp+7];上1项字符长度
call 重置光标并清除前文件名
mov [esp+7],bl;刷新 上1项字符长度
movzx cx,bl;字符长度
movzx dx,bl
mov si,di;字符地址
call 显示项名
mov bx,di
cmp dx,[esp+0];第1项文件名长度
jnz 尝试第二项;第一项名长不匹配

mov cx,dx;字符长度
mov si,缓存区_2;第1项文件名位置
rep cmpsb
jz 项名相同

尝试第二项:
cmp dx,[esp+3];第2项文件名长度
jnz 继续对比;文件名不一样长就不用对比了

mov cx,dx;字符长度
mov si,bx;字符地址
call UTF16字符串内的小写字母转成大写
mov cx,dx;字符串长度
mov si,[esp+1];第2项文件名位置
mov di,bx;字符地址
rep cmpsb
jnz 继续对比

项名相同:
and byte[标志],11111110b;触发重置
mov eax,ebp;逻辑扇区号
mov ebx,[u32_1];iSO9660数据长度
add sp,8
clc
ret

项已完结:
mov dx,[esp+5];光标位置
mov cx,[esp+7];上一项字符长度
call 重置光标并清除前文件名
add sp,8
stc
ret





;将会修改EAX，EBX，CX，DX，Si，Di寄存器
;输入EAX数据长度，ECX逻辑扇区号，DL属性，Si文件名位置
;输出EAX数据长度，ECX逻辑扇区号
Joliet的检索文件或文件夹:
sub sp,4
;mov byte[esp+0],文件或文件夹名长度
;mov word[esp+1],光标位置
mov byte[esp+3],1;上1项字符长度 应该是0但使用此值会导致某些BiOS清空全屏，所以使用1来解决
mov [u32_1],eax
mov ebp,ecx
mov bl,dl
mov di,缓存区_2;文件或文件夹名位置
call UTF8字符串转UTF16字符串
sub di,缓存区_2
mov ax,di
mov [esp+0],al;文件或文件夹名长度
mov si,缓存区_2
mov cx,di
shr cx,1;除以2，因为UTF16至少为Word大小
call UTF16字符串内的小写字母转成大写
call 获取光标位置
mov [esp+1],dx;光标位置
mov eax,[u32_1]
mov ecx,ebp
mov dl,bl

对比下一个项_1:
call Joliet获取一个项
jc 项已获取完_1

mov [u32_1],eax
mov ebp,ecx
movzx cx,byte[esp+3];上1项字符长度
mov dx,[esp+1];光标位置
call 重置光标并清除前文件名
mov [esp+3],bl;刷新上1项字符长度
mov si,di;文件或文件夹名位置
movzx cx,bl;文件或文件夹名长度
call 显示项名
cmp bl,[esp+0];文件或文件夹名长度
jnz 对比下一个项_1

mov si,di
shr bl,1;除以2，因为UTF16至少为Word大小
movzx cx,bl
call UTF16字符串内的小写字母转成大写
mov si,缓存区_2
movzx cx,bl
repe cmpsw
jnz 对比下一个项_1

mov eax,[u32_1]
mov ecx,ebp
and byte[标志],11111110b;触发重置
add sp,4
clc
ret

项已获取完_1:
movzx cx,byte[esp+3];上1项字符长度
mov dx,[esp+1];光标位置
call 重置光标并清除前文件名
add sp,4
stc
ret




























;AX，BH，CX，DX寄存器将会被修改
;无输入
;输出DX光标位置
获取光标位置:
mov ah,3;调用号
mov bh,0;页码
int 10h; AX=0000h(Phoenix BiOS)，CH起始扫描线，CL结束扫描线，DH行（00h位于顶部），DL列（00h位于左侧）
ret



;将会修改AX，BH寄存器
;输入CX覆盖长度，DX光标位置
;输出
重置光标并清除前文件名:
mov ah,2;功能号
mov bh,0;页码
int 10h
mov al,' ';用空格覆盖
mov ah,10;功能号
;mov bh,0;页码
int 10h
ret



;AX，BH，CX，Si寄存器将会被修改
;输入CX字符长度，Si项名
;输出
显示项名:
mov ah,14;功能号
mov bh,0;页码

循环显示完项名:
 lodsb
 int 10h
loop 循环显示完项名
ret



;将会修改EAX，EBX，ECX，DX，Si，Di寄存器
;输入EAX数据长度，ECX逻辑扇区号，BL第一次需要属性
;输出EAX数据长度，ECX逻辑扇区号，BL字符长度，Di字符地址
;错误则设置进位
iSO9660获取一个项:
test byte[标志],1b;被测试位=0则ZF=1
jnz 不要重置_1

or byte[标志],1b;取消下次重置
mov [文件属性号],bl
mov [逻辑扇区号],ecx
mov edx,0;清空除法高位
movzx ecx,word[扇区大小]
div ecx;edx高：eax低÷ecx=eax…edx
cmp dx,0
jz 不增加一个扇区_1

inc ax;超出一个字节都需要读完整个扇区

不增加一个扇区_1:
mov [循环次数],ax
mov eax,[逻辑扇区号]
mov bx,缓存区_1
call 读盘
inc dword[逻辑扇区号];预先推到下一个扇区
mov bx,缓存区_1
movzx ax,byte[缓存区_1];跳过一个.目录
add bx,ax
mov al,[bx];跳过一个..目录
add bx,ax
mov [扇区内数据位置],bx
jmp 不要读盘;第一次则直接读取项

不要重置_1:
mov bx,[扇区内数据位置]
mov dx,0;不允许推进

属性不同:
add bx,dx;推进到下一个项
mov ax,[扇区大小]
add ax,bx
cmp bx,ax
jb 不要读盘;小于则跳转

触底:
dec word[循环次数]
jz 扇区读完

mov eax,[逻辑扇区号]
mov bx,缓存区_1
call 读盘
inc dword[逻辑扇区号];预先推到下一个扇区

不要读盘:
movzx dx,byte[bx];取这个项的长度
cmp dl,0
jz 触底;遇到空项

mov di,iSO9660属性表
mov al,[bx+25];取属性
call 对比文件属性
jnz 属性不同

mov eax,[bx+2];2双端格式的范围地址 (LBA)，2~8÷2
mov ecx,[bx+10];双端格式的数据长度（范围大小）
lea di,[bx+33];文件名
add dx,bx
mov [扇区内数据位置],dx;推进到下一个项
movzx bx,byte[bx+32];文件名长度
cmp byte[文件属性号],1;属性为文件夹则不需要减2
jz 已省略iSO9660版本号

cmp word[bx+di-2],';1'
jnz 已省略iSO9660版本号

dec bl;文件名长度-2
dec bl

已省略iSO9660版本号:
clc
ret

扇区读完:
and byte[标志],11111110b
stc
ret

属性表:
iSO9660属性表:;
dw iSO9660文件
dw iSO9660文件夹

db 1;长度
iSO9660文件:;
db 0;属性

db 1;长度
iSO9660文件夹:;
db 2;属性









;将会修改EAX，EBX，ECX，DX，Si，Di寄存器
;输入EAX数据长度，ECX逻辑扇区号，DL第一次需要属性
;输出EAX数据长度，ECX逻辑扇区号，BL字符长度，Di字符地址
;test指令示例test al,0000_0100b;被测试位 =0则ZF =1
Joliet获取一个项:
mov bx,[扇区内数据位置]
test byte[标志],1b
jnz 获取项_1

or byte[标志],1b;取消下次重置
mov [文件属性号],dl
mov [逻辑扇区号],ecx
mov edx,0;清空除法高位
movzx ecx,word[扇区大小]
div ecx;edx高：eax低÷ecx=eax…edx
cmp dx,0
jz 不增加一个扇区_3

inc ax;超出一个字节都需要读完整个扇区

不增加一个扇区_3:
mov [循环次数],ax
mov eax,[逻辑扇区号]
mov ebx,缓存区_1
call 读盘
inc dword[逻辑扇区号];预先推到下一个扇区
movzx ax,byte[bx];跳过一个.目录
add bx,ax
mov al,[bx];跳过一个..目录
add bx,ax
mov si,0;刚来时不能推进项

属性不同_1:
add bx,si;加上下面获取到的下一个项的长度以推进到下一个项

获取项_1:
mov ax,缓存区_1
add ax,[扇区大小]
cmp bx,ax
jb 还可以取项_1

读取下一个扇区_1:
cmp word[循环次数],0
jz 已读完所有扇区_1

mov ebx,缓存区_1
mov eax,[逻辑扇区号]
mov edx,0;逻辑扇区号高位
call 读盘
inc dword[逻辑扇区号]
dec word[循环次数]

还可以取项_1:
movzx si,byte[bx];本项长度
cmp si,0
jz 读取下一个扇区_1;没有项了

mov al,[bx+25]
mov di,iSO9660属性表
call 对比文件属性
jnz 属性不同_1

add si,bx;推进到下一个项以便下次操作
mov [扇区内数据位置],si
mov ecx,[bx+2];逻辑扇区号
mov eax,[bx+10];数据长度
;movzx ax,byte[bx+32];判断结束符
;lea si,[bx+33]
;movzx cx,[bx+0]
;add si,cx
;sub si,34
lea di,[bx+33]
mov bl,[bx+32];文件或文件夹名长度
clc
ret

已读完所有扇区_1:
and byte[标志],1111_1110b;下次则从头开始
stc;设置进位
ret

jmp $























;将会修改EAX，Si，Di寄存器
;输入DS：Si字符串
;输出ES：Di缓存区
;test指令示例test al,0000_0100b;被测试位 =0则ZF =1
_00～_7F:
shl ax,8;移动到AH顺便清空低位，小端存储，因为UTF16的高位为零

写入字符_1:
stosw

UTF8字符串转UTF16字符串:;
lodsb;读取一个UTF8字符
cmp al,0
jz UTF8字符串转UTF16字符串结束

cmp al,'/'
jz UTF8字符串转UTF16字符串结束

test al,1000_0000b
jz _00～_7F

test al,0010_0000b
jz _80～_7FF

test al,0001_0000b
jz _800～_FFFF

test al,0000_1000b
jz _10000～_10FFFF

stc;转换时出现错误
ret

_80～_7FF:
and al,0001_1111b
mov ah,al
lodsb
shl al,2
shr ax,2
jmp 写入字符_1

_800～_FFFF:
and ax,0000_1111b
shl eax,16;移到EAX
lodsw
shl ah,2
shl al,2
shr eax,2
jmp 写入字符_1

_10000～_10FFFF:
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
movzx cx,byte[di-1];对比次数
repne scasb

属性相同:
ret







;将会修改EAX，BX，CX，DL，Si，EDi，BP寄存器
;输入EAX数据长度，EBX逻辑扇区号，ECX读到的位置
;输出
iSO9660读入扇区:
mov edi,ebx
mov edx,0;清空除法高位
movzx ebx,word[扇区大小]
div ebx;edx高：eax低÷ebx=eax…edx
cmp dx,0
jz 不增加一个扇区_2

inc ax;超出一个字节都需要读完整个扇区

不增加一个扇区_2:
mov ebx,ecx
mov cx,ax
mov bp,[扇区大小]

继续读入:
 mov eax,edi;逻辑扇区号
 call 读盘
 inc edi;推进到下一个扇区
 add bx,bp;增加一个扇区大小的偏移
loop 继续读入
ret




;AX，BH，Si寄存器将会被修改
;输入
;DS：Si >字符地址
;输出
;自行查看显示器
打印:
mov bh,0;页码
mov ah,14;功能号
jmp 打印_1

继续打印:;每个指令都很重要确保他们被正确执行
 int 10h;中断号

 打印_1:
 lodsb;将DS：Si指向的内容放入AL然后Si+1
 cmp al,0
 jz 打印完毕

 cmp al,'/'
jnz 继续打印

int 10h;打印一个斜杠

打印完毕:
ret



;将会修改AH，DL，Si寄存器
;输入EAX=LBA低32位，BX段地址
;输出BX：0目标位置

;将会修改AH，DL，Si寄存器
;输入EAX=LBA低32位，EDX=LBA高32位，EBX=高32位段地址+低32位偏移地址
;输出
读盘:
push edx;[12]LBA高32位
push eax;[8]LBA低32位
;word[6]段地址
push ebx;[4]偏移地址
;byte[3]保留，必须为0，注意栈最小压Word
push byte 1;[2]要传输的扇区数0~127
;byte[1]保留，必须为0，CX的高位就是这里的值应当清空CH寄存器，注意栈最小压Word
push byte 16;[0]参数块大小

mov ah,42h;调用号
mov dl,[驱动器号]
mov si,sp;注意栈是反过来的
int 13h;中断号
lea sp,[esp+16];从栈中删除参数块
jc 读盘错误

ret

读盘错误:
mov si,光盘读取错误
jmp 打印并退出
光盘读取错误 db 13,10,'Disc read error',0



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
 sub byte[si-1],32;Si只减1是因为大小端的原因

 不要转换_1:
loop UTF16字符串内的小写字母转成大写

ret



;没有寄存器会被修改
;无输入
;输出
打印斜杠:
mov [u16_1],ax
mov [u8_1],bh
mov al,'/'
mov ah,14;功能号
mov bh,0;页码
int 10h;中断号
mov ax,[u16_1]
mov bh,[u8_1]
ret



驱动器号 db 0
二卷 db 2,'CD001';不一定在第二槽位
Joliet标识 db '%/E',0;或是@或是C或是E
扩展描述 db 'BEA01'
扩展描束 db 'TEA01'
UDFS标识 db 'NSR2',0;或是NSR0或是NSR2
逻辑扇区号 dd 0
循环次数 dw 0
标志 db 0
文件属性号 db 0
扇区大小 dw 0
扇区内数据位置 dw 0
文件系统类型 db 0
根目录逻辑扇区 dd 0
根目录大小 dd 0
BOOT db 'BOOT',0;所有的文件名都是都是大写，0用于显示
LOADER db 'LOADER.BIN',0
换行 db 13,10,0
NONE db 'None ',0
u8_1 db 0
u8_2 db 0
u8_3 db 0
u8_4 db 0
u16_1 dw 0
u16_2 dw 0
u16_3 dw 0
u16_4 dw 0
u32_1 dd 0
u32_2 dd 0
u32_3 dd 0
u32_4 dd 0


times 2046-($-$$) db 0;对于无仿真启动，BiOS最大可加载500KiB
dw 0AA55h;必要，否则会黑屏