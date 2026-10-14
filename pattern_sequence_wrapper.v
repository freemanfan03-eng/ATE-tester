module pattern_sequence_wrapper #(
    // --- gt_multilane_wrapper 相关参数 ---
	parameter 		  GT_ENABLE					=	"TRUE",//TRUE  FALSE
    parameter integer GT_DATA_WIDTH             = 32,
    parameter         EXAMPLE_SIM_GTRESET_SPEEDUP = "TRUE",
    parameter real    STABLE_CLOCK_PERIOD         = 8.0,
    
    // --- pattern_engine_wrapper 相关参数 ---
    parameter integer NUM_CHANNELS                      = 2,     // 匹配 2 个高速收发通道
    parameter integer MEM_WIDTH                         = 32,
    parameter integer EDGE_WIDTH                        = 16,
    parameter integer PERIOD_WIDTH                      = 24,
	parameter integer PAT_ACT_GROUNP  					= 2
)(
	// =========================================================================
    // --- pattern_engine_wrapper 引入的顶层控制与配置接口 ---
    // =========================================================================
  
    
    // --- 顶层系统时钟与复位 ---
    input  wire                                 sysclk_in,
    input  wire                                 soft_reset_i,
	
	 // 周期与配置
    
    wire [PERIOD_WIDTH-1:0]              period_in,
	wire             					 trigger_sync,
    wire [3:0]                           pattern_index,
    wire [2:0]                           data_src_sel,
    
    // --- 差分参考时钟引脚 ---
    input  wire                                 gt_refclk_pad_p_in,
    input  wire                                 gt_refclk_pad_n_in,

    // --- 高速串行差分收发物理引脚 (2通道) ---
    input  wire [1:0]                           RXP_IN,
    input  wire [1:0]                           RXN_IN,
    output wire [1:0]                           TXP_OUT,
    output wire [1:0]                           TXN_OUT,
	
	output wire        							gt0_txusrclk2_out,
	output wire        							gt1_txusrclk2_out
	
	
   
);
   
   
    wire [NUM_CHANNELS-1:0]              test_fail_arr;
    wire                                 next_mem_req;
    wire [NUM_CHANNELS-1:0]              period_ends;
    wire [NUM_CHANNELS-1:0]              tx_ui_t0;
	
   
    // 宽总线存储器接口
    wire                                	mem_data_vld;
    wire [MEM_WIDTH-1:0]                 	mem_data_in;
   
	wire [32*PAT_ACT_GROUNP-1:0]			pattern_act_cfg;


	/*wire [8*NUM_CHANNELS:0]  							gt0_drpaddr_i = 0;
	wire [15*NUM_CHANNELS:0] 							gt0_drpdi_i = 0;
	wire [15*NUM_CHANNELS:0] 							gt0_drpdo_o;
	wire[NUM_CHANNELS-1:0]        							gt0_drpen_i = 0;
	wire [NUM_CHANNELS-1:0]       							gt0_drprdy_o;
	wire [ NUM_CHANNELS -1:0]      							gt0_drpwe_i = 0;*/
	
	
	// 多通道边沿输入总线
	wire [NUM_CHANNELS*EDGE_WIDTH-1:0]   edge_0_in;
	wire [NUM_CHANNELS*EDGE_WIDTH-1:0]   edge_1_in;
	wire [NUM_CHANNELS*EDGE_WIDTH-1:0]   edge_2_in;
	wire [NUM_CHANNELS*EDGE_WIDTH-1:0]   edge_3_in;
	wire [NUM_CHANNELS*EDGE_WIDTH-1:0]   edge_4_in;
	wire [NUM_CHANNELS*EDGE_WIDTH-1:0]   edge_5_in;
	wire [NUM_CHANNELS*EDGE_WIDTH-1:0]   edge_r0_in;
	wire [NUM_CHANNELS*EDGE_WIDTH-1:0]   edge_r1_in;


	// 高速收发器恢复出来的时钟
	
	wire        					gt0_rxusrclk2_out;
	wire        					gt1_rxusrclk2_out;
	wire  							gt0_tx_ready_out;
	wire 							gt1_tx_ready_out ;    

	



	
	wire [15:0] D0_RCV = 16'd0;
	wire [15:0] D3_RCV = 16'd900;
	//
	wire [15:0] D1_DAT = 16'd10;
	wire [15:0] D2_DAT = 16'd500;
	//
	wire [15:0] D4_DAT = 16'd600;
	wire [15:0] D5_DAT = 16'd800;
	wire [15:0] R0 = 10;
	wire [15:0] R1 = 200;


	wire [16*8-1:0]edge_period_clk = {16'd75,16'd50,16'd95,16'd25,16'd0,16'd0};
	//wire [16*8-1:0]edge_period_nrz = {16'd80,16'd60,16'd80,16'd40,16'd20,16'd0};
	//wire [16*8-1:0]edge_period_nrz = {R1,R0,D5_DAT,D4_DAT,D3_RCV,D2_DAT,D1_DAT,D0_RCV};//D5<-D0
	
	wire [16*8-1:0]edge_period_nrz = {R1,R0,D3_RCV,D5_DAT,D4_DAT,D2_DAT,D1_DAT,D0_RCV};//D5<-D0


	wire [16*8-1:0]edge_period = edge_period_nrz;
	
pattern_sequence #(
    .GT_ENABLE                  (GT_ENABLE),                     // 字符串参数
    .GT_DATA_WIDTH              (GT_DATA_WIDTH),
    .EXAMPLE_SIM_GTRESET_SPEEDUP(EXAMPLE_SIM_GTRESET_SPEEDUP),
    .STABLE_CLOCK_PERIOD        (STABLE_CLOCK_PERIOD),                         // real 类型参数
    .NUM_CHANNELS               (NUM_CHANNELS),
    .MEM_WIDTH                  (MEM_WIDTH),
    .EDGE_WIDTH                 (EDGE_WIDTH),
    .PERIOD_WIDTH               (PERIOD_WIDTH),
	.PAT_ACT_GROUNP				(PAT_ACT_GROUNP)
) u_pattern_sequence (
    // --- pattern_engine_wrapper 接口 ---
    .trigger_sync       (trigger_sync       ),
    .mem_data_vld       (mem_data_vld       ),
    .mem_data_in        (mem_data_in        ),
    .period_ui_in          (period_in          ),
    .pattern_index      (pattern_index      ),
    .pattern_act_cfg    (pattern_act_cfg    ),
    .data_src_sel       (data_src_sel       ),

    .edge_0_in          (edge_period[0 * 16 +: 16]         ),
    .edge_1_in          (edge_period[1 * 16 +: 16]         ),
    .edge_2_in          (edge_period[2 * 16 +: 16]         ),
    .edge_3_in          (edge_period[3 * 16 +: 16]         ),
    .edge_4_in          (edge_period[4 * 16 +: 16]         ),
    .edge_5_in          (edge_period[5 * 16 +: 16]         ),
    .edge_r0_in         (edge_period[6 * 16 +: 16]         ),
    .edge_r1_in         (edge_period[7 * 16 +: 16]         ),

    .test_fail_arr      (test_fail_arr      ),
    .next_mem_req       (next_mem_req       ),
    .period_ends        (period_ends        ),
    .tx_ui_t0           (tx_ui_t0           ),

    // --- 顶层系统时钟与复位 ---
    .sysclk_in          (sysclk_in          ),
    .soft_reset_i       (soft_reset_i       ),

    // --- 差分参考时钟引脚 ---
    .Q0_CLK0_GTREFCLK_PAD_N_IN (gt_refclk_pad_n_in),
    .Q0_CLK0_GTREFCLK_PAD_P_IN (gt_refclk_pad_p_in),

    // --- DRP 接口 (通道0) ---
    .gt0_drpaddr_i      (gt0_drpaddr_i      ),
    .gt0_drpdi_i        (gt0_drpdi_i        ),
    .gt0_drpdo_o        (gt0_drpdo_o        ),
    .gt0_drpen_i        (gt0_drpen_i        ),
    .gt0_drprdy_o       (gt0_drprdy_o       ),
    .gt0_drpwe_i        (gt0_drpwe_i        ),

    // --- 高速串行差分收发物理引脚 (2通道) ---
    .RXP_IN             (RXP_IN             ),
    .RXN_IN             (RXN_IN             ),
    .TXP_OUT            (TXP_OUT            ),
    .TXN_OUT            (TXN_OUT            ),

    // --- 高速收发器恢复时钟 ---
    .gt0_txusrclk2_out  (gt0_txusrclk2_out  ),
    .gt0_rxusrclk2_out  (gt0_rxusrclk2_out  ),
    .gt1_txusrclk2_out  (gt1_txusrclk2_out  ),
    .gt1_rxusrclk2_out  (gt1_rxusrclk2_out  ),
    .gt0_tx_ready_out   (gt0_tx_ready_out   ),
    .gt1_tx_ready_out   (gt1_tx_ready_out   )
);
endmodule