;============================================================================
;iso文件系统的引导扇区

;2023年3月
;编写完成\
@cya

;26日
;添加检索文件夹\
@cya

;6月22日
;支持iso9660的变体Joliet
;@cya

;4月12日
;尝试支持UDFS以失败告终\
@cya
;----------------------------------------------------------------------------
;内存布局
;7C00～？_isoboot.BIN
;500~？_卷描述符
org 7c00h;基地址
jmp 初始化寄存器;BPB？
nop
rootLBA dd 0
根大小 dd 0

初始化寄存器:
mov ax,0
mov Ds,Ax;数据段DS：BX，SI，DI，BP
mov Ss,Ax;堆栈段SS：SP
mov Ax,50h;500，用于解析文件系统，不能使用7e00，因为我们的引导扇区是未知长度
mov Es,Ax
mov Sp,7c00h

mov Ds:[驱动器号],dl;来自BISO
mov Ax,4b01h;获取光盘仿真状态，与AX=4B00h相同但不终止仿真
;mov dl驱动器号已存在
mov Si,Sp;将其放置于栈
int 13h
jc 错误集群_BIOS;遇到错误cf被设置
cmp byte Ds:[Si+1],0;模拟软盘
jnz 错误集群_光盘
mov al,[Si+2],;Ds：Si规格包已填充
cmp Ds:[驱动器号],al;驱动器号应该相同
jnz 错误集群_BIOS;我们被BIOS骗了



mov EAx,16;从16扇区开始检索
mov Bx,Es;读到的位置
mov bp,0FFh;循环次数

下一个卷:
 push EAx
 call 读盘
 pop EAx
 inc EAx;准备取下一个卷

 mov si,二卷
 mov di,0
 mov cx,6
 repe cmpsb
 jnz 不会是Joliet
 mov Si,Joliet
 mov Di,58h;偏移，不知道为什么要放在这里
 mov Cx,3
 repe cmpsb
 jz 是Joliet

 不会是Joliet:
 dec bp;不能被jz指令跳过
 cmp byte Es:[0],0FFh;最后一个卷
 jz 看看扩展卷

 cmp bp,0
jnz 下一个卷
jmp iSO9660;終了


看看扩展卷:
push EAx
call 读盘
pop EAx
inc EAx;准备取下一个卷

mov Si,扩展描述符
mov Di,1;没有序号
mov Cx,5
repe cmpsb
jnz iSO9660;没有扩展卷
扩展卷循环:
 push EAx
 call 读盘
 pop EAx
 inc EAx;准备取下一个卷

 mov Si,扩展描述符结束
 mov Di,1;没有序号
 mov Cx,5
 repe cmpsb
 jz iSO9660;終了

 mov Si,UDFS
 xor Di,Di
 mov Cx,4
 repe cmpsb
 jz 是UDFS

dec bp
jnz 扩展卷循环



iSO9660:
mov byte [类型],1;下次支持UDF

mov EAx,16;再读主卷符
mov Bx,Es;读到的位置
call 读盘
mov Si,500h+1;显示文件系统，卷描述符描述符前面有个byte表示卷号
mov Ax,2020h;两个空格
mov Ds:[Si+5],Ax;覆盖掉不知道什么东西以免影响显示
call 打印

mov EAx,Es:[156+2];根目录的目录项+2双端格式的范围位置 (LBA)，2~8÷2
mov ECx,Es:[156+10];根目录的目录项+10双端格式的数据长度（范围大小）
mov [rootLBA],eax;Loader需要的参数
mov [根大小],ecx
add ECx,2048-1;扇区大小
shr ECx,11;÷2048，要读取的扇区数

mov si,文件夹名
mov bP,4;名长度
call iSO9660_检索
jc 尝试另一种方式
mov Si,显示文件夹名
call 打印
jmp 找到文件夹


尝试另一种方式:
mov eax,[rootLBA];正好用一下
mov ecx,[根大小]
mov si,文件夹名_1
mov bP,4;名长度
call iSO9660_检索;寻找文件夹
jc 错误集群_没有文件夹
mov Si,显示文件夹名_1
call 打印


找到文件夹:;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
mov EAx,Es:[Di+2];2双端格式的范围位置 (LBA)，2~8÷2
mov ECx,Es:[Di+10];双端格式的数据长度（范围大小）
add ECx,2048-1;扇区大小
shr ECx,11;÷2048，要读取的扇区数
push eax
push ecx

mov si,文件名
mov bP,10;名长度
call iSO9660_检索
jc 尝试另一种方式_1
add sp,8;栈平
mov Si,显示文件名
call 打印
jmp 找到文件_1

尝试另一种方式_1:
pop eax
pop eax
mov si,文件名_1
mov bP,11;名长度
call iSO9660_检索
jc 错误集群_没有文件
mov Si,显示文件名_1
call 打印

找到文件_1:
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


mov bP,0aa55h;魔数，用于传递这是我们的引导扇区
mov dh,[类型]
mov dl,[驱动器号]
jmp 50h:0


;EAX，BX，DX，SI，DI，BP，CR2，CR3寄存器将会被修改
;输入
;EAX >LBA
;ECX >扇区数
;SI >文件名地址
;BP >名称长度
;输出
;无
;错误则设置进位
iSO9660_检索:
mov Bx,Es;读到的位置
iSO9660_检索_e:
 push ecx;不重复任何多余的指令
 push eax
 push si
 call 读盘
 pop si
 pop eax
 inc EAx

 mov di,es:[0];跳过一个.目录
 add di,es:[di];跳过一个..目录

    iSO9660_继续此扇区:
     mov dx,Es:[Di];取这个项的长度
     cmp dx,0
     jz 触底

     movzx cx,byte Es:[Di+32];取文件名长度，刚好满足repe指令
     cmp cx,bp
     jnz 不用对比
     push si
     push Di;注意
     add Di,33;指向实际文件名
     repe cmpsb;比较SI，DI重复CX次数
     pop Di
     pop si;续
     jz 找到

     不用对比:
     add di,dx
     cmp di,2048
    jb iSO9660_继续此扇区;小于则跳转

pop ecx
loop iSO9660_检索_e

触底:
stc;设置错误进位
找到:
pop ECx;栈平
ret



是Joliet:;跟iSO9660几乎一样，不知道存在的目的是什么
mov byte [类型],2;下次支持UDF
mov si,Joliet
call 打印

mov EAx,Es:[156+2];根目录的目录项+2双端格式的范围位置 (LBA)，2~8÷2
mov ECx,Es:[156+10];根目录的目录项+10双端格式的数据长度（范围大小）
mov [rootLBA],eax;Loader需要的参数
mov [根大小],ecx
add ECx,2048-1;扇区大小
shr ECx,11;÷2048，要读取的扇区数
mov si,文件夹名_2;;;;;;;;;;;;;;;;;;;;;;
mov bP,8;名长度
call iSO9660_检索
jc 错误集群_没有文件夹
mov Si,显示文件夹名
call 打印

mov EAx,Es:[Di+2];2双端格式的范围位置 (LBA)，2~8÷2
mov ECx,Es:[Di+10];双端格式的数据长度（范围大小）
add ECx,2048-1;扇区大小
shr ECx,11;÷2048，要读取的扇区数
mov si,文件名_2;;;;;;;;;;;;;;;;;;;;;;;;;;
mov bP,20;名长度
call iSO9660_检索
jc 错误集群_没有文件
mov Si,显示文件名
call 打印
JMP 找到文件_1;通用于iSO9660








是UDFS:
mov byte [类型],3
mov si,UDFS
call 打印
jmp $

mov eax,256;锚卷描述符指针
mov bx,es
call 读盘
mov EAx,Es:[16];止步于此
mov ECx,Es:[16+4];我不知道任何的结构入大小端或LBA，偏移等
add ECx,2048-1;应该是这样
shr ECx,11












cd2j:;;;;;;;;;;;;;;;;;;;;;这是我不理解的领域
add di,25
;cmp es:[di],0
;jne next_entry

mov Cx,Bp;byte Es:[Di+32];取文件名长度
mov ESi,cr2;寄存器嘛。。越多越好
push di;注意桟平衡
add di,8h
repe cmpsb;比较SI，DI重复CX次数
jz 找到
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
mov Si,文件夹名
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


;EAX，BX，DX，Si寄存器将会被修改
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



二卷 db 2,'CD001';看似第二张卷但不一定在第二槽位
Joliet db '%/E',0;或@或C或E
扩展描述符 db 'BEA01'
扩展描述符结束 db 'TEA01'
UDFS db 'NSR2',0;或NSR0或NSR2
类型 db 0

显示文件夹名 db 10,13,'/'
文件夹名 db 'Boot',0
显示文件夹名_1 db 10,13,'/'
文件夹名_1 db 'BOOT',0;0是结束符

显示文件名 db '/'
文件名 db 'Loader.BIN',0
显示文件名_1 db '/'
文件名_1 db 'LOADER.BIN',0;所有的文件名都是都是大写

文件夹名_2 db 0,'B',0,'o',0,'o',0,'t'
文件名_2 db 0,'L',0,'o',0,'a',0,'d',0,'e',0,'r',0,'.',0,'B',0,'I',0,'N'

没有 db '/none ',0
换行没有 db 10,13,'none ',0

times 2048-($-$$) db 0;BIOS似乎不止加载一个扇区2048，到底加载了几个呢
dw 0aa55h