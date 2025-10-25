;============================================================================
;iSO文件的引导扇区\
@ychen

;2023年3月
;编写完成，能够从iSO9660加载文件
;@cya

;26日
;添加检索文件夹\
@cya

;6月22日
;支持iSO9660的变体Joliet\
@cya

;2024年1月
;修复BUG，不传入LBA的高64位
;VMware会忽略传入LBA的高64位
;Oracle VM VirtualBox会显示FATAL: int13_cdrom: function 42. Can't use 64bits lba

;新增识别UDF文件系统的功能
;El Torito格式规范的部分信息https://www.cnblogs.com/hustdc/p/7051133.html
;将iSO作为十六进制文件打开，然后搜索AA5555AA在这个数值的开头处加上偏移36后值是0x91EF还有在AA5555AA这个数值开头加上偏移68后值是0x88就会导致UltraISO打开iSO时产生除法错误，但Windows资源管理器不受影响，把这两个值破坏以后UltraISO就能正常打开此iSO文件了
;@cya。2025|4|30
;----------------------------------------------------------------------------

;内存布局
缓存区_1 equ 500h
缓冲区1 equ 500h
缓存区_2 equ 2000h
缓存区_3 equ 10000h

org 7c00h;～8c00;iSO.Bin
mov ax,0
mov ds,ax
jmp 跳过引导扇区内缺失的部分;当你在UltraISO把一个超大的文件错误的设置成了引导文件然后即使将正确的文件设为引导文件也会产生BUG，表现为BiOS会漏加载开头的一小节区域，幸好BiOS会加载开头的一点点部分使我能够使用跳转代码，否则极有可能会一开机就遇到未定义操作码错误

times 40h - ($ - $$) db 0;填充以跳过BiOS漏加载的这一小节

跳过引导扇区内缺失的部分:;判断引导扇区结束符以检查完整性
cmp word[引导扇区结束符],0AA55h;如果你在UltraISO把一个超大的文件错误的设置成了引导文件然后即使将正确的文件设为引导文件也会产生BUG，表现为BiOS只加载一个2048大小的扇区，致使引导代码有缺失因此首先我需要检查一下完整性
jz 完整的引导扇区

mov si,字符串_引导扇区不完整
jmp 打印并退出


字符串_引导扇区不完整 db 13,10,'incomplete boot sector',0



完整的引导扇区:
mov sp,7c00h;清空高位
mov es,ax
mov ax,4b01h;获取光盘仿真状态，与AX=4b00h相同但不终止仿真
mov si,缓存区_1
mov [驱动器号],dl
int 13h
jc 获取光盘参数时异常;CF被设置

cmp byte[si + 1],0;=无仿真，1=仿真1.2M软盘，2=仿真1.44M软盘，3=仿真2.88M软盘，4=仿真硬盘
jnz 光盘处于仿真模式

mov dl,[si+2];DS：Si规格包已填充
cmp [驱动器号],dl;驱动器号应该相同
jnz 驱动器号不同



;https://www.cnwrecovery.com/manual/HowToRecogniseTypeOfCDDVD.html
;https://forum.osdev.org/viewtopic.php?t=23554
;https://wiki.osdev.org/UDF
;判断文件系统类型:
;push bp;创建栈帧
mov bp,sp
sub sp,判断文件系统类型的函数栈帧大小
mov ax,16;必须从第16扇区开始读
mov si,0
mov [bp - 数据区起始的卷描述符读取扇区号递增低16位],ax
mov [bp - 数据区起始的卷描述符读取扇区号递增高16位],si
mov cx,0FFh;扇区最大读取数，顺便清空标志
mov [bp - 数据区起始的卷描述符读取扇区数递减],cl
mov bx,缓存区_1
mov dh,1

数据区起始的卷描述符读取扇区数递减 equ 1
数据区起始的卷描述符读取扇区号递增高16位 equ 数据区起始的卷描述符读取扇区数递减 + 2
数据区起始的卷描述符读取扇区号递增低16位 equ 数据区起始的卷描述符读取扇区号递增高16位 + 2
判断文件系统类型的函数栈帧大小 equ 数据区起始的卷描述符读取扇区号递增低16位 + 0

下一个卷:
 call LBA48读扇区
 mov si,二卷
 mov di,缓存区_1
 mov cl,6
 repe cmpsb
 jnz 不是Joliet

 mov si,Joliet标识
 mov di,缓存区_1+58h;偏移，不知道为什么要放在这里
 mov cl,3
 repe cmpsb
 jz Joliet文件系统

 不是Joliet:
 add word[bp - 数据区起始的卷描述符读取扇区号递增低16位],1;准备读取下一个卷，一个扇区为一个卷
 adc word[bp - 数据区起始的卷描述符读取扇区号递增高16位],0
 mov ax,[bp - 数据区起始的卷描述符读取扇区号递增低16位]
 mov si,[bp - 数据区起始的卷描述符读取扇区号递增高16位]
 cmp byte[缓存区_1],0FFh;卷计数结束，这是一个依次递增的序号，当结束时即使没到最后也会被设为最后一个扇区的序号
 jz 尝试扩展卷

 dec byte[bp - 数据区起始的卷描述符读取扇区数递减]
jnz 下一个卷

jmp iSO9660文件系统;終了


;https://www.rodneybeede.com/programming/understanding_the_udf_file_system_specification.html
尝试扩展卷:
dec byte[bp - 数据区起始的卷描述符读取扇区数递减];从上面下来的但没有减去一个扇区，因此在这里补上减去
call LBA48读扇区
cmp dword[缓存区_1 + 1],'BEA0'
jnz iSO9660文件系统;没有扩展卷就直接跳走

cmp byte[缓存区_1 + 1 + 4],'1';这个字符串的长度是五字节
jnz iSO9660文件系统;没有扩展卷就直接跳走

下一个扩展卷:
 add word[bp - 数据区起始的卷描述符读取扇区号递增低16位],1;准备读取下一个卷，一个扇区为一个卷
 adc word[bp - 数据区起始的卷描述符读取扇区号递增高16位],0
 mov ax,[bp - 数据区起始的卷描述符读取扇区号递增低16位]
 mov si,[bp - 数据区起始的卷描述符读取扇区号递增高16位]
 call LBA48读扇区
 cmp dword[缓存区_1 + 1],'TEA0';结束标识
 jnz 扩展卷未结束

 cmp byte[缓存区_1 + 1 + 4],'1'
 jz iSO9660文件系统;終了

 扩展卷未结束:
 cmp dword[缓存区_1 + 1],'NSR0';Volume Recognition Sequence，从扇区 32 开始，包含 NSR03 描述符（UDF 2.60 使用 NSR03）
 jnz 不是UDF文件系统

 mov al,[缓存区_1 + 1 + 4]
 cmp al,'0'
 jz UDF文件系统

 cmp al,'2'
 jz UDF文件系统

 cmp al,'3'
 jz UDF文件系统

 不是UDF文件系统:
 dec byte[bp - 数据区起始的卷描述符读取扇区数递减]
jnz 下一个扩展卷

;https://kikakurui.com/x0/X0606-1998-01.html
iSO9660文件系统:
add sp,判断文件系统类型的函数栈帧大小;移除栈帧
mov byte[文件系统类型],1;标记为iSO9660文件系统
mov eax,16;再次读取iSO9660主卷描述符
;mov bx,缓存区_1
call 读扇区
mov si,缓存区_1+1;+1跳过卷描述符前面表示卷号的Byte
mov ax,2020h;2个空格
mov [si+5],ax;覆盖掉不知道什么东西以免影响显示
call 打印
mov si,消息_回车加换行
call 打印
mov ax,[缓存区_1+128]
mov [实际扇区大小],ax
mov cx,16
jmp $
扇区大小计算位移次数:
 shr ax,1
 jc 扇区大小位移计算结束

loop 扇区大小计算位移次数

扇区大小位移计算结束:
mov ch,16
sub ch,cl;最大次数减去剩余次数等于已使用次数
mov [数据长度转扇区数量的位移次数],ch
mov ax,[缓存区_1 + 156 + 2];根目录的目录项+2双端格式的范围位置 (LBA)，2~8÷2
mov si,[缓存区_1 + 156 + 2 + 2]
mov dx,[缓存区_1 + 156 + 10];根目录的目录项+10双端格式的数据长度（范围大小）
mov di,[缓存区_1 + 156 + 10 + 2]
mov [根目录逻辑扇区],ax;备份Loader需要的参数
mov [根目录逻辑扇区 + 2],si
mov [根目录大小],dx;RootSize
mov [根目录大小 + 2],di
;mov ecx,[根目录逻辑扇区]
;mov eax,[根目录大小]
mov bx,LOADER
mov cl,10;文件名长度
mov ch,0;获取的类型为文件
call iSO9660的检索文件或文件夹
jc 没有找到LOADER文件

mov bx,1000h
mov es,bx
mov bx,0
call iSO9660读入扇区
mov eax,[根目录大小]
mov bx,[实际扇区大小]
mov ecx,[根目录逻辑扇区]
mov dl,[驱动器号]
mov dh,[文件系统类型]
mov bp,0AA55h;我们的标识
jmp 1000h:0



Joliet文件系统:
add sp,判断文件系统类型的函数栈帧大小;移除栈帧
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
mov si,消息_换行
call 打印
mov ax,[缓存区_1+128]
mov [实际扇区大小],ax
mov ecx,[缓存区_1+156+2];根目录的目录项+2双端格式的范围位置 (LBA)，2~8÷2
mov eax,[缓存区_1+156+10];根目录的目录项+10双端格式的数据长度（范围大小）
mov [根目录逻辑扇区],ebx;备份Loader需要的参数
mov [根目录大小],eax;RootSize
mov si,LOADER
mov bl,0;需要文件
call Joliet的检索文件或文件夹
jc 没有找到LOADER文件

mov bx,1000h
mov es,bx
mov bx,0
mov ecx,缓存区_1
call iSO9660读入扇区
mov eax,[根目录大小]
mov bx,[实际扇区大小]
mov ecx,[根目录逻辑扇区]
mov dl,[驱动器号]
mov dh,[文件系统类型]
mov bp,0AA55h;我们的标识
jmp 0:缓存区_1



;https://ecma-international.org/publications-and-standards/technical-reports/ecma-tr-112/
;https://www.yumpu.com/en/document/view/26257693/udf-200-osta-optical-storage-technology-association
;https://kikakurui.com/x0/X0611-2018-01.html
;Universal Disk Format，Universal Disc Format通用光盘格式
UDF文件系统:;UDFS
push bp;创建栈帧
mov bp,sp
sub sp,获取UDF基本参数的函数栈帧大小 - 判断文件系统类型的函数栈帧大小
mov byte[文件系统类型],4;标记为UDFS
mov byte[bx + 1 + 5],0;字符串结束符
lea si,[bx + 1];指向文件系统的名称
call 打印
mov si,消息_回车加换行
call 打印
;Anchor Volume Descriptor Pointer 锚点卷描述符指针
;AnchorVolumeDescriptor锚点卷描述符固定位于位于第256扇区 ，备份副本位于N-1 或 N（N 为介质最后一个扇区）
;AVDP是UDF文件系统的第一个卷描述符，他指向主卷描述符序列MainVolumeDescriptorSequence的起始扇区
mov ax,256;AVDP是固定的
mov si,0
mov bx,缓存区_1
mov dh,1;要读取的扇区数量
call LBA48读扇区
cmp word[缓存区_1],2;AVDP的标签
jnz 没有读取到锚点卷描述符;不是锚卷描述符

;Volume Descriptor Sequence，MainVolumeDescriptorSequence主卷描述符序列
;现在开始读取MVDS主卷描述符序列包含逻辑卷描述符分区描述符等
mov ax,[缓存区_1 + 16];MVDS的长度低16位
mov dx,[缓存区_1 + 16 + 2];MVDS的长度高16位
mov di,[缓存区_1 + 16 + 4];MVDS的起始扇区号低16位
mov si,[缓存区_1 + 16 + 4 + 2];MVDS的起始扇区号高16位
test ax,扇区大小 - 1;只要跨越了扇区哪怕只有一比特也要读完整个扇区
jz 不需要多加一个MVDS扇区

add ax,扇区大小 - 1
adc dx,0;把加法进位CF加到DX，如果有的话

不需要多加一个MVDS扇区:
mov cx,11;相当于除以2048等于MVDS的扇区数量

位移计算MVDS的扇区数量:
 shr dx,1;右移一次，最低位移入CF
 rcr ax,1;右移一次，CF移入最高位
loop 位移计算MVDS的扇区数量

mov cx,ax;MVDS的扇区数量
mov ax,di
mov di,0FFFFh;可以使用FFFF作为判断值，因为分区不可能位于最后一个扇区，因为分区内还要存储数据
mov [bp - 分区起始扇区号低16位],di;作为写入参数后的判断值，如果不为此值则代表参数存在
mov [bp - 分区起始扇区号高16位],di
mov [bp - 文件集描述符所在分区起始扇区号低16位],di
mov [bp - 文件集描述符所在分区起始扇区号高16位],di
mov [bp - 主卷描述符序列内扇区读取递进号低16位],ax
mov [bp - 主卷描述符序列内扇区读取递进号高16位],si
mov dh,1;要读取的扇区数量

主卷描述符序列内扇区读取递进号高16位 equ + 2
主卷描述符序列内扇区读取递进号低16位 equ 主卷描述符序列内扇区读取递进号高16位 + 2
主卷描述符序列扇区数 equ 主卷描述符序列内扇区读取递进号低16位 + 2
文件集描述符所在分区号 equ 主卷描述符序列扇区数 + 2
文件集描述符所在分区起始扇区号高16位 equ 文件集描述符所在分区号 + 2
文件集描述符所在分区起始扇区号低16位 equ 文件集描述符所在分区起始扇区号高16位 + 2
分区扇区数高16位  equ 文件集描述符所在分区起始扇区号低16位 + 2
分区扇区数低16位 equ 分区扇区数高16位 + 2
分区起始扇区号高16位 equ 分区扇区数低16位 + 2
分区起始扇区号低16位 equ 分区起始扇区号高16位 + 2
分区属性高16位 equ 分区起始扇区号低16位 + 2
分区属性低16位 equ 分区属性高16位 + 2
分区编号 equ 分区属性低16位 + 2
获取UDF基本参数的函数栈帧大小 equ 分区编号 + 0

遍历MVDS:;主卷描述符序列是一段区域，里面有多个描述符，每个描述符占一个扇区大小
 call LBA48读扇区
 mov ax,[缓存区_1]
 cmp ax,8;终止卷描述符的标签
 jz 在MVDS里没有找到所需的描述符

 cmp ax,5;PartitionDescriptor分区描述符的标签
 jnz 不是PD
 
 mov si,[缓存区_1 + 22];PartitionNumber分区编号
 mov [bp -分区编号],si
 mov si,[缓存区_1 + 184];AccessType分区访问类型，1只读，2可写，3可重写，4覆盖写
 mov di,[缓存区_1 + 184 + 2]
 mov [bp - 分区属性低16位],si
 mov [bp - 分区属性高16位],di
 mov si,[缓存区_1 + 188];StartingLocation分区起始逻辑扇区号
 mov di,[缓存区_1 + 188 + 2]
 mov [bp - 分区起始扇区号低16位],si
 mov [bp - 分区起始扇区号高16位],di
 mov si,[缓存区_1 + 192];PartitionLength分区大小，扇区数
 mov di,[缓存区_1 + 192 + 2]
 mov [bp - 分区扇区数低16位],si
 mov [bp - 分区扇区数高16位],di
 cmp word[bp - 文件集描述符所在分区起始扇区号低16位],0FFFFh;交叉验证另一个参数是否存在
 jnz 找到逻辑卷

 cmp word[bp - 文件集描述符所在分区起始扇区号高16位],0FFFFh
 jnz 找到逻辑卷

 不是PD:
 cmp ax,6;LogicalVolumeDescriptor逻辑卷描述符的标签
 jnz 不是LVD

 mov si,[缓存区_1 + 252];LogicalBlockNumber逻辑块号，FSD在分区内的起始扇区号
 mov di,[缓存区_1 + 252 + 2]
 mov [bp - 文件集描述符所在分区起始扇区号低16位],si
 mov [bp - 文件集描述符所在分区起始扇区号高16位],di
 mov si,[缓存区_1 + 256];PartitionReferenceNumber分区引用号，FSD所在的分区号
 mov [bp - 文件集描述符所在分区号],si
 cmp word[bp - 分区起始扇区号低16位],0FFFFh;交叉验证另一个参数是否存在
 jnz 找到逻辑卷

 cmp word[bp - 分区起始扇区号高16位],0FFFFh
 jnz 找到逻辑卷
 
 不是LVD:
 add word[bp - 主卷描述符序列内扇区读取递进号低16位],1;增加到下一个扇区
 adc word[bp - 主卷描述符序列内扇区读取递进号高16位],0;把加法进位CF加到高16位，如果有的话
 mov ax,[bp - 主卷描述符序列内扇区读取递进号低16位]
 mov si,[bp - 主卷描述符序列内扇区读取递进号高16位]
 dec cx
jnz 遍历MVDS

jmp 在MVDS里没有找到所需的描述符


;File Set Descriptor文件集描述符的标签
找到逻辑卷:;获取到了两个参数才会跳转到这里
mov ax,[bp - 分区起始扇区号低16位]
mov si,[bp - 分区起始扇区号高16位]
add ax,[bp - 文件集描述符所在分区起始扇区号低16位]
adc si,[bp - 文件集描述符所在分区起始扇区号高16位]
call LBA48读扇区
cmp word[缓存区_1],100h;文件集描述符的标签
jnz 读取到错误的文件集描述符

;RootDirectoryICB根目录ICB
;mov ,[缓存区_1 + 400];ExtentLength
;mov ,[缓存区_1 + 400 + 2]
mov ax,[缓存区_1 + 404];ExtentLocation
mov si,[缓存区_1 + 404 + 2]
mov cx,[缓存区_1 + 406];PartitionReferenceNumber分区编号
call 读取FE

mov si,LOADER
mov cl,10;文件名长度
mov ch,0;需要文
call 搜索一个指定的FiD条目
jc 没有搜索到文件LOADER

call 读取FE
mov sp,[bp - 0];移除栈帧
;push bp;创建栈帧
;mov bp,sp
;sub sp,读取文件的栈帧大小 - 获取UDF基本参数的函数栈帧大小

;push si;EF的逻辑扇区号高16位
;push ax;EF的逻辑扇区号低16位

test dx,扇区大小 - 1;只要跨越了扇区哪怕只有一比特也要读完整个扇区
jz 不需要多加一个文件扇区

add dx,扇区大小 - 1
adc dx,0;把加法进位CF加到DX，如果有的话

不需要多加一个文件扇区:
mov cx,11;相当于除以2048等于文件的扇区数量

位移计算文件的扇区数量:
 shr di,1;右移一次，最低位移入CF
 rcr dx,1;右移一次，CF移入最高位
loop 位移计算文件的扇区数量

mov di,ax;逻辑扇区号低16位
mov si,bx;逻辑扇区号高16位
mov bp,bx
mov cx,dx;循环次数
mov dh,1;读取的扇区数
mov bx,1000h
mov es,bx
mov bx,0
jmp 不推进到下一个段_1;插入循环

读取文件的栈帧大小 equ 0

读取下一个文件扇区:
add di,1
adc bp,0
mov ax,di
mov si,bp
add bx,扇区大小
jnc 不推进到下一个段_1

mov dx,es
add dx,1000h
cmp dx,9000h
jae 读取的文件大小超过512KB限制

mov es,dx
mov dh,1;DX被修改，重新赋值要读取的扇区数

不推进到下一个段_1:
call LBA48读扇区

loop 读取下一个文件扇区

jmp 1000h:0



;将会修改所有寄存器
;输入AX=FE的扇区号低16位，Si=FE的扇区号高16位，DX=FE的大小低16位，Di=FE的大小高16位，BP上一个函数的栈帧
;输出CX分区编号，AX=EF的逻辑扇区号低16位，BX=EF的逻辑扇区号高16位，DX=FE的大小低16位，Di=FE的大小高16位
读取FE:
add ax,[bp - 分区起始扇区号低16位]
adc si,[bp - 分区起始扇区号高16位]
;push bx;保留BX
;mov cl,dl;保留DL
mov bx,缓存区_1
mov dh,1;读取的扇区数
call LBA48读扇区
cmp word[缓存区_1],105h;FileEntry文件入口的标签
jnz $

mov bx,[缓存区_1 + 168];LengthofExtendedAttributors扩展属性的长度（0 表示无扩展属性），注意这是个32位的值但不应该用到高32位，如果用到了则是遇到错误
cmp word[缓存区_1 + 168 + 2],0
jnz $

mov cx,[缓存区_1+172];LengthofAllocationDescriptes分配描述符的长度，用于定位文件数据或目录内容的信息长度
cmp word[缓存区_1 + 172 + 2],0
jnz $

mov dx,[缓存区_1 + 176 + bx];ExtentLength文件名表大小
mov di,[缓存区_1 + 176 + bx + 2]
mov ax,[缓存区_1 + 180 + bx];ExtentLocation逻辑扇区号
mov bx,[缓存区_1 + 180 + bx + 2]
add ax,[bp - 分区起始扇区号低16位]
adc bx,[bp - 分区起始扇区号高16位]
ret








;将会修改所有寄存器
;输入Si文件名指针，CL文件名长度，CH需要的条目类型，AX=FiD卷的逻辑扇区号低16位，BX=FiD卷的逻辑扇区号高16位，DX=FiD卷的大小低16位，Di=FiD卷的大小高16位
;输出CX分区编号，AX=EF的逻辑扇区号低16位，Si=EF的逻辑扇区号高16位，BX=FE的大小低16位，DX=FE的大小高16位
;500;～1500;缓存区
扇区大小 equ 2048
搜索一个指定的FiD条目:;用于搜索条目的函数
push bp;创建栈帧
mov bp,sp
sub sp,FiD前文件名长度
push di;FiD的大小高16位
push dx;FiD的大小低16位
push bx;FiD的逻辑扇区号高16位
push ax;FiD的逻辑扇区号低16位
;test dx,扇区大小 - 1;只要跨越了扇区哪怕只有一比特也要读完整个扇区
;jz 不需要多加一个FiD扇区

;add dx,扇区大小 - 1
;adc di,0;把加法进位CF加到Di，如果有的话

;不需要多加一个FiD扇区:
;mov cx,11;相当于除以2048等于文件名的扇区数量

;位移计算FiD的扇区数量:
; shr di,1;右移一次，最低位移入CF
; rcr dx,1;右移一次，CF移入最高位
;loop 位移计算FiD的扇区数量
push dx;FiD的扇区数量
mov bl,cl;保留CL文件名长度
mov cl,0;顺便置零FiD扇区内对齐地址
push cx;CL=FiD扇区内对齐地址，CH需要的条目类型
call 获取光标大小和位置
push dx
mov cl,bl;恢复CL文件名长度
mov ax,0
mov es,ax
mov bx,缓存区_2
mov di,缓存区_2 + 256
call UTF8编码字符串转OSTA编码字符串
push cx;mov [bp - OSTA8文件名长度],cx;合并操作，mov [bp - OSTA16文件名长度],ch有两个文件名所以用CX
mov word[bp - FiD缓存区内扇区基地址],缓存区_1 + 扇区大小;手动设置扇区读入的基地址指针到结尾以触发区环回
mov byte[bp - FiD前文件名长度],0;初始为0长度
;mov byte[bp - FiD扇区内对齐地址],0
;mov [bp - 需要的FiD条目类型],ch
mov bx,缓存区_1 + 扇区大小 * 2;手动设置缓存区指针到结束以触发区环回
;参数已全部写入栈帧

FiD缓存区内扇区基地址 equ + 2
FiD前文件名长度 equ FiD缓存区内扇区基地址 + 2
FiD大小高32位 equ FiD前文件名长度 + 2
FiD大小低32位 equ FiD大小高32位 + 2
FiD物理位置LBA高32位 equ FiD大小低32位 + 2
FiD物理位置LBA低32位 equ FiD物理位置LBA高32位 + 2
FiD扇区数 equ FiD物理位置LBA低32位 + 2
需要的FiD条目类型 equ FiD扇区数 + 1
FiD扇区内对齐地址 equ 需要的FiD条目类型 + 1
FiD文件名光标位置 equ FiD扇区内对齐地址 + 2
OSTA16文件名长度 equ FiD文件名光标位置 + 1
OSTA8文件名长度 equ OSTA16文件名长度 + 1
遍历FiD的函数栈帧大小 equ OSTA8文件名长度 + 0

;搜索目标文件或文件夹，遍历所有的文件条目并逐一对比文件名
;使用环回缓存区（环形缓冲区）
遍历FiD条目缓存区:
lea ax,[bx + 38];当前条目起始加上固定数据的长度
sub ax,[bp - FiD缓存区内扇区基地址];判断此条目定长部分是否超出扇区边界，如果大于或等于一个扇区就要读盘，推进到下一个条目后大于一个扇区也要读盘，不会出现如果推进到下一个项后读盘覆盖前面的数据，因为条目不可能大于一个扇区，不会追到尾部
cmp ax,扇区大小;如果等于或大于一个扇区就要读盘
jae 读取下一个FiD扇区
;以上代码用于判断本条目固定长度的数据是否完整

;以下代码用于判断整个条目是否超出缓存区，如果超出槽位则会来到这里判断是否大于缓存区结尾
FiD定长部分并未跨越到下个扇区暂不读盘:;无论如何都要执行此代码以计算条目的长度
不复制条目前半部分:
mov dl,[bx + 19];文件名的字节长度
mov dh,0;清空高位
add dx,[bx + 36];实现者的数据字节长度，可能是iSO镜像的创建者会往这里保存数据，跳过他即可
add dx,38;定长参数部分
mov ax,dx;DX此条目长度
add ax,bx
sub ax,[bp - FiD缓存区内扇区基地址];再次判断本条目是否超出扇区
mov si,bx;指向要对比的条目
jc 没有就结束判断去对比文件名了;基地址还大于偏移指针了，那偏移指针相对于基地址就完全不可能会大于2048

cmp ax,扇区大小
jb 没有就结束判断去对比文件名了

读取下一个FiD扇区:;来到这里就一定要读盘，但要判断从何处而来
cmp bx,缓存区_1 + 扇区大小;如果大于倒数第二个缓存区槽位且上面判断已超出一个扇区的大小则预示着已超出缓存区
mov cx,0;要复制的条目长度，预设被环回截断需要复制的条目长度为零
jbe  FiD缓存区未结束不环回;注意等于倒数第二个扇区也不环回，因为最后一个槽位没被占用仍能使用

mov word[bp - FiD缓存区内扇区基地址],缓存区_1 - 扇区大小;环回到缓存区起始，注意减去一个槽位以应对下面递增一个槽位
mov cx,缓存区_1 + 扇区大小 * 2;在此处计算需要复制的条目长度
sub cx,bx;CX=环回前的部分数据长度
jnz NoRestBX;在这里有三种状态，可能是已经读过盘了，也可能是初始化完刚进来，也有可能是验证条目超长了

;是的话就立刻回滚，但要复制的怎么办，
mov bx,缓存区_1

NoRestBX:
FiD缓存区未结束不环回:
add word[bp - FiD缓存区内扇区基地址],扇区大小;推进到缓存区的下一个槽位
mov di,bx;保留BX
mov bx,[bp - FiD缓存区内扇区基地址]
mov ax,[bp - FiD物理位置LBA低32位]
mov si,[bp - FiD物理位置LBA高32位]
mov dh,1;读取的扇区数量
call LBA48读扇区
mov bx,di;恢复BX
;mov bx,cx
;mov word[bp - FiD缓存区内扇区基地址],bx;已读取新扇区更新基地址
add word[bp - FiD物理位置LBA低32位],1;推进到下一个扇区
adc word[bp - FiD物理位置LBA高32位],0;把加法进位CF加到高16位，如果有的话

;读完盘以后判断是否位于缓存区结尾，如果是则立即复制
是因为超出扇区而进来的:
cmp cx,0
mov ax,bx;保留BX
;mov bx,缓存区_1
jz 不复制条目前半部分

;mov bx,ax;恢复BX

复制一整条项:
;输入CL = 被环形截断的前面部分 = 要复制的部分
;已用完的部分XXXXXXXXXXXXXXXX，要复制的部分OOOOOOOO
;将要复制的部分，分离成定长参数部分和文件名部分，如果有的话
;已用完的部分XXXXXXXXXXXXXXXX，定长参数部分OOOOO，文件名部分OOO
mov si,bx
mov di,缓存区_1 + 扇区大小
mov al,cl;保留CL
rep movsb
sub al,38;减去定长参数部分如果出现负数则不足部分是待复制部分，如果有剩余则剩余部分是多复制的文件名部分
mov si,缓存区_1
jnc NoCopyEnrty

;mov cl,0;CL已被上面的rep movsb指令递减成0
sub cl,al;neg al mov cl,al;将负数反转成正数并赋值给CL
rep movsb
mov al,0;LA=CL复制的是定长参数部分，不减去任何文件名部分

NoCopyEnrty:
mov dx,bx;保留BX
mov bx,缓存区_1 + 扇区大小
mov cl,[bx + 19];文件名的字节长度
add cx,[bx + 36];实现者的数据字节长度，可能是iSO镜像的创建者会往这里保存数据
mov bx,dx;恢复BX
mov dx,cx;条目变长部分
add dx,38;加上定长部分
mov ah,0;清空AX高位
sub cx,ax;减去上面可能已复制过的文件名部分长度，不过多复制
rep movsb;开始复制文件名部分
;add dx,38;文件名部分 + 定长参数部分 = 当前条目长度
mov si,缓存区_1 + 扇区大小;指向复制的完整条目
;mov dx,si;Si指向此条目结尾
;sub si,bx;2048 + 缓存区_1;减去此值，因为下面会还会加上此值，注意加上这个数的倒数等于减去这个数


;输入BX缓存区游标，DX此条目长度，Si指向此条目
;不会修改Si寄存器
没有就结束判断去对比文件名了:
cmp word[bx],101h;FileIdentifierDescriptor文件标识描述符
jnz $

;mov ax,[bx]
push dx;保留DX
push bx;保留BX
mov di,[si + 36];实现者的数据字节长度，可能是iSO镜像的创建者会往此处保存数据，跳过他即可
lea di,[si + 38 + 1];定长参数部分 + 文件名编码类型 = 指向文件名
mov bl,[si + 19];文件名长度
;mov bl,cl;保留CL
mov ch,0;清空CX高位
mov dx,[bp - FiD文件名光标位置]
mov cl,[bp - FiD前文件名长度]
call 重置光标并清除前文件名

mov [bp - FiD前文件名长度],bl;更新文件名长度
;mov bh,0;窗口页码
mov ah,0eh;功能号
mov cl,bl;要显示的文件名长度
jcxz 不能显示零长度的FiD条目名;文件名长度为零则不执行打印代码

dec bl
dec cl

显示FiD条目的一个字符:
 mov al,byte es:[di];读取这个字符
 int 10h
 inc di;推进到下一个字符
loop 显示FiD条目的一个字符

不能显示零长度的FiD条目名:
;inc word[u16_1];断点指定条目
;cmp word[u16_1],0bb6h
;jz $

cmp bl,[bp - OSTA8文件名长度]
jnz 尝试16位文件名

mov cl,[bp - OSTA8文件名长度]
mov dl,bl;保留BL
mov bx,si;保留Si
mov si,[si + 36];实现者的数据字节长度
lea si,[bx + si + 38 + 1];指向文件名
mov di,si;保留Si
call OSTA字符串内的小写字母转成大写
mov si,di;恢复Si
mov cl,dl
mov di,缓存区_2
rep cmpsb
jz FiD文件名和目标文件名相同

尝试16位文件名:
cmp dl,[bp - OSTA16文件名长度]
jnz 判断FiD是否结束;FiD条目文件名长度不符合要求，继续循环搜索下一个条目

mov cl,[bp - OSTA16文件名长度]
mov si,[bx + 36];实现者的数据字节长度
lea si,[bx + si + 38 + 1];指向文件名
mov di,si;保留Si
call OSTA字符串内的小写字母转成大写
mov si,di;恢复Si
mov cl,bl
mov di,缓存区_2 + 256
rep cmpsb
jz FiD文件名和目标文件名相同


;必须要三个参数，原始位置，特殊长度和原始长度
;当前项的长度计算方式 = 实现者特定数据字节byte长度 + 文件名字节byte长度 + 前面的数据固定为38字节byte长度 + 对齐4字节
判断FiD是否结束:
pop bx
pop dx;恢复DX
;mov cx,dx;保留DX
test dl,0000_0011b
jz FiD条目已对齐

add dx,3;4字节对齐
and dl,1111_1100b;清空低2位

FiD条目已对齐:
add bx,dx;推进到下一个条目
cmp bx,缓存区_1 + 扇区大小 * 2
jbe 不环回FiD缓存区

sub bx,扇区大小 * 2

不环回FiD缓存区:
sub [bp - FiD大小低32位],dx;减去一个项的大小，cmp [],2ah
jnz 无需判断FiD大小高32位是否为零

cmp word[bp - FiD大小高32位],0;如果低位为零就要手动判断高位是否为零，因为没有产生借位
jnz 遍历FiD条目缓存区;不为零则跳过设置进位

;jmp 结束循环;可以用jmp 跳出循环但我不想这么做
stc;如果高位为零则设置借位到下面减去借位时也会借位以跳出循环

无需判断FiD大小高32位是否为零:
sbb word[bp - FiD大小高32位],0
jnc 遍历FiD条目缓存区

mov sp,bp;移除栈帧
pop bp
;stc;错误返回
ret

FiD文件名和目标文件名相同:
mov al,[bx + 18];本条目的属性
mov cl,[bp - 需要的FiD条目类型]
mov di,FiD属性表
call 对比条目属性
jnz 判断FiD是否结束

FiD条目属性符合:;读取ICB
mov dx,[bx + 20 + 2];FE数据块的字节长度高16位
mov ax,[bx + 24];ExtentLocation，FE的逻辑块地址（LBA）低16位
mov si,[bx + 24 + 2];FE的逻辑块地址（LBA）高16位
mov cx,[bx + 28];PartitionReferenceNumber，分区编号，标识 BA所属的分区（对应 PD 的 Partition Number）
mov bx,[bx + 20];ExtentLength，FE数据块的字节长度低16位
mov sp,bp;移除栈帧
pop bp
;clc;正确返回
ret


























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
push si
mov si,消息_NONE
call 打印
pop si
call 打印
mov si,消息_回车加换行

打印并退出:
call 打印

返回BiOS:
int 18h;启动其他的操作系统或进入ROM BASiC解释器



;将会修改AX，BX，CX，DX，Si，Di寄存器
;输入AX=卷扇区号低16位，Si=卷扇区号高16位，DX=卷大小低16位，Di=卷大小高16位，BX文件名地址，CL文件名长度，CH需要的条目类型
;输出AX逻辑扇区号低16位，Si逻辑扇区号高位16位，DX数据长度低16位，Di数据长度高16位
iSO9660的检索文件或文件夹:
push bp;创建栈帧
mov bp,sp
sub sp,上一条目的字符长度
;mov byte[bp - 上一iSO9660文件条目长度],0
mov word[bp - 上一条目的字符长度],1;上一项字符长度 应该是0但使用此值会导致某些BiOS清空全屏，所以使用1来解决
push si
push ax
push di
push dx
push word[实际扇区大小]
push bx;mov [bp - 第一条文件名位置],bx
sub sp,4
mov byte[bp + 第二条文件名长度],0
mov [bp -  第一条文件名长度],cl
add word[bp - iSO9660文件名条目扇区缓冲区结束],缓冲区1

上一iSO9660文件条目长度 equ + 1
上一条目的字符长度 equ 上一iSO9660文件条目长度 + 1
文件名表扇区号高16位 equ 上一条目的字符长度 + 2
文件名表扇区号低16位 equ 文件名表扇区号高16位 + 2
文件名表大小高16位 equ 文件名表扇区号低16位 + 2
文件名表大小低16位 equ 文件名表大小高16位 + 2
iSO9660文件名条目扇区缓冲区结束 equ 文件名表大小低16位 + 2
第一条文件名位置 equ iSO9660文件名条目扇区缓冲区结束 + 2
需要的属性位掩码 equ 第一条文件名位置 + 1
需要的条目属性_1 equ 需要的属性位掩码 + 1
第二条文件名长度 equ 需要的条目属性_1 + 1
第一条文件名长度 equ 第二条文件名长度 + 1
文件名前光标位置_1 equ 第一条文件名长度 + 2
搜索iSO9660文件或文件夹的函数栈帧大小 equ 文件名前光标位置_1 + 0

;From 表10 ファイルフラグ
cmp ch,0FFh
jnz 属性转译_1

mov [bp - 需要的条目属性_1],ch
jmp 属性转译结束_1;全部属性都要因此无需转译属性

属性转译_1:
mov dx,0
test ch,0000_0001b;需要文件还是文件夹
jz 需要文件_1

or dl,0000_0010b;目标条目是1则表示文件夹

需要文件_1:
or dh,0000_0010b;保留第2位表示文件还是文件夹
mov [bp - 需要的条目属性_1],dx

属性转译结束_1:
mov si,bx
mov ah,cl;保留CL
mov ch,0
call UTF8字符串内的小写字母转成大写
cmp word[bp - 第一条文件名长度],8
jbe 不用截断成短文件名;小于等于则跳转

;将会修改AX，CX，Si，Di寄存器
;把文件名截断成8.3格式
mov di,bx
mov cl,ah
add di,cx;指向字符串结尾
mov al,'.';句号。

;继续对比字符:
std;倒序
repnz scasb
cld;正序
jz 有句号

;没有句号
mov si,bx
mov di,缓存区_2
mov cl,8;只复制8个字符
rep movsb
mov byte[bp - 第二条文件名长度],8
jmp 不用截断成短文件名;短文件名截断完成

有句号:
inc cl;repnz指令会多执行一次，先读取下一次的字符再根据这次的结果决定是否继续执行
sub ah,cl;总长度减去剩余长度得到已扫描的长度也就是后缀名长度
cmp cl,8;先判断字符串剩余的长度也就是文件名长度
ja 截断文件名

dec ah;repnz指令会多执行一次，注意句号
cmp ah,3;再判断后缀名长度
ja 截断后缀名

jmp 不用截断成短文件名;不要截断后缀名

截断文件名:
mov cl,8

截断后缀名:
mov si,bx
mov di,缓存区_2
mov al,cl;保留CL
rep movsb
and ah,00000011b;只保留两个比特位最大可表示数字3，刚好是短文件名的最大长度
inc ah;增加一个字符把句号也复制过来
mov cl,ah
add al,ah
rep movsb
mov byte[bp - 第二条文件名长度],al

不用截断成短文件名:
call 获取光标位置
push dx;刷新 光标位置
mov bx,[bp - iSO9660文件名条目扇区缓冲区结束]
mov ch,0;帮下面清空CX高位

继续对比:
call 获取一个iSO9660文件名条目
jc 项已完结

;mov bh,0;BH已被重置光标并清除前文件名置零
cmp word[si + bx - 2],';1'
jnz 已减去版本号;没有版本号则不用减去

sub bl,2
ja 已减去版本号

add bl,2;文件名长度错误，因此减去的是文件名而不是版本号，要把文件名加回来

已减去版本号:
mov cl,bl
call 不清空BH的显示项名
mov cl,byte[bp - 上一条目的字符长度]
sub cl,bl
mov [bp - 上一条目的字符长度],bl;刷新 上1项字符长度
jbe 上一项名已被当前项名覆盖完了;因此无需清除项名

mov ax,0a00h + ' ';mov al,' ';用空格覆盖;mov ah,10;功能号，重复显示一个字符
;mov bh,0;窗口页码
int 10h

上一项名已被当前项名覆盖完了:
mov ah,bl;保留BL
mov dh,[bp - 需要的条目属性_1]
mov bx,di
cmp dh,0FFh;任何属性的条目都要
jz 属性相同;无需对比目标属性了

and dl,[bp - 需要的属性位掩码];清空不需要的位
cmp dl,dh
jnz 继续对比

属性相同:
cmp ah,[bp - 第一条文件名长度]
jnz 尝试第二项;第一项名长不匹配

mov cl,ah;字符长度
lea si,[bx + 33];字符地址
call UTF8字符串内的小写字母转成大写
mov cl,ah
mov si,[bp - 第一条文件名位置]
lea di,[bx + 33];字符地址
rep cmpsb
jz 项名相同

尝试第二项:
cmp ah,[bp - 第二条文件名长度]
jnz 继续对比;文件名不一样长就不用对比了

mov cl,ah;字符长度
lea si,[bx + 33];字符地址
call UTF8字符串内的小写字母转成大写
mov cl,ah
mov si,缓存区_2;第2项文件名位置
lea di,[bx + 33];字符地址
rep cmpsb
jnz 继续对比

项名相同:
mov ax,[bx + 2];逻辑扇区号低16位
mov si,[bx + 2 + 2];逻辑扇区号高16位
mov dx,[bx + 10];数据长度低16位
mov di,[bx + 10 + 2];数据长度高16位
mov sp,bp
pop bp
;clc;CF标志位已被CMPSB指令置零
ret

项已完结:
mov dx,[bp - 文件名前光标位置_1]
mov cl,byte[bp - 上一条目的字符长度]
call 重置光标并清除前文件名
mov sp,bp
pop bp
stc
ret



;将会修改EAX，EBX，CX，DX，Si，Di寄存器
;输入EAX数据长度，ECX逻辑扇区号，DL属性，Si文件名位置
;输出AX逻辑扇区号低16位，Si逻辑扇区号高位16位，DX数据长度低16位，Di数据长度高16位
Joliet的检索文件或文件夹:
sub sp,4
;mov byte[esp+0],文件或文件夹名长度
;mov word[esp+1],光标位置
mov byte[esp+3],1;上1项字符长度 应该是0但使用此值会导致某些BiOS清空全屏，所以使用1来解决
mov [u32_1],eax
mov ebp,ecx
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
mov dx,ax
shr eax,16
mov di,ax
mov ax,bp;逻辑扇区号
shr ebp,16
mov si,bp
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
获取光标大小和位置:
mov ah,3;功能号
mov bh,0;页码
int 10h; AX=0000h(Phoenix BiOS)，CH光标高度起始和参数，CL光标高度结束，DH光标行位置（00h则位于顶部），DL光标列位置（00h则位于左侧）
ret



;将会修改AX，BH，CX寄存器
;输入CL覆盖长度，DX光标位置
;输出
重置光标并清除前文件名:
mov ah,2;功能号
mov bh,0;窗口页码
int 10h
mov al,' ';用空格覆盖
mov ah,10;功能号
;mov bh,0;窗口页码
mov ch,0;清空CH覆盖的字符数量
int 10h
ret



;AX，BH，CX，Si寄存器将会被修改
;输入CL字符长度，Si项名
;输出
显示项名:
mov bh,0;页码

不清空BH的显示项名:
mov ah,14;功能号

循环显示完项名:
 lodsb
 int 10h
loop 循环显示完项名
ret



;将会修改EAX，EBX，ECX，DX，Si，Di寄存器
;输入EAX数据长度，ECX逻辑扇区号，DL第一次需要属性
;输出EAX数据长度，ECX逻辑扇区号，BL字符长度，Di字符地址
;错误则设置进位
iSO9660获取一个项:
call Joliet获取一个项
jc 已读完所有扇区_2

cmp byte[文件属性号],1;属性为文件夹则不需要减2
jz 没有结束符_1

mov bh,0
cmp word[di+bx-2],';1';有时候文件名结尾会带个版本号
jnz 没有结束符_1

dec bl;文件名长度-2
dec bl

没有结束符_1:
clc
ret

已读完所有扇区_2:
stc
ret


; test byte[标志],1b;被测试位=0则ZF=1
; jnz 不要重置_1

; or byte[标志],1b;取消下次重置
; mov [文件属性号],dl
; mov [逻辑扇区号],ebx
; mov edx,0;清空除法高位
; movzx ecx,word[实际扇区大小]
; div ecx;edx高：eax低÷ecx=eax…edx
; cmp dx,0
; jz 不增加一个扇区_1

; inc ax;超出一个字节都需要读完整个扇区

; 不增加一个扇区_1:
; mov [循环次数],ax
; mov eax,[逻辑扇区号]
; mov bx,缓存区_1
; call 读扇区
; inc dword[逻辑扇区号];预先推到下一个扇区
; mov bx,缓存区_1
; movzx ax,byte[缓存区_1];跳过一个.目录
; add bx,ax
; mov al,[bx];跳过一个..目录
; add bx,ax
; mov [扇区内数据位置],bx
; jmp 不要读扇区;第一次则直接读取项

; 不要重置_1:
; mov bx,[扇区内数据位置]
; mov dx,0;不允许推进

; 属性不同:
; add bx,dx;推进到下一个项
; mov ax,[实际扇区大小]
; add ax,bx
; cmp bx,ax
; jb 不要读扇区;小于则跳转

; 触底:
; dec word[循环次数]
; jz 扇区读完

; mov eax,[逻辑扇区号]
; mov bx,缓存区_1
; call 读扇区
; inc dword[逻辑扇区号];预先推到下一个扇区

; 不要读扇区:
; movzx dx,byte[bx];取这个项的长度
; cmp dl,0
; jz 触底;遇到空项

; mov di,iSO9660属性表
; mov al,[bx+25];取属性
; call 对比文件属性
; jnz 属性不同

; mov eax,[bx+2];2双端格式的范围地址 (LBA)，2~8÷2
; mov ecx,[bx+10];双端格式的数据长度（范围大小）
; lea di,[bx+33];文件名
; add dx,bx
; mov [扇区内数据位置],dx;推进到下一个项
; movzx bx,byte[bx+32];文件名长度
; cmp byte[文件属性号],1;属性为文件夹则不需要减2
; jz 已省略iSO9660版本号

; cmp word[bx+di-2],';1'
; jnz 已省略iSO9660版本号

; dec bl;文件名长度-2
; dec bl

; 已省略iSO9660版本号:
; clc
; ret

; 扇区读完:
; and byte[标志],11111110b
; stc
; ret



;将会修改AX，BX，CX，DX，Si，Di寄存器
;输入BX缓冲区偏移指针，BP调用者的栈帧，BP - 2 = 文件名表大小高16位，BP - 4 = 文件名表大小低16位，BP - 6 = iSO9660文件名条目扇区缓冲区结束
;输出Di扇区内数据偏移，DL文件名条目的属性，BL字符长度，Si字符地址
;test指令示例test al,0000_0100b;被测试位 =0则ZF =1
获取一个iSO9660文件名条目:
Joliet获取一个项:
mov cl,[bp - 上一iSO9660文件条目长度]

减去一个iSO9660文件条目:
sub [bp - 文件名表大小低16位],cx
ja 文件条目表大小低位还没用完

jnz 不设置退出循环的借位_1

cmp word[bp - 文件名表大小高16位],0;如果低位为零就要手动判断高位是否为零，因为没有产生借位
jnz 不设置退出循环的借位_1;不为零则跳过设置进位

stc;如果高位为零则设置借位到下面减去借位时也会借位以跳出循环

不设置退出循环的借位_1:
sbb word[bp -文件名表大小高16位],0
jc iSO9660文件名条目已耗尽

文件条目表大小低位还没用完:
add bx,cx;上一条目的起始加上一条目的长度等于下一条目的起始
cmp bx,[bp - iSO9660文件名条目扇区缓冲区结束]
jae 读取下一个扇区_1

获取项_1:
cmp byte[bx],0;iSO9660的文件名条目不会跨越扇区，如果当前扇区不足以保存本项，则本项会被推到下一个扇区，当前扇区的剩余空间则会用零填充
jnz 还可以取项_1;没有项了

mov cx,[bp - iSO9660文件名条目扇区缓冲区结束]
sub cx,bx
jbe 读取下一个扇区_1;缓冲区偏移指针越界或指向结束则直接读取下一个扇区

cmp cx,34 - 1;一个没有文件名的条目长度
mov byte[bp - 上一iSO9660文件条目长度],0;注意此条目的长度已被立即减去，当下次循环时不要减去已减过的条目
jb 减去一个iSO9660文件条目;余下的空间不足以存放一个条目，因此无需搜索剩下的空间

mov dx,cx;保留CX
mov di,bx
mov al,0
repz scasb
jnz 填充的空间后还有条目;不应该发生这种情况，条目必须紧挨着一条接一条中间不能有空隙

mov cx,dx
jmp 减去一个iSO9660文件条目

填充的空间后还有条目:
sub dx,cx;总大小减去已剩余大小等于空块大小
mov cx,dx
jmp 减去一个iSO9660文件条目

读取下一个扇区_1:
mov bx,缓存区_1;环回到缓冲区起始
mov dh,1
mov ax,[bp - 文件名表扇区号低16位]
mov si,[bp - 文件名表扇区号高16位]
call LBA48读扇区
add word[bp - 文件名表扇区号低16位],1
adc word[bp - 文件名表扇区号高16位],0

还可以取项_1:
mov dx,[bp - 文件名前光标位置_1]
mov di,bx;保留BX
;call 重置光标并清除前文件名
mov ah,2;功能号
mov bh,0;窗口页码
int 10h
mov bl,[di];本条目的长度
mov [bp - 上一iSO9660文件条目长度],bl;更新上一条目的长度记录
mov dl,[di + 25];本条目的属性
mov bl,[di + 32];文件名长度
lea si,[di + 33];文件名地址
clc

iSO9660文件名条目已耗尽:
;stc;CF标志位已被SBB指令置1
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
shr eax,4; E0000_0000_E000x_xxxx AHxxxx_xxxx_ALxxxx_xxxx此时将得到Unicode码
sub eax,10000h;将Unicode码压缩到20位
shl eax,6; E0000_00xx_Exxxx_xxxx AHxxxx_xxxx_ALxx00_0000
shr ax,6;  E0000_00xx_Exxxx_xxxx AH0000_00xx_ALxxxx_xxxx
;and eax,000000_1111111111_000000_1111111111b
or eax,110110_0000000000_110111_0000000000b
stosd
jmp UTF8字符串转UTF16字符串

UTF8字符串转UTF16字符串结束:;
clc
ret



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
 sub byte[si-1],32;lodsw把Si+2但我们只减1是因为大小端的原因

 不要转换_1:
loop UTF16字符串内的小写字母转成大写

ret



;将会修改AL，CX，Si寄存器
;输入DS：Si字符串地址，CX字符串长度
;输出
UTF8字符串内的小写字母转成大写:;
 lodsb
 test al,1000_0000b
 jz 尝试转化为大写字母;单字节编码_3

 cmp al,110_00000b
 jb 双字节编码_3

 cmp al,1110_0000b
 jb 三字节编码_3

 ;cmp al,11110_000b
 ;jb 四字节编码_3

 四字节编码_3:
 inc si

 三字节编码_3:
 inc si

 双字节编码_3:
 inc si
 jmp 不要转换_2

 尝试转化为大写字母:
 cmp al,'a'
 jb 不要转换_2;小于则跳转

 cmp al,'z'
 ja 不要转换_2;大于则跳转

 sub byte[si-1],32;小写字母到大写字母的差值

 不要转换_2:
loop UTF8字符串内的小写字母转成大写

ret



;将会修改AX，CX，DX，Si，Di寄存器
;输入DS：Si目标字符字符串指针，ES：BX OSTA8的字符缓存区，ES：Di OSTA16的字符串缓存区
;输出ES：BX OSTA8的字符串指针，CL=OSTA8字符计数，CH=OSTA16字符计数，ES：Di OSTA16的字符串指针
UTF8编码字符串转OSTA编码字符串:
mov dx,si;保留Si原始字符串指针
mov cx,0;清空字符计数
jmp 获取一个UTF8字符转OSTA16字符;插入循环

UTF8字符转OSTA16字符:
 cmp al,1_0000000b
 jb 单字节编码

 cmp al,110_00000b
 jb 双字节编码

 cmp al,1110_0000b
 jb 三字节编码

 ;cmp al,11110_000b
 ;jb 四字节编码

 四字节编码:;不支持大于0x10000的编码
 add si,3;注意开始时已经取了一字节
 mov word[di],0FDFFh;将错误字符替换为�（FFFD）注意大端
 add di,2
 jmp 获取一个UTF8字符转OSTA16字符

 单字节编码:
 stosb
 inc cl;字符计数加一
 jmp 获取一个UTF8字符转OSTA16字符

 双字节编码:
 mov ah,[si + 1]
 inc si
 cmp ah,10_000000b
 ja 双字节编码错误

 shl al,3;往上移3位顺便覆盖标志位
 ;and ah,00_111111;只保留低6位
 shr ax,3;往下移3位使其变成从零开始每一位对齐
 stosw
 inc cl;字符计数加一
 jmp 获取一个UTF8字符转OSTA16字符

 三字节编码:
 ;mov eax,[si - 1];不建议这样因为可能会越界遇到段错误就老实了
 mov ah,[si + 2]
 cmp ah,10_000000b
 ja 三字节编码错误

 and ah,00_111111b;只保留低6位
 shl eax,6;移到EAX
 shr ax,6 - 4;把被移动的AL移回来，可以少移4位，省得到下面还要移上去4位
 mov ah,[si + 1]
 cmp ah,10_000000b
 ja 三字节编码错误

 shl ax,2;拼接到EAX，顺便清空标志
 shr eax,4;往下移4位使其变成从零开始每一位对齐
 stosw
 inc cl;字符计数加一
 jmp 获取一个UTF8字符转OSTA16字符

 双字节编码错误:
 dec si;减一因为需要跳过一字节而上面会跳过二字节

 三字节编码错误:
 dec si;减一因为需要跳过二字节而上面会跳过三字节
 jmp 四字节编码

 获取一个UTF8字符转OSTA16字符:
 lodsb
 cmp al,0
jnz UTF8字符转OSTA16字符;循环转换以转换所有字符


转换成OSTA16字符串:
mov si,dx;恢复目标字符串指针
xchg di,bx
jmp UTF8字符转OSTA8位字符;插入循环

;UTF8字符串转OSTA8字符串:
循环把UTF8字符转OSTA8位字符:
 cmp al,1_0000000b
 jb 单字节编码_2

 cmp al,110_00000b
 jb 双字节编码_2

 ;cmp al,1110_0000b
 ;jb 三字节编码_2

 cmp al,11110_000b
 ;jb 四字节编码_2

 四字节编码_2:;不支持大于0x10000的编码
 jmp UTF8字符串转OSTA8字符串错误;已无需转换

 单字节编码_2:
 stosb
 inc ch;字符计数加一
 jmp UTF8字符转OSTA8位字符

 双字节编码_2:
 mov ah,[si + 1]
 inc si
 cmp ah,10_000000b
 ja 四字节编码_2

 shl al,3;往上移3位顺便覆盖标志位
 ;and ah,00_111111;只保留低6位
 shr ax,3;往下移3位使其变成从零开始每一位对齐
 cmp ax,0FFh;任意一个字符大于0xFF就表示不是OSTA8编码
 ja UTF8字符串转OSTA8字符串错误;已无需转换

 stosw
 inc ch;字符计数加一
 jmp UTF8字符转OSTA8位字符

 ;三字节编码_2:
 ;jmp UTF8字符串转OSTA8字符串错误;已无需转换

 UTF8字符转OSTA8位字符:
 lodsb
 cmp al,0
jnz 循环把UTF8字符转OSTA8位字符

UTF8字符串转OSTA8字符串错误:
xchg bx,di
ret


;将会修改AX，CX，Si寄存器
;输入CX字符串的长度，Si指向字符串
;输出
OSTA字符串内的小写字母转成大写:;
mov al,[si - 1];读取compiD，只能是8或16，如果是他的的值表示compiD错误
;dec cx;字符计数减一
cmp al,16
jz 是CS016

cmp al,8
jnz 不是CS08;都不是则表示compiD是错误的

OS08编码的小写字母转换成大写:
 lodsb
 cmp al,'a'
 jb 不要转换_3;小于则跳转

 cmp al,'z'
 ja 不要转换_3;大于则跳转

 sub byte[si-1],32;减去差值

 不要转换_3:
loop OS08编码的小写字母转换成大写

ret

是CS016:
 lodsw
 cmp ax,6100h;a字母在高位，低位是零
 jb 不要转换_4;小于则跳转

 cmp ax,7a00h;z字母在高位，低位是零
 ja 不要转换_4;大于则跳转

 sub byte[si-1],32;减去差值

 不要转换_4:
loop 是CS016

ret

不是CS08:
stc
ret



;将会修改CX，Di寄存器
;输入AL文件名条目的属性，Di属性表，BP调用者的栈帧，BP - 13 = 需要的属性
;输出
;ZF=0=属性不同
对比文件属性:




;将会修改CX，Di寄存器
;输入AL条目的属性，CL需要的条目类型，ES：Di总属性表
;输出
;ZF=0=属性不同
对比条目属性:
cmp cl,0FFh;任何属性的条目都要
jz 属性相同_2;是的任何属性都要

mov ch,0;清空CX高位
shl cl,1; × 2
add di,cx;加上偏移指向文件或文件夹属性表指针
mov di,[di];读取指针以指向文件或文件夹属性表
mov cl,[di-1];对比次数即属性表大小
repne scasb

属性相同_2:
ret










;将会修改AX，BX，CX，DX，Si，Di，BP，ES寄存器
;输入AX=LBA逻辑扇区号低16位，Si=LBA逻辑扇区号高位16位，扇区读取到ES段地址，扇区读取到BX偏移地址，DX要读取的数据长度低16位，Di要读取的数据长度高16位
;输出
iSO9660读入扇区:
cmp di,9
ja 读取的文件大小超过512KB限制

jnz 无需判断高16位是否为零_1;读取的文件大小不是刚好512KB

cmp dx,0
ja 读取的文件大小超过512KB限制

无需判断高16位是否为零_1:
mov cl,[数据长度转扇区数量的位移次数]
;mov ch,0
test dx,扇区大小 - 1;只要跨越了扇区哪怕只有一比特也要读完整个扇区
jz 不需要多加一个文件扇区_2

add dx,扇区大小 - 1
adc di,0;把加法进位CF加到Di，如果有的话

不需要多加一个文件扇区_2:
;位移计算文件的扇区数量_2:
 shr di,1;右移一次，最低位移入CF
 rcr dx,1;右移一次，CF移入最高位
loop 不需要多加一个文件扇区_2;位移计算文件的扇区数量_2

mov cx,dx;循环次数
mov di,ax;保留逻辑扇区号低16位
mov bp,si;保留逻辑扇区号高16位
mov dh,1;读取的扇区数
jmp 不推进到下一个段_2;插入循环

读取文件扇区_1:
 add di,1;推进到下一个扇区
 adc bp,0
 mov ax,di;逻辑扇区号
 mov si,bp
 add bx,[实际扇区大小];增加一个扇区大小的偏移
 jnc 不推进到下一个段_2

 mov dx,es
 add dx,1000h
 mov es,dx
 mov dh,1;DX已被修改，重新赋值要读取的扇区数

不推进到下一个段_2:
 call LBA48读扇区
loop 读取文件扇区_1

ret









;将会修改AX，DL，Si寄存器
;输入;输入AX=LBA低16位，Si=LBA高位16位，扇区读取到ES段地址，扇区读取到BX偏移地址，DH要读取的扇区数量
;输出
LBA48读扇区:
xchg sp,si
mov [si - 2 * 3],sp;注意DS要等于SS因为BiOS使用的数据包是DS：Si
mov sp,si
mov si,0
push si;[12]LBA第64位
push si;[10]LBA第48位
;push si;[8]LBA第32位
dec sp;已用上面的mov ss:[si]赋值
dec sp;跳过一个push
push ax;[6]LBA第16位
push es;[6]段地址
push bx;[4]偏移地址
mov ah,0;byte[3]保留，必须为0，正好被下面的push AX覆盖，因为AH高位为零，注意栈最小压Word
mov al,dh
push ax;[2]要传输的扇区数只能是0 ~ 127
;mov ah,0;byte[1]保留，必须为0，由于栈最小压Word所以正好被下面的push AX所覆盖，因为这是参数块的高位
mov al,16
push ax;[0]参数块大小，注意栈最小压Word

mov ah,42h;功能号
mov dl,[驱动器号]
mov si,sp;DS：Si指向数据包，注意栈是反过来的
int 13h;中断号
lahf;保存标志寄存器因为要返回ZF标志位
add sp,16;从栈中移除参数块
sahf;恢复标志位
jc $

ret



;将会修改AH，DL，Si寄存器
;输入;输入EBP=LBA低32位，EBX高位=段地址，EBX低位=偏移地址，DH要读取的扇区数量
;输出
LBA48读盘:
push dword 0;[12]LBA高32位
push ebp;[8]LBA低32位
;word[6]段地址
push ebx;[4]偏移地址
shl word[esp + 2],12; × 1000h
;byte[3]保留，必须为0，正好被下面的push Si覆盖，因为Si高位为零，注意栈最小压Word
movzx si,dh
push si;[2]要传输的扇区数只能是0 ~ 127
;byte[1]保留，必须为0，由于栈最小压Word所以正好被下面的push 16所覆盖，因为这是参数块的高位
push byte 16;[0]参数块大小，注意栈最小压Word

mov ah,42h;功能号
mov dl,[驱动器号]
mov si,sp;注意栈是反过来的
int 13h;中断号
lea sp,[esp + 16];从栈中删除参数块
jc $

ret



;将会修改AH，DL，Si寄存器
;输入EAX=LBA低32位，BX段地址
;输出BX：0目标位置





;将会修改AH，DL，Si寄存器
;输入EAX=LBA低32位，EBX高位段地址，EBX低位偏移地址
;输出
读扇区:
push dword 0;[12]LBA高32位
push eax;[8]LBA低32位
;word[6]段地址
push ebx;[4]偏移地址
;byte[3]保留，必须为0，注意栈最小压Word
push byte 1;[2]要传输的扇区数0~127
;byte[1]保留，必须为0，CX的高位就是这里的值应当清空CH寄存器，注意栈最小压Word
push byte 16;[0]参数块大小

mov ah,42h;功能号
mov dl,[驱动器号]
mov si,sp;注意栈是反过来的
int 13h;中断号
lea sp,[esp + 16];从栈中删除参数块
jc 读扇区错误

ret

读扇区错误:
mov si,消息_光盘读取错误
jmp 打印并退出




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



获取光盘参数时异常:
mov si,消息_光盘错误
jmp 打印并退出

光盘处于仿真模式:
mov si,消息_光盘处于仿真模式不可使用光盘文件系统
jmp 打印并退出

驱动器号不同:
mov si,消息_驱动器号不同
jmp 打印并退出

没有读取到锚点卷描述符:
mov si,消息_没有读取到锚点卷描述符
jmp 打印并退出


在MVDS里没有找到所需的描述符:
cmp word[bp - 分区起始扇区号低16位],0
jnz PD已读取
 
cmp word[bp - 分区起始扇区号高16位],0
jnz PD已读取

mov si,消息_没有找到分区描述符
call 打印

PD已读取:
cmp word[bp - 文件集描述符所在分区起始扇区号低16位],0
jnz LVD已读取

cmp word[bp - 文件集描述符所在分区起始扇区号高16位],0
jnz LVD已读取

mov si,消息_没有找到逻辑卷描述符

LVD已读取:
jmp 返回BiOS


读取到错误的文件集描述符:
mov si,消息_读取到错误的文件集描述符
jmp 打印并退出

没有搜索到文件LOADER:
mov si,消息_回车加换行
call 打印
mov si,消息_NONE
call 打印
mov si,LOADER
call 打印
mov si,消息_回车加换行
jmp 打印并退出

;https://en.wikipedia.org/wiki/Conventional_memory
读取的文件大小超过512KB限制:
mov si,消息_读取的文件大小超过512KB限制
jmp 打印并退出













消息_回车加换行 db 13
消息_换行 db 10,0
消息_NONE db 'None ',0
消息_光盘错误 db 13,10,'Disc error',13,10,0
消息_光盘处于仿真模式不可使用光盘文件系统 db 13,10,'Disc is in an emulation mode',13,10,0
消息_驱动器号不同 db 13,10,'Drive letters are different',13,10,0
消息_光盘读取错误 db 13,10,'Disc read error',13,10,0
消息_没有读取到锚点卷描述符 db 13,10,'No read found Anchor Volume Descriptor',13,10,0
消息_没有找到分区描述符 db 13,10,'No secrch found Partition Descriptor',13,10,0
消息_没有找到逻辑卷描述符 db 13,10,'No search found Logical Volume Descriptor',13,10,0
消息_读取到错误的文件集描述符 db 13,10,'Read error File Set Descriptor',13,10,0
消息_读取的文件大小超过512KB限制 db 13,10,'Read file size larger than 512KB limit',13,10,0

二卷 db 2,'CD001';不一定在第二槽位
Joliet标识 db '%/E',0;或是@或是C或是E
扩展描述 db 'BEA01'
扩展描束 db 'TEA01'
UDFS标识 db 'NSR2',0;或是NSR0或是NSR2
BOOT db 'BOOT',0;所有的文件名都是都是大写，0用于结束符
LOADER db 'LOADER.BIN',0

驱动器号 db 0
逻辑扇区号 dd 0
循环次数 dw 0
标志 db 0
文件属性号 db 0
实际扇区大小 dw 0
数据长度转扇区数量的位移次数 db 0
扇区内数据位置 dw 0
文件系统类型 db 0
根目录逻辑扇区 dd 0
根目录大小 dd 0

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

FiD属性表:
dw FiD文件
dw FiD文件夹

db 1;长度
FiD文件:
db 0

db 2;长度
FiD文件夹:
db 2h
db 10h

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


times 2048 * 2 - 2 - ($ - $$) db 0;对于无仿真启动，BiOS最大可加载500KB大小的引导扇区
引导扇区结束符 db 55h,0AAh;需要，否则可能会黑屏