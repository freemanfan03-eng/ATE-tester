// =========================================================================
// ate_waveform_channel_top.v - ATE 高速数字通道顶层例化模块
// =========================================================================
module pat_gen #(
    parameter integer DATA_WIDTH = 64,
    parameter integer EDGE_WIDTH   = 16,     
    parameter integer PERIOD_WIDTH = 24,
	parameter integer PAT_ACT_GROUNP = 2    
   
)(
    input  wire                         clk,
    input  wire                         rst_n,
    
    // 全局流控与周期接口
    input  wire                         trigger_sync,
    input  wire [PERIOD_WIDTH-1:0]      period_ui_in,
	input  wire [31*PAT_ACT_GROUNP:0]					pattern_act_cfg,
	input wire [2:0]             		data_src_sel,        // <--- 外部控制端口
	input wire [3:0]             		pattern_index,       // WAVESET 行选择
    
    
    // 边沿时间戳输入 (来自上游 Waveset Decoder)
    input  wire [EDGE_WIDTH-1:0]                  act_edge_1_ui, act_edge_2_ui, 
    input  wire [EDGE_WIDTH-1:0]                  act_edge_3_ui, act_edge_4_ui, // 驱动边沿 (Edge 1~4)
    input  wire [EDGE_WIDTH-1:0]                  act_edge_0_ui, act_edge_5_ui, // 接收使能边沿 (Edge 0, 5)
    input  wire [EDGE_WIDTH-1:0]                  cmp_edge_r0_ui, cmp_edge_r1_ui, // 比对窗口边沿 (R0, R1)
    
    // 期望数据输入
    input  wire [DATA_WIDTH-1:0]        expect_data_in,
    
    // 接口 1：输出给 GT Transceiver (发送与驱动控制)
    output wire                         next_vector_req,
    output wire [DATA_WIDTH-1:0]        drv_parallel_data,
    output wire [DATA_WIDTH-1:0]        rcv_parallel_data,
    
    // 接口 2：来自 GT Transceiver 的硬件采样回传数据 (接收通道)
    input  wire [DATA_WIDTH-1:0]        cmp_h_in,
    input  wire [DATA_WIDTH-1:0]        cmp_l_in,
    
    // 接口 3：最终比对结果输出
    output wire [DATA_WIDTH-1:0]        pass_fail_vector, // 按位比对结果 (1: Pass, 0: Fail)
    output wire                         channel_fail_flag // 通道总体 Fail 标志
);

    // =========================================================================
    // 内部连线声明
    // =========================================================================
    // 1. Formatter 输出的原始掩码与请求

	wire [DATA_WIDTH-1:0] raw_cmp_win_mask;
	wire [2*DATA_WIDTH-1:0] raw_cmp_op_code;
	//wire [2*DATA_WIDTH-1:0] raw_cmp_mode_out;

   // wire                  drv_req, rcv_req, cmp_req;
    
    // 2. 经过 waveform_data_delay（延迟补偿）后的对齐信号
    wire [DATA_WIDTH-1:0] delayed_rcv_parallel;
    wire [DATA_WIDTH-1:0] delayed_cmp_h_mask;
    wire [DATA_WIDTH-1:0] delayed_cmp_l_mask;
    wire [DATA_WIDTH-1:0] delayed_expect_data;
	
	
	wire  act_e0, act_e1, act_e2, act_e3, act_e4, act_e5, act_r0_en, act_r1_en,act_cmp_win_en;
	wire [1:0] act_r0_mode,act_r1_mode;
	(* dont_touch="true" *)
	waveset_decoder#(
		.PAT_ACT_GROUNP(PAT_ACT_GROUNP)
	)u_waveset_dec
	(
        .pattern_index(pattern_index),
		.pattern_act_cfg(pattern_act_cfg),
        .data_src_sel(data_src_sel),
        .act_e0(act_e0),
        .act_e1(act_e1),
        .act_e2(act_e2),
        .act_e3(act_e4),
        .act_e4(act_e5),
        .act_e5(act_e3),
        .act_r0_en(act_r0_en),
		.act_r0_mode(act_r0_mode),
		.act_cmp_win_en(act_cmp_win_en),
        .act_r1_en(act_r1_en),
		.act_r1_mode(act_r1_mode)
    );
	

    // =========================================================================
    // 1. 例化驱动数据生成器 (drv_formatter)
    // =========================================================================
	(* dont_touch="true" *)
    drv_formatter #(
        .DATA_WIDTH(DATA_WIDTH),
        .PERIOD_WIDTH(PERIOD_WIDTH)
    ) u_drv_formatter (
        .clk(clk),
        .rst_n(rst_n),
        .trigger_sync(trigger_sync),
        .period_ui_in(period_ui_in),
        .act_edge_1_ui(act_edge_1_ui),
        .act_edge_2_ui(act_edge_2_ui),
        .act_edge_3_ui(act_edge_3_ui),
        .act_edge_4_ui(act_edge_4_ui),
		.act_e1(act_e1), 
		.act_e2(act_e2),  
		.act_e3(act_e4),  
		.act_e4(act_e5), 
        .next_vector_req(next_vector_req),
        .drv_parallel_data(drv_parallel_data)
    );

    // =========================================================================
    // 2. 例化接收驱动使能生成器 (rcv_formatter)
    // =========================================================================
	(* dont_touch="true" *)
    rcv_formatter #(
        .DATA_WIDTH(DATA_WIDTH),
        .PERIOD_WIDTH(PERIOD_WIDTH)
    ) u_rcv_formatter (
        .clk(clk),
        .rst_n(rst_n),
        .trigger_sync(trigger_sync),
        .period_ui_in(period_ui_in),
        .act_edge_0_ui(act_edge_0_ui),
        .act_edge_5_ui(act_edge_5_ui),
		.act_e0(act_e0), 
		.act_e5(act_e3),
        .next_vector_req(rcv_req),
        .rcv_parallel_data(rcv_parallel_data)
    );



	wire ser_out_drv;

	pat_data_deserializer #(
		.DATA_WIDTH (64),
		.DELAY_TAPS(10)
	)pat_data_deserializer_drv
	(	 .clk(clk),
        .rst_n(rst_n),
		.trigger_sync(trigger_sync),
		.pat_parallel_data(drv_parallel_data), // 64-bit 并行输入数据
		.ser_out(ser_out_drv)            // 严格的 1-bit 位宽输出
		
		
	);
	
	wire ser_out_rcv;

	pat_data_deserializer #(
		.DATA_WIDTH (64),
		.DELAY_TAPS(10)
	)pat_data_deserializer_rcv
	( 	.clk(clk),
        .rst_n(rst_n),
		.trigger_sync(trigger_sync),
		.pat_parallel_data(rcv_parallel_data), // 64-bit 并行输入数据
		.ser_out(ser_out_rcv)            // 严格的 1-bit 位宽输出
		
	);


			
    // =========================================================================
    // 3. 例化比对窗口掩码生成器 (cmp_formatter)
    // =========================================================================
	
	(* dont_touch="true" *)
    cmp_formatter #(
        .DATA_WIDTH(DATA_WIDTH),
        .EDGE_WIDTH(EDGE_WIDTH),
		.PERIOD_WIDTH(PERIOD_WIDTH),
		.STROBE_WIDTH_UI(4)
    ) u_cmp_formatter (
        .clk(clk),
        .rst_n(rst_n),
        .trigger_sync(trigger_sync),
        .period_ui_in(period_ui_in),
        
		.cmp_edge_r0_ui(cmp_edge_r0_ui),
        .cmp_edge_r1_ui(cmp_edge_r1_ui),
		.act_r0(act_r0_en),
		.act_r1(act_r1_en),
		.act_r0_mode(act_r0_mode),
		.act_r1_mode(act_r1_mode),
		.act_cmp_win_en(act_cmp_win_en),
        .next_vector_req(cmp_req),
     
	    .cmp_win_mask(raw_cmp_win_mask),
		.cmp_op_code(raw_cmp_op_code)
    );
	
	
	wire ser_out_cmp;

	pat_data_deserializer #(
		.DATA_WIDTH (64),
		.DELAY_TAPS(10)
	)pat_data_deserializer_cmp_win
	( 	.clk(clk),
        .rst_n(rst_n),
		.trigger_sync(trigger_sync),
		.pat_parallel_data(raw_cmp_win_mask), // 64-bit 并行输入数据
		.ser_out(ser_out_cmp)            // 严格的 1-bit 位宽输出
		
	);



	

    // =========================================================================
    // 4. 例化延迟补偿模块 (waveform_data_delay)
    // =========================================================================
	
	wire [DATA_WIDTH-1:0]     cmp_win_mask_dly;     // 高阈值比对掩码延时
    wire [2*DATA_WIDTH-1:0]   cmp_op_code_dly;       // 2-bit 比对格式 (00/01: 标逻, 10: M, 11: V)
	   (* dont_touch="true" *)
	cmp_latency_compensator #(
            .DATA_WIDTH       (DATA_WIDTH),
            .MAX_DELAY_CYCLES (64)
        ) u_cmp_latency_compensator (
            .clk                (clk),
            .rst_n              (rst_n),
			.link_ready(1),
            .cfg_latency_cycles (0), // 
			.cfg_latency_ui(0),
            .emergency_stop     (0),
            
            // 输入：来自第 ch 通道的 cmp_formatter
            .in_cmp_win_mask    (raw_cmp_win_mask),
            .in_cmp_op_code     (raw_cmp_op_code),
     
            
            // 输出：送往第 ch 通道的 waveform_comparator
            .out_cmp_win_mask     (cmp_win_mask_dly),
            .out_cmp_op_code      (cmp_op_code_dly)
            
        );

    // =========================================================================
    // 5. 例化波形比对器 (waveform_comparator)
    // =========================================================================
	   (* dont_touch="true" *)
    compare_engine #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_compare_engine (
        .clk(clk),
        .rst_n(rst_n),
		//.glitch_filter_limit(0),
		
        .cmp_win_mask(cmp_win_mask_dly),
		.cmp_op_code(cmp_op_code_dly),
        .cmp_h_in(cmp_h_in),
        .cmp_l_in(cmp_l_in),
		
        .bit_pass_vector(pass_fail_vector),
        .channel_fail_flag(channel_fail_flag),
        .fail_capture_reg() // 预留错误捕获寄存器接口
    );
	// =========================================================================
	// 6. capture_engine 模块例化
	// =========================================================================
	  (* dont_touch="true" *)
	capture_engine #(
		.BRAM_DATA_WIDTH        ( 128 ),    // 64-UI 数据宽度
		.ADDR_WIDTH        ( 12   )     // 12-bit 地址宽度
	) u_capture_engine (
		.clk               ( clk                  ),
		.rst_n             ( rst_n                ),

		// --- 1. 底层双比较器物理采样信号输入 ---
		.cmp_l_in          ( cmp_l_in          ), // 绑定物理低电平比较线
		.cmp_h_in          ( cmp_h_in          ), // 绑定物理高电平比较线

		// --- 2. 掩码输入 (共享 cmp_formatter 解算的视窗) ---
		.capture_win_mask  ( cmp_win_mask_dly         ), // 用于 2'b01 模式下的视窗数据过滤

		// --- 3. 控制与触发配置接口 ---
		//.trigger_sync      ( trigger_sync     ), // 绑定图形起始同步信号
		.capture_start       ( 1          ), // 绑定软件使能控制位
		.test_done      ( 0   ), // 绑定 compare_engine 的 Fail 输出
	

		// --- 4. Trace RAM / BRAM 写入接口 ---
		.ram_wr_en         ( trace_ram_wr_en      ), // 驱动 BRAM 写使能端口
		.ram_wr_addr       ( trace_ram_wr_addr    ), // 驱动 BRAM 写地址端口
		.ram_wr_data       ( trace_ram_wr_data    ) // 驱动 BRAM 写数据端口 (128-bit)

		// --- 5. 状态输出映射 ---
	//	.capture_active    ( cap_active_flag      ), // 映射至状态寄存器或 LED 观察
	//	.capture_done      ( cap_done_flag        )  // 映射至中断或状态寄存器
	);

	// =========================================================================
    // 7. TMU 测量引擎例化 (tmu_meas_engine)
    // =========================================================================
	   (* dont_touch="true" *)
	gt_tmu_meas_engine #(
		.DATA_WIDTH          ( 64          ),
		.IDX_WIDTH           ( 6           ),
		.TS_WIDTH            ( 40          ),
		.CYC_WIDTH           ( 32          )
	) u_gt_tmu_meas_engine 
	(
		.clk                 ( clk                     ), // 通道系统时钟
		.rst_n               ( rst_n                   ), // 全局复位信号

		// 控制触发接口
		.start_meas          ( tmu_start_meas          ), // 高电平启动单次测量

		// 包络与物理数据流输入 (联合逻辑译码)
		.drv_parallel_data   ( expect_data_dly       ), // 驱动 start/stop 的窗口控制包络流
		.cmp_l_in            ( cmp_l_in               ), // 驱动 cnt 计数/上升沿提取的 Low 阈值流
		.cmp_h_in            ( cmp_h_in               ), // 驱动下降沿/脉宽提取的 High 阈值流

		// 硬件原子数据输出
		.high_pulse_ui_count (  ), // 输出：脉冲 UI 长度
		.total_ui_count      (       ), // 输出：start -> stop 跨越的总 UI
		.actual_cycles       (        ), // 输出：窗口内实际锁定的周期数 cnt

		// 状态标志
		.meas_busy           (            ), // 输出：1 表示测量进行中
		.meas_done           (            )  // 输出：1 表示测量完毕，数据已锁定
	);
	
endmodule