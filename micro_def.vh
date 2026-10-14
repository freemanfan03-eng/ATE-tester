`ifndef _MICRO_DEF_
`define _MICRO_DEF_

// FSM State Encoding
`define ST_IDLE                             3'b000
`define ST_TRIG                             3'b001
`define ST_FETCH                            3'b010
`define	ST_BRAM_DLY			    			3'b011
`define ST_DECODE                           3'b100
`define ST_EXEC                             3'b101
`define ST_WAIT            				    3'b110
`define ST_ERROR                            3'b111
    				   
// ============================================================================
// Pattern Engine Micro-Opcode Definitions (6-bit Width)
// ============================================================================

// ----------------------------------------------------------------------------
// Group 0: [00_xxxx] 程序流与控制类指令 (1-Cycle 快速步进)
// ----------------------------------------------------------------------------
`define OP_NOP_INC      6'b000000    // 空指令 / 顺序步进 (防止未初始化内存破坏DUT)

`define OP_JMP          6'b000001    // 无条件跳转 (PC <- Target_Addr)
`define OP_CJMP         6'b000010    // 条件跳转 (基于 Error/Flag 状态跳转)
`define OP_CALL         6'b000011    // 调用子程序 (Push PC+1 -> Call Stack, JMP)
`define OP_RET          6'b000100    // 子程序返回 (Pop -> PC)

`define OP_LOOP_INIT    6'b000101    // 进入 Loop (Push PC+1 & Loop_Cnt -> Loop Stack)
`define OP_LOOP_END     6'b000110    // 退出/继续 Loop
`define OP_WAIT_TRIG    6'b000111    // 挂起 PC，等待外部硬件触发信号 (用于与仪表握手) [补充]

// ----------------------------------------------------------------------------
// Group 1: [01_xxxx] 波形合成与驱动类指令 (挂起 exec_busy，向外发波)
// ----------------------------------------------------------------------------
`define OP_VECTOR       6'b010000    // 标准双向向量 (驱动 + 期望值比对)
`define OP_DRIVE        6'b010001    // 纯驱动向量 (Pin 脚输出 0/1/Z，关闭比对)
`define OP_COMPARE      6'b010010    // 纯比对向量 (Pin 脚高阻，开启 RX 采样比对)
`define OP_RPT          6'b010011    // 波形周期重复 (重复当前向量 N 次)
`define OP_CAPTURE      6'b010100    // 波形捕获 (不比对，将当前周期的回读波形压入 Capture FIFO) [补充]

// ----------------------------------------------------------------------------
// Group 2: [10_xxxx] 配置、状态与外部同步类指令
// ----------------------------------------------------------------------------
`define OP_RECONF       6'b100000    // 动态更新 Dynamic Mask 寄存器
`define OP_SET_TS       6'b100001    // 动态切换 Timing Set (更改波形频率/边沿)
`define OP_SET_FLAG     6'b100010    // 设置内部状态/掩码 Flag 标志
`define OP_CLR_FLAG     6'b100011    // 清除内部状态/掩码 Flag 标志
`define OP_TRIG_OUT     6'b100100    // 硬件同步脉冲输出 (用于对齐示波器)

// ----------------------------------------------------------------------------
// Group 3: [11_xxxx] Dynamic Match & 异常处理类指令
// ----------------------------------------------------------------------------
`define OP_MATCH_INIT   6'b110000    // 初始化 Match 超时计数器
`define OP_MATCH_WAIT   6'b110001    // 挂起等待 DUT 握手/Match 成功
`define OP_MATCH_ERR    6'b110010    // Match 异常处理分支
`define OP_HALT         6'b111111    // 停止运行 (引擎挂起并置起 test_done)




// -------------------------------------------------------------
// 驱动格式编码 (Drive Format) —— 决定引脚在一个UI内如何驱动电平
// -------------------------------------------------------------
`define FMT_DNRZ 4'd0;  // NRZ:  Non-Return-to-Zero,电平在edge_t1采样后保持整个UI
`define FMT_RZ   4'd1;  // RZ:   Return-to-Zero,窗口外强制拉0
`define FMT_RO   4'd2;  // RO:   Return-to-One,窗口外强制拉1
`define FMT_RTC  4'd3;  // RTC:  Return-to-Complement,edge_t2处翻转到互补电平
`define FMT_SBC  4'd4;  // SBC:  Surrounded-by-Complement,数据前后均为互补电平包围
`define FMT_SBH  4'd5;  // SBH:  Surrounded-by-High,数据前后均被高电平包围
`define FMT_SBL  4'd6;  // SBL:  Surrounded-by-Low, 数据前后均被低电平包围(SBH的镜像)
`define FMT_CLK  4'd7;  // CLK:  纯时钟/选通脉冲,占空比由curr_t1/curr_t2定义
`define FMT_RZ1  4'd8;  // RZ1:  differential正端专用RZ(配合RZ0组成差分对)
`define FMT_RZ0  4'd9;  // RZ0:  differential负端专用RZ(与RZ1互补)
`define FMT_HIZ  4'd10; // HIZ:  真正的高阻态(不驱动,由DUT或负载决定电平)
`define FMT_OFF  4'd11; // OFF:  逻辑关闭,驱动0且可选禁用驱动




// 基础驱动与比较状态编码 (4-bit)
`define ATE_STATE_0    4'b0000 // 驱动低电平 (Drive Low)
`define ATE_STATE_1    4'b0001 // 驱动高电平 (Drive High)
`define ATE_STATE_Z    4'b0010 // 高阻态 / 三态 (Tristate / High-Z)
`define ATE_STATE_H    4'b0011 // 期望比较高电平 (Expect/Compare High)
`define ATE_STATE_L    4'b0100 // 期望比较低电平 (Expect/Compare Low)
`define ATE_STATE_X    4'b0101 // 不关心 / 屏蔽 (Don't Care / Mask)

// 扩展状态（利用 4-bit 的 16 种组合优势，可按需增加）
`define ATE_STATE_V    4'b0110 // 有效数据驱动 (Drive Valid)
`define ATE_STATE_D    4'b0111 // 保持前一个状态 (Data Retain / Hold)
`define ATE_STATE_UP   4'b1000 // 上拉 (Pull-up)
`define ATE_STATE_DN   4'b1001 // 下拉 (Pull-down)
	
`endif


// 依据波形格式真值表，采用 Verilog 二维数组或常量映射定义
// 格式编码与表格内容完全对应：
// Format | D0   | D1  | D2   | D3
// RH     | On   | DD  | DH   | [Off]
// RL     | On   | DD  | DL   | [Off]
// NR     | On   | DD  | Null | [Off]
// ROFF   | On   | DD  | Null |  Off
// SBH    | DH   | DD  | DH   | [Off]
// SBL    | DL   | DD  | DL   | [Off]
// SBC    | DC   | DD  | DC   | [Off]
// STAY   | Null | Null| Null | [Off]
// vector_in[1:0] | 0|drive 0
// vector_in[1:0] | 1|drive 1
// vector_in[1:0] | 2|expect L
// vector_in[1:0] | 3|expect H
/*

OP_VEC    - 驱动/比较一个向量周期(唯一产生波形的指令)
OP_JUMP   - 无条件跳转(对应STIL Goto)
OP_CALL   - 子程序调用(对应STIL Call/Macro)
OP_RET    - 子程序返回(编译器在Call/Macro定义体末尾自动插入)
OP_LOOP   - 固定次数循环开始(对应STIL Loop)
OP_LEND   - 循环结束判断(对应STIL Loop的闭合括号)
OP_MATCH  - 条件等待(对应STIL MatchLoop语义,可能需要拆成独立的循环变体)
OP_HALT   - 停止执行(对应STIL Stop,或Pattern块末尾自动补)
OP_NOP    - 空操作(编译器占位用,STIL本身没有直接对应语句)*/
/*
这 5 条指令属于 Group 1 (波形合成与驱动类)，它们是整个 ATE (自动测试设备) Pattern Engine 的灵魂
与纯控制流（如跳转、NOP）不同，这组指令是唯一会真正与外部被测芯片（DUT）发生物理交互的指令。它们会挂起状态机（拉高 exec_busy），占用至少一个完整的波形周期（如8-UI），并在物理 Pin 脚上产生真实的电压跳变或触发真实的硬件采样。
下面为你重点剖析这 5 条核心指令的作用、硬件行为以及实际应用场景：
1. OP_VECTOR (标准双向向量)
 * 核心作用：在同一个测试周期内，既向 DUT 发送驱动信号，又采样 DUT 返回的信号并与期望值进行比对。
 * 硬件行为：
   * TX (发送端)：驱动器（Pin Driver）根据数据（0/1）输出高低电平。
   * RX (接收端)：在设定的 Strobe（采样沿/窗口）时刻开启比较器，读取引脚上的电平，并与期望数据做硬件异或/比较。如果不匹配，立刻拉高 Error 或 Fail 标志。
 * 应用场景：
   * 双向总线测试：例如 I2C 的 SDA 线，前半个周期 Tester 驱动地址，后半个周期切换为接收模式比对 DUT 返回的 ACK 信号。
   * 全双工接口：例如 SPI，Tester 边发送 MOSI，边比对 MISO 返回的数据。
2. OP_DRIVE (纯驱动向量)
 * 核心作用：强制物理引脚输出指定的电平波形，完全忽略/屏蔽来自 DUT 的任何返回信号。
 * 硬件行为：
   * TX (发送端)：强力驱动 Pin 脚（输出 0、1 或强制拉至特定的驱动电压）。
   * RX (接收端)：比较器（Comparator）的输出被屏蔽（Masked），即便引脚上的实际电压与“期望值”不符，也绝对不会触发 Error 报错。
 * 应用场景：
   * 提供时钟与复位：向芯片提供系统时钟（CLK）或复位信号（RST），这些管脚只需要 Tester 单向发波。
   * 芯片配置/写操作：往芯片的寄存器、EEPROM、Flash 里单纯写入数据时。
3. OP_COMPARE (纯比对向量)
 * 核心作用：Tester 放弃对引脚的电平控制，专门“竖起耳朵”听 DUT 吐出的数据，并实时判别对错。
 * 硬件行为：
   * TX (发送端)：Tester 的引脚驱动器关闭，呈现 高阻态 (High-Z)，把总线控制权完全交给被测芯片。
   * RX (接收端)：在精确的纳秒级采样点（Strobe Time），判断 DUT 输出的是 L (低电平)、H (高电平) 还是 Z (高阻)。如果不符合期望值，则上报 Fail。
 * 应用场景：
   * 数据读取：从芯片 RAM/ROM 中读出数据并校验是否正确。
   * 状态机校验：芯片完成某项任务后，拉高 INT (中断) 或 Ready 信号，Tester 用 Compare 指令捕捉这个瞬间。
4. OP_RPT (波形周期重复)
 * 核心作用：将当前周期的物理波形动作（无论是 Drive 还是 Compare）原封不动地连续执行 N 次。
 * 硬件行为：
   * 状态机停留在 ST_EXEC，不消耗新的 BRAM 地址（PC 不变），而是启动内部的 rpt_cnt 重复计数器。底层波形发生器连续跑 N 个 8-UI 周期。
 * 应用场景：
   * 极度节省 Pattern 内存 (BRAM)：如果要给芯片送 10000 个周期的时钟让它跑内部自测（BIST），不需要在 BRAM 里写 10000 行 OP_DRIVE，只需要 1 行 OP_RPT 加上重复次数即可。
   * 等待芯片初始化：上电后芯片需要 2 毫秒的 Setup 时间，直接 Repeat 空白周期即可。
5. OP_CAPTURE (波形捕获) [高级功能]
 * 核心作用：像“逻辑分析仪”一样工作。它采样 DUT 吐出的数据，不做对错比对，而是直接把真实的 0/1 状态存进内部 FIFO/RAM 中，留给上位机软件慢慢分析。
 * 硬件行为：
   * TX (发送端)：通常配置为高阻 (High-Z)。
   * RX (接收端)：屏蔽比对产生的 Error，触发 Capture FIFO 的 Write Enable，把采样到的 1-bit 或多 bit 真实电平数据压栈保存。
 * 应用场景：
   * ADC 动态测试：测试芯片里的 ADC 模块，需要捕获连续 4096 个周期的正弦波量化输出，传回电脑做 FFT（快速傅里叶变换）分析 SNR、THD。
   * 未知 Bug 调试 (Debug)：当芯片输出完全混乱时，用 Compare 会满屏爆红（Fail），改用 Capture 把芯片吐出的真实报文全抓下来，给工程师看协议哪里跑飞了。
总结：Group 1 指令硬件特征速查表
| 指令 (Opcode) | 占用波形周期 | TX 驱动器 (Pin Driver) | RX 比较器 (Comparator) | 报错 (Error) 机制 | 核心目的 |
|---|---|---|---|---|---|
| OP_VECTOR  | 是 | 激活 | 激活，进行预期比对 | 不匹配则 Fail | 全双工交互 |
| OP_DRIVE   | 是 | 激活 | 屏蔽 (不采样或忽略结果) | 绝对不会 Fail | 单向喂信号 |
| OP_COMPARE | 是 | 关闭 (高阻 Z) | 激活，进行预期比对 | 不匹配则 Fail | 判定芯片好坏 |
| OP_RPT     | 是 (N次) | 保持上一状态不变 | 保持上一状态不变 | 依据基准向量而定 | 压缩指令、延时 |
| OP_CAPTURE | 是 | 关闭 (高阻 Z) | 激活，数据压入 FIFO | 绝对不会 Fail | 收集真实数据供计算 |
这 5 条指令构成了测试机与芯片交流的最基础词汇：说（Drive）、听并检查（Compare）、又说又听（Vector）、重复说（RPT）、只录音不评价（Capture）。
*/