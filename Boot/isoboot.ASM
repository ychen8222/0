;=======================================================================
;iso9660文件系统的引导扇区

;2023年3月
;编写完成\
@cya

;26日
;添加检索文件夹\
@cya

;4月12日
;尝试添加iso9660的变体Joliet极有可能会失败\
@cya
;————————————————————————————————————
;内存布局
;7C00～？_isoboot.ASM
;500~？_卷描述符
org 7c00h;基地址

xor Ax,Ax
mov Ds,Ax;数据段DS：BX，SI，DI，BP
mov Ss,Ax;堆栈段SS：SP
mov Ax,50h;2000，用于解析文件系统
mov Es,Ax
mov Sp,7c00h

mov Ds:[驱动器号],dl;来自biso

mov Ax,4b01h;获取光盘仿真状态，与AX=4B00h相同但不终止仿真
;mov dl驱动器号已存在
mov Si,Sp;将其放置于栈
int 13h
jc 错误集群_BIOS;遇到错误cf被设置
cmp byte Ds:[Si+1],0
jnz 错误集群_光盘
mov al,[Si+2],;Ds：Si规格包已填充
cmp Ds:[驱动器号],al;驱动器号应该相同
jnz 错误集群_BIOS;我们被BIOS骗了

mov EAx,16;从16扇区开始检索
mov Bx,Es;读到的位置
下一个卷:
push EAx
call 读盘
pop EAx
inc EAx;准备取下一个卷
mov Si,二卷
xor Di,Di
mov Cx,6h
repe cmpsb
pop cx
;jcxz cd2
;cmp byte Es:[0],0FFh;最后一个卷
;jnz 下一个卷
loop 下一个卷

mov EAx,16;重新读取iso9660的主卷描述符
mov Bx,Es;读到的位置
call 读盘
jmp cd1

cd2:
mov si,Joliet
mov di,58h
mov Cx,3h
rep cmpsb;前缀随便用的
jnz 下一个卷
mov byte [类型],1;下次支持UDF


cd1:;iso9660，Joliet都采用同样的主卷格式
mov Si,Es;显示文件系统
shl Si,4;从段变成偏移
inc Si;卷描述符描述符前面有个byte表示卷描述符我们跳过他
mov Ax,2020h;两个空格
mov Ds:[Si+5],Ax;覆盖掉不知道什么东西以免影响显示
call 打印

mov EAx,Es:[156+2];根目录的目录项+2双端格式的范围位置 (LBA)，2~8÷2
mov ECx,Es:[156+10];根目录的目录项+10双端格式的数据长度（范围大小）
add ECx,2048-1;扇区大小
shr ECx,11;÷2048，要读取的扇区数

mov EBx,文件夹名
mov cr2,EBx;寄存器嘛。。越多越好
mov bP,4;名长度
call 检索;寻找文件夹
jc 错误集群_没有文件夹
mov Si,显示文件夹名
call 打印


mov EAx,Es:[Di+2];2双端格式的范围位置 (LBA)，2~8÷2
mov ECx,Es:[Di+10];双端格式的数据长度（范围大小）
add ECx,2048-1;扇区大小
shr ECx,11;÷2048，要读取的扇区数

mov EBx,文件名
mov cr2,EBx;寄存器嘛。。越多越好
mov bP,11;名长度
call 检索
jc 错误集群_没有文件
mov Si,显示文件名
call 打印


mov EAx,Es:[Di+2];2双端格式的范围位置 (LBA)，2~8÷2
mov ECx,Es:[Di+10];双端格式的数据长度（范围大小）
add ECx,2048-1;扇区大小
shr ECx,11;÷2048，要读取的扇区数

mov Bx,50h;读到的位置
mov bP,2048;扇区大小
shr bP,4;段变偏移
继续读入:
 mov cr3,EAx;寄存器嘛。。越多越好
 call 读盘;只读一个扇区吗
 mov EAx,cr3;恢复
 inc EAx;下一个扇区
 add Bx,bP;添加一个扇区大小的偏移
loop 继续读入

mov al,0ffh;魔数，用于传递这是我们的引导扇区
mov ah,4;第四个文件系统
mov dl,Ds:[驱动器号]
jmp 50h:0



;EAX，BX，DX，SI，DI，BP，CR2，CR3寄存器将会被修改
;输入
;EAX >LBA
;ECX >扇区数
;CR2 >名称长度
;BP >文件名地址
;输出
;无
;错误则设置进位
检索:
 mov cr3,ECx;寄存器嘛。。越多越好
 ;mov EAXLBA号已存在
 mov Bx,Es;读到的位置
 push EAx
 call 读盘;只读一个扇区吗
 xor Di,Di

 call 检索文件名
 pop EAx;注意桟平衡
 jnc 找到并且返回;进位没有被设置说明我们

 inc EAx
 mov ECx,cr3;恢复
loop 检索
stc;设置错误进位
找到并且返回:
ret


检索文件名:
cmp byte [类型],1;是什么类型的文件系统
jz cd2j

cd1下一个项:
     mov Ax,Es:[Di];取这个项的长度
     or Ax,Ax
     jz 触底

     mov Cx,Bp;byte Es:[Di+32];取文件名长度
     mov ESi,cr2;寄存器嘛。。越多越好
     push Di;注意
     add Di,33;指向实际文件名
     repe cmpsb;比较SI，DI重复CX次数
     pop Di
     jcxz 找到文件

     add Di,Ax
     cmp Di,2048
jb cd1下一个项;小于则跳转
触底:
stc
找到文件:;底下的会借用这里的返回
ret


cd2j:;;;;;;;;;;;;;;;;;;;;;这是我不理解的领域
add di,25
;cmp es:[di],0
;jne next_entry

mov Cx,Bp;byte Es:[Di+32];取文件名长度
mov ESi,cr2;寄存器嘛。。越多越好
push di;注意桟平衡
add di,8h
repe cmpsb;比较SI，DI重复CX次数
jcxz 找到文件
pop Di

;next_entry:
add di,7
mov es:[di],ax
add ax,di

b1:
inc di
cmp byte es:[di,0],0
jz b1
stc
ret




;AX，BX，SI寄存器将会被修改
;输入
;DS：SI >字符地址
;输出
;自行查看显示器
继续打印:;每个指令都很重要确保他们被正确执行
 xor Bx,Bx
 mov ah,14;BIOS中断参数
 int 10h;显示字符

 打印:
 lodsb;将DS：SI指向的内容放入al然后SI+1
 or al,al;判断al中的字符值是否 =0
 jnz 继续打印
ret


错误集群_BIOS:
mov Si,BIOSError
jmp short 停止前
BIOSError db 10,13,'BIOS error',0;0是结束符

错误集群_光盘:
mov Si,仿真模式
jmp short 停止前
仿真模式 db 10,13,'Disc is in an emulation mode',0

错误集群_读盘:
mov Si,读取错误
jmp short 停止前
读取错误 db 10,13,'Disc read error',0

错误集群_没有文件夹:
mov Si,换行没有
call 打印
mov Si,显示文件夹名
jmp short 停止前

错误集群_没有文件:
mov Si,没有
call 打印
mov Si,文件名

停止前:
call 打印

停止:
cli
hlt
jmp short 停止


;EAX，DX，Si寄存器将会被修改
;输入
;EAX >LBA低32位
;BX >段地址
;输出
;BX：0 >目标位置
读盘:
push DworD 0;[12]lba高32位
push EAx;[8]lba低32位
push Bx;[6]段地址
push Word 0;[4]偏移地址
;byte[3]保留，必须为0，注意堆栈只能压word
push byte 1;[2]要传输的块数0~127
;byte[1]保留，必须为0，cx的高位就是这里的值应当清空ch寄存器，堆栈只能压word
push byte 16;[0]参数块大小

mov ah,42h;扩展调用
mov dl,Ds:[驱动器号]
mov Si,Sp;注意堆栈是反过来的
int 13h
add Sp,16;从堆栈中删除参数块
jc 错误集群_读盘;如果读取失败则中止
ret
驱动器号 db 0



二卷 db 2h,'CD001';看似第二张卷但不一定在第二槽位
Joliet db 25h,2fh,45h
类型 db 0
显示文件夹名 db 10,13
文件夹名 db 'BOOT',0;0是结束符

显示文件名 db '\'
文件名 db 'LOADER.BIN',0;所有的文件名都是都是大写

没有 db '\none ',0
换行没有 db 10,13,'nono',0

;times 2048-($-$$) db 0;BIOS似乎不止加载一个扇区2048，到底加载了几个呢
;dw 0aa55h