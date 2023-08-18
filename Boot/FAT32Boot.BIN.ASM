;============================================================================
;FAT32文件系统的引导扇区
;MBR分区表最大支持2T大小的空间，FAT32最大也只支持2T大小，所以只使用LAB的低32位就行了

;2019年11月
;编写完成\
@cya

;26日
;修复计算下一个簇时错误，修改传递的参数\
@cya

;2023年1月
;修正读入更多文件扇区时错位\
@cya

;8月2日
;优化了运行速度，显示文件项的名字\
@cya
;----------------------------------------------------------------------------
;内存布局
缓存FAT表 equ 2000h;～2200
;7c00～7e00_FAT32Boot.BIN
文件读入的位置 equ 1000h;～？

org 7c00h;历史遗留的起始位置
;BPB表不用修改，他只是用来占位而已
;12~?字节为BPB部分？
jmp short 初始化寄存器;略过下面的干扰去执行引导程序,3个字节
nop;别漏了这个
取个你喜欢的名字 db 'lunzi os';8个字节
扇区大小 dw 512;默认512，2个字节 
每个簇占用的扇区数 db 0;默认8，8h×512b=4k，1个字节
保留扇区数 dw 32;2个字节
FAT表总数 db 2;默认2，1个字节
根目录可容纳目录数 dw 0;历史字段，FAT32不适用，2个字节
分区总扇区数 dw 0;小于32m，在这记录，大于32m，改totalsectors，2个字节
设备类型 db 0f8h;0xf8表示硬盘，1个字节
FAT表大小扇区数 dw 0;硬盘FAT32已经不使用了，2个字节
磁道扇区数 dw 0;每个磁道扇区数 s   >不同硬盘改动，一般为“3fh   00h”，2个字节
磁头数 dw 0;磁头数 h   >修改，一般为“ffh   00h”，即每个柱面有255个磁头，2个字节
FAT区前隐藏扇区数 dd 0;分区目前已使用 隐藏扇区数，4个字节
扇区总数 dd 73584;大于32m这里修改扇区数，对于大硬盘来说该处存放的是该分区占用的扇区数，4个字节
每个FAT表使用扇区数 dd 566;每个FAT表使用扇区数 ，4个字节
FAT表同步标识 dw 0;标记，2个字节;;最左端二进制位为零则所有FAT表是同步的，为1则有损坏的FAT表。低4位表示在用的FAT表编号，从零开始计
版本号 dw 0;文件系统格式版本号，2个字节
根目录起始簇号 dd 2;根目录簇号 4个字节 起始于数据区的 + 2个簇，4个字节
文件系统信息 dw 1;存放文件系统格式信息的扇区号，2个字节
引导备份 dw 6;备份引导扇区 位于文件系统的6号扇区，2个字节

未使用12字节 dd 0;预留未使用，你不用是吗 我用，，嗯。刚好够
FAT表起始 dd 0
数据区起始 dd 0

驱动器号 db 80;硬盘为“80h”，一般软盘为“00h
未使用1字节 db 0;预留，1个字节
扩展引导标记 db 41;扩展引导标记，1个字节
磁盘序列号 dd 0;4个字节
磁盘标签 db 'NO NAME    ';windows显示硬盘的名字，如果没有卷标此处通常为字符串no   name，11个字节
文件系统 db 'FAT32   ';，文件系统标识，对于FAT32文件系统此处常为FAT32，8个字节


初始化寄存器:;添加更多寄存器组合方式的注释
xor bp,bp
mov ds,bp;数据段DS：BX，Si，Di
;mov ss,bp;堆栈段SS：SP，BP
mov ax,文件读入的位置;第2段
mov es,ax;附加段ES：Di
;mov sp,7c00h;临时栈
;mov bp,sp;栈游标SS：BP

mov byte ds:[驱动器号],dl;先保存驱动器号

mov word ds:[文件系统+5],0ah
mov si,文件系统
call 显示


;首先计算FAT表起始
;乘法
;al×bl =ax，被乘数×被乘数 =积
;eax×ebx =edx高：低eax
xor eax,eax
mov dword ds:[未使用12字节],eax;清空用于对比的LBA号

mov ax,word ds:[保留扇区数];没有movzx eax，字...需要
add eax,dword ds:[FAT区前隐藏扇区数]
mov dword ds:[FAT表起始],eax;第一个FAT表扇区
mov dword ds:[数据区起始],eax;数据区起始，仅值的第一部分

;然后计算数据区起始
mov eax,dword ds:[FAT表总数];不需要 movzx ...字节，bsFATs db 之后的 2 dw 根据 FAT32 定义为 0 :-)
mul dword ds:[每个FAT表使用扇区数]
add dword ds:[数据区起始],eax;第一个数据扇区，全部值


;在根目录中检索文件
mov eax,dword ds:[根目录起始簇号]
cld;清空df并向前推进
;xor bp,bp
movzx cx,byte ds:[每个簇占用的扇区数]
算簇大小 add bp,word ds:[扇区大小]
loop 算簇大小

下一个簇:
 push eax;保存目前的簇号
 call 簇转LBA;簇号转换为绝对扇区号，返回值中Si是每个簇的扇区数，EAX是扇区号 
 jc 簇找完了;簇转LBA时发现簇查完了
 mov bx,es;读取到的段地址，使用ES的值以便配合Di
 call 读盘
 xor di,di;ES:Di，文件名目标地址
 mov ah,14;int 10的功能号
 xor bh,bh;页码

    下一个目录项:;在这里循环的寻找目标文件
     cmp byte es:[di],0e5h;固定值
     jz 直接下一个项;本项已被删除
     cmp byte es:[di+11],20h;固定值
     jnz 直接下一个项;不是短目录项
     mov al,13;回车符，用于重置光标
     mov cx,12;显示长度11+一个回车符
     mov dx,di;save

        显示文件名 int 10h
         mov al,byte es:[di]
         inc di;推
        loop 显示文件名;续

     mov si,要搜索的文件名;文件名源地址
     mov cx,11;文件名长度，也是比较的次数，正确一个就减1
     mov di,dx;revert
     repe cmpsb;比较Si，Di，重复CX次数
     mov di,dx;恢复推动过的Di
     jz 找到了文件

     直接下一个项:
     ;and di,0FFe0h;（1111 1111 1110 0000）用于使Di对齐
     add di,32;20h，DI指向下一个文件条目的32字节结构体开头处
     cmp di,bp;这个扇区查完了吗？
    jnz 下一个目录项;小于则跳转

 pop eax;推进到下一个簇号
 call 计算下一个簇号
jmp short 下一个簇


找到了文件:
push word es:[di+20];获取簇号高位
push word es:[di+26];获取簇号低位
pop eax;合成为32位
shr bp,4;÷16，将整个簇占用的大小转成段地址

读入文件:
 mov ecx,eax;save，簇号
 call 簇转LBA;Si是簇中的扇区，EAX是扇区
 jc 读入完成
 mov bx,es;读入第2个段
 call 读盘
 add bx,bp;加
 mov es,bx
 mov eax,ecx
 call 计算下一个簇号
jmp short 读入文件

读入完成:
mov si,换行
call 显示
mov bp,0AA55h;判断数，用于表示我们的引导扇区
mov dh,2;文件系统编号
jmp 文件读入的位置:0;我的同行抖机灵只读一个簇就跳转过去了，让他解析表项自己读完自己，这样好吗？这样不好



簇找完了:
mov si,回车
mov dx,没有文件
call 更多显示
int 18h;返回BiOS



;将会修改EAX，EDX，Si寄存器
;输入
;EAX >目标簇号
;输出
;EAX >LBA号
;Si =每个簇占用的扇区数
;如果链表末端则设置进位EAX，EDX，Si不变，链表结束
;乘法
;al×bl =ax，被乘数×被乘数 =积
;EAX×EDX =EDX高：低EAX
;算法
;（簇号-2）×每个簇占用的扇区数+数据区起始扇区号=簇的LBA号
簇转LBA:
cmp eax,0FFFFFF8h;如果链表结束
stc;通过进位表示已结束，预判失败也无妨
jae 链表末端;等于大于则跳转，这是簇链的结束标志
dec eax;簇号-2×每个簇占用的扇区数+数据区起始扇区号=簇的LBA号
dec eax

movzx edx,byte ds:[每个簇占用的扇区数];使用扩位传送覆盖DX的高位以进行32位乘法
mov si,dx;用于返回读入的扇区数
mul edx;edx是乘法的高位但我们不允许eax溢出到高位

add eax,dword ds:[数据区起始];+数据区起始扇区号
链表末端 ret;此时进位未设置，除非参数错误



;给定一个簇号，找出下一个簇号
;簇号÷（扇区大小×4）=商×4 =扇区号…余数，簇表内偏移
;输入
;EAX >簇号
;输出
;EAX >下一个簇号
;除法
;AX÷bl =al…ah，被除数÷除数 =商…余数
;EDX高：EAX低÷EBX =EAX……EDX
计算下一个簇号:
movzx ebx,word ds:[扇区大小]
shr bx,2;扇区512字节除以四便是每个扇区可保存的目录数
xor edx,edx;清空高位
div ebx;EAX >扇区号，DX >目录内偏移
shl dx,2
mov di,dx;save，Si会被读盘修改

add eax,dword ds:[FAT表起始];你得到了LBA号
cmp eax,dword ds:[未使用12字节];在同一张FAT表内？
mov bx,缓存FAT表/16;段地址，读到的位置，注意即使不用读盘也要设置BX为缓存区来取上次的值
jz 读取簇号;上次读过这张FAT表
mov dword ds:[未使用12字节],eax;使用LBA号进行标记
mov si,1;读取的扇区数
call 读盘;只需要读一个扇区的FAT表即可

读取簇号:
shl bx,4;×16，变回偏移，基地址
;+Di=加FAT表内偏移
and byte ds:[bx+di+3],0Fh;屏蔽前4位，FAT32其实只有28位簇号
mov eax,dword ds:[bx+di];读取我们需要的簇号
ret



;将会修改AX，BX，Si寄存器
;显示字符
;输入
;DS：SI >字符地址
;输出
;自行查看显示器
更多显示:
call 显示
mov si,dx;现在可以显示原来的字符了

lodsb
继续显示:;每个指令都很重要确保他们被正确执行
 xor bh,bh;页码
 mov ah,14;BIOS中断参数：中断模式
 int 10h

 显示:
 lodsb;将ds：si指向的内容放入al然后si+1
 or al,al;判断al中的字符值是否 =0
jnz 继续显示
ret



;将会修改EAX，DX，Si寄存器
;从硬盘读取一个扇区数据
;输入
;EAX >LBA 低32位
;BX >段地址
;DX =读入的扇区数
;输出
读盘:
push ds;[12]LBA高32位
push ds;目的是压入dword大小的0，压两次空的段寄存器也比直push dword 0要节省空间
push eax;[8]LBA低32位，只使用了LBA的低32位，最大支持2T的磁盘空间
push bx;[6]段地址
push ds;push 0;[4]偏移地址，这只是压个固定为0的寄存器，比压word 0节省空间
;byte[3]保留，必须为0，注意堆栈最小压word，上面压的已溢出至这
push si;byte 1;[2]要传输的块数0~127
;byte[1]保留，必须为0，DX的高位就是这里的值应当清空DH寄存器，注意堆栈最小压word
push byte 16;[0]参数块大小，高位为0正好用于保留处

mov si,sp;注意堆栈是反过来的
mov dl,byte ds:[驱动器号]
mov ah,42h;扩展调用
int 13h
jc 读盘错误;如果读取失败则中止

add sp,16;从堆栈中删除参数块
ret

读盘错误:
mov si,换行
mov dx,读盘错误_1
call 更多显示

停:
 ;cli;会导致某些虚拟机报错
 hlt
jmp short 停



读盘错误_1 db 'Disk Erro',0
没有文件 db 'None ';没有找到loader，0是判断数
要搜索的文件名 db 'LOADER  BIN',0;在FAT文件系统 里所有保存的文件名都是大写空格是后缀名的点，11字节
换行 db 10
回车 db 13,0

times 510-($-$$) db 0
dw 0xAA55
;注意\
我们不能在引导扇区耽误太多时间