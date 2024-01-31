[BITS 16]
org 7c00h
start:
    mov ax, cs
    mov ds, ax
    mov es, ax           
    mov esp, 7c00h
    jmp load_stage2

disk_rw_struct:
    db 16  ; disk_rw_struct 的大小，10h
    db 0   ; 反转，必须为 0
    dw 0   ; 扇区数
    dd 0   ; 目标地址
    dq 0   ; 起始LBA号

read_disk_by_int13h:
    mov eax, dword [esp + 8]
    mov dword [disk_rw_struct + 4], eax
    mov ax, [esp + 6]
    mov word [disk_rw_struct + 2], ax
    mov eax,dword [esp + 2]
    mov dword [disk_rw_struct + 8], eax
    mov ax, 4200h
    mov dx, 0080h
    mov si, disk_rw_struct
    int 13h
    ret

; 第一个扇区代码作用：读取硬盘加载加下来几个扇区的代码到内存中
load_stage2:
    push dword 0x7e00   ; 目标地址
    push word 50        ; 块数
    push dword 1        ; 起始LBA号
    call read_disk_by_int13h
    add esp, 10
    jmp enter_long_mode;跳转到loader代码

times 510-($-$$) db 0
dw 0xaa55


;此处为loader
E820_BUFFER equ 0xc000
PAGE_TABLE equ 0x40000
CODE_SEG equ 0x0008
DATA_SEG equ 0x0010

gdt64:
.Null:
    dq 0                              ; 空描述符 - 应该存在。
.Code:
    dq 0x00209A0000000000             ; 64 位代码描述符（执行/读取）.
    dq 0x0000920000000000             ; 64 位数据描述符（读/写）.
ALIGN 4, dw 0
.pointer:
    dw $ - gdt64 - 1                    ; GDT 的 16 位大小（限制）。
    dd gdt64

enter_long_mode:
    call memory_detect      ; 利用e820中断探测内存
	call 设置段寄存器的隐藏部分
    call fill_page_table    ; 初始化临时页表
    call enable_paging      ; 开启分页
    lgdt [gdt64.pointer]
    jmp CODE_SEG:long_mode_entry
    
mmap_entry_count equ E820_BUFFER
memory_detect:
    mov edi, 0xc004
    xor ebx, ebx		
	xor bp, bp		
	mov edx, 0x0534D4150
	mov eax, 0xe820
	mov [es:edi + 20], dword 1	
	mov ecx, 24
	int 0x15
    jc .failed
    mov edx, 0x0534D4150
	cmp eax, edx
	jne short .failed
	test ebx, ebx
	je .failed
	jmp .jmpin
    .e820_loop:
	    mov eax, 0xe820		; eax、ecx 在每次 int 0x15 调用时都会被丢弃
	    mov [es:edi + 20], dword 1	; 强制输入有效的 ACPI 3.X 条目
	    mov ecx, 24		; 再次请求 24 字节
	    int 0x15
	    jc short .detect_finish		; 进位集意味着“已到达列表末尾”
	    mov edx, 0x0534D4150	; 修复可能已损坏的寄存器
    .jmpin:
        jcxz .skip_entry		; 跳过任何 0 长度的条目
        cmp cl, 20		; 收到 24 字节 ACPI 3.X 响应？
        jbe .add_idx
        test byte [es:edi + 20], 1	; 如果是这样：“忽略此数据”位是否清楚？
        je .skip_entry
    .add_idx:
        mov ecx, dword [es:edi + 8]	; 获取较小的 uint32_t 内存区域长度
        or ecx, dword [es:edi + 12]	; 将其与上位 uint32_t 进行“或”操作以测试零
        jz .skip_entry		; 如果长度 uint64_t 为 0，则跳过条目
        inc bp			; 得到一个好的条目：++count，移动到下一个存储点
        add edi, 24
    .skip_entry:
        test ebx, ebx		; 如果 ebx 重置为 0，则列表完整
        jne .e820_loop
    .detect_finish:
        mov [mmap_entry_count], bp
        clc
        ret
    .failed:
        hlt

fill_page_table:
    mov edi, PAGE_TABLE   ; page talbe从0x40000开始，占用20KB内存并映射前26MB
    push edi
    mov ecx, 0x10000
    xor eax, eax
    cld
	
	_64KBkaczero
	mov dword fs:[edi],0
	add edi,4
	loop _64KBkaczero
	
    ;rep stosd          ; 将 64KB 内存归零
    pop edi
;p4	
    lea eax, [fs:edi + 0x1000]  ;p3的位置   
    or eax, 3 
    mov [fs:edi], eax
;p3
    lea eax, [fs:edi + 0x2000];p2的位置
	or eax, 3 
    mov [fs:edi + 0x1000], eax
;p2 
    mov ebx, 0x3000;p1的位置
    mov edx, 0x2000;p2自己的位置
    mov ecx, 52
    .loop_p4:
        lea eax, [fs:edi + ebx]       
        or eax, 3
        mov [fs:edi + edx], eax

        add ebx, 0x1000
        add edx, 8
        dec ecx
        cmp ecx, 0
        jne .loop_p4

;p1
    push edi               
    lea edi, [fs:edi + 0x3000];p1自己的位置
    mov eax, 3 ;物理地址
    .loop_page_table:
        mov [fs:edi], eax
        add eax, 0x1000
        add edi, 8
        cmp eax, 0x1a00000       
        jb .loop_page_table
    pop edi

    mov ax, 0x2401
    int 0x15              ; Enalbe A20 地址线。
    cli
    ret

enable_paging:
    ; 启用 pae 和 pge
    mov eax, 10100000b
    mov cr4, eax

    mov eax, PAGE_TABLE
    mov cr3, eax

    ; 设置 EFER MSR（型号特定寄存器）中的长模式位
    mov ecx, 0xC0000080
    rdmsr
    or eax, 0x00000100 
    wrmsr

    ; 启用寻呼和保护
    mov eax, cr0
    or eax, 0x80000001
    mov cr0, eax
    ret

times 1024 - ($-start) db 0

multi_core_boot:    ; 0x8000开始
    jmp 0x0000:ap_main
ap_main:
    mov ax, 0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax

    mov eax, 0x1
    cpuid
    and ebx, 0xff000000
    shr ebx, 24
    mov eax, ebx                 ; 获取cpuid
    cmp eax, 8                   ; 最多支持8C
    jle .start_multi_core_boot
    hlt
    .start_multi_core_boot:
        mov ebx, 7c00h
        .minus_stack_loop:
            cmp eax, 0
            je .do_start_multi_core
            sub eax, 1
            sub ebx, 400h            ; 每个核分配不同的栈，初始1kb
            jmp .minus_stack_loop
        .do_start_multi_core:
            mov esp, ebx
            call enable_paging      ; 开启分页
            lgdt [gdt64.pointer]
            jmp CODE_SEG:long_mode_entry


;将会修改EAX，BX，DS，ES，FS，GS寄存器，iF标志位
;无输入
;输出
设置段寄存器的隐藏部分:
lgdt cs:[Gdtcfg];读入GDT长度及位置
mov eax,cr0
or al,1b
cli;关中断
mov cr0,eax
jmp short ProtectedMode;进入兼容模式

ProtectedMode:;
mov dx,8
mov fs,dx
and al,1111_1110b
mov cr0,eax
jmp 0:RealMode;进入实模式

RealMode:;
mov dx,0
mov fs,dx
sti;开中断
ret


Gdtcfg:;
dw GdtEnd-GdtStart-1;长度-1以忽略后1字节
dd GdtStart;+基地址
GdtStart:;
dq 0h;听说设置个空的段描述符是为了防止从16位实地址模式切换到32位保护模式后忘记设置段寄存器引发的问题。

dw 0FFFFh;段长度
db 0,0,0;基地址
db 92h;10010010b;段属性
db 8Fh;1100_1111b;段属性_段长度1111b
db 0;基地址00h

dw 0FFFFh;段长度
db 0,0,0;基地址
db 92h;10010010b;段属性
db 0;1100_1111b;段属性_段长度1111b
db 0;基地址00h
GdtEnd:;













[BITS 64]
long_mode_entry:
    mov ax,DATA_SEG
    mov ds,ax       ;DS存放数据段描述符。
    mov es,ax
    mov fs,ax
    mov gs,ax
    mov ss,ax
    jmp $