`timescale 1ns / 1ps

module gt_multilane_wrapper #(
    parameter integer GT_DATA_WIDTH              = 32,
    parameter         EXAMPLE_SIM_GTRESET_SPEEDUP = "TRUE",
    parameter real    STABLE_CLOCK_PERIOD         = 8.0,
	 parameter integer NUM_CHANNELS                      = 2
)(
    // --- 系统时钟与复位 ---
    input  wire                         sysclk_in,
    input  wire                         soft_reset_i,
    
    // --- 差分参考时钟 ---
    input  wire                         Q0_CLK0_GTREFCLK_PAD_N_IN,
    input  wire                         Q0_CLK0_GTREFCLK_PAD_P_IN,

	// GT0 内部信号
    input  wire [9*NUM_CHANNELS-1:0]   gtx_drpaddr_i,   // 每个通道 9 位地址
	input  wire [16*NUM_CHANNELS-1:0]  gtx_drpdi_i,     // 每个通道 16 位写入数据
	output wire [16*NUM_CHANNELS-1:0]  gtx_drpdo_o,     // 每个通道 16 位读出数据
	input  wire [NUM_CHANNELS-1:0]     gtx_drpen_i,
	output wire [NUM_CHANNELS-1:0]     gtx_drprdy_o,
	input  wire [NUM_CHANNELS-1:0]     gtx_drpwe_i,
    
    // --- 高速串行差分收发端口 (2通道) ---
    input  wire [1:0]                   RXP_IN,
    input  wire [1:0]                   RXN_IN,
    output wire [1:0]                   TXP_OUT,
    output wire [1:0]                   TXN_OUT,
    
    // --- 用户并行数据接口 (受 GT_DATA_WIDTH 参数控制) ---
    input  wire [GT_DATA_WIDTH-1:0]     gt0_txdata_in,
    output wire [GT_DATA_WIDTH-1:0]     gt0_rxdata_out,
    input  wire [GT_DATA_WIDTH-1:0]     gt1_txdata_in,
    output wire [GT_DATA_WIDTH-1:0]     gt1_rxdata_out,
    
    // --- 仅保留 usrclk2 时钟输出 ---
    output wire                         gt0_txusrclk2_out,
    output wire                         gt0_rxusrclk2_out,
    output wire                         gt1_txusrclk2_out,
    output wire                         gt1_rxusrclk2_out,
    
    // --- 状态指示信号 (resetdone 与 qplllock 相与后输出) ---
    output wire                         gt0_tx_ready_out,
    output wire                         gt1_tx_ready_out
);

    // =========================================================================
    // 内部信号声明
    // =========================================================================
    wire        tied_to_ground_i;
    wire        tied_to_vcc_i;
    wire        drpclk_in_i;

    // 时钟内部接收线（不再输出到顶层）
    wire        gt0_txusrclk_i;
    wire        gt0_rxusrclk_i;
    wire        gt1_txusrclk_i;
    wire        gt1_rxusrclk_i;

    // QPLL 锁定信号
    wire        gt0_qplllock_i;

    
    wire [14:0] gt0_dmonitorout_i;
    wire        gt0_eyescandataerror_i;
    wire        gt0_rxcdrhold_i;
    wire        gt0_rxpmareset_i;
    wire        gt0_rxslide_i;
    wire        gt0_rxresetdone_i;
    wire        gt0_txresetdone_i;
    wire        gt0_txmmcm_lock_i;
    wire        gt0_rxmmcm_lock_i;
    wire        gt0_track_data_i;
    wire        gt0_rxoutclkfabric_i;
    wire        gt0_txoutclkfabric_i;
    wire        gt0_txoutclkpcs_i;
    wire [7:0]  gt0_rxmonitorout_i;

    // GT1 内部信号
    wire [8:0]  gt1_drpaddr_i;
    wire [15:0] gt1_drpdi_i;
    wire [15:0] gt1_drpdo_i;
    wire        gt1_drpen_i;
    wire        gt1_drprdy_i;
    wire        gt1_drpwe_i;
    wire [14:0] gt1_dmonitorout_i;
    wire        gt1_eyescandataerror_i;
    wire        gt1_rxcdrhold_i;
    wire        gt1_rxpmareset_i;
    wire        gt1_rxslide_i;
    wire        gt1_rxresetdone_i;
    wire        gt1_txresetdone_i;
    wire        gt1_txmmcm_lock_i;
    wire        gt1_rxmmcm_lock_i;
    wire        gt1_track_data_i;
    wire        gt1_rxoutclkfabric_i;
    wire        gt1_txoutclkfabric_i;
    wire        gt1_txoutclkpcs_i;
    wire [7:0]  gt1_rxmonitorout_i;

    // =========================================================================
    // 常量与组合逻辑赋值
    // =========================================================================
    assign tied_to_ground_i = 1'b0;
    assign tied_to_vcc_i    = 1'b1;
    assign drpclk_in_i      = sysclk_in;
    
    // 数据有效性跟随重置完成状态
    assign gt0_track_data_i = gt0_txresetdone_i && gt0_rxresetdone_i;
    assign gt1_track_data_i = gt1_txresetdone_i && gt1_rxresetdone_i;

    // 状态信号：txresetdone 与 qplllock 相与后输出
    assign gt0_tx_ready_out = gt0_txresetdone_i && gt0_qplllock_i;
    assign gt1_tx_ready_out = gt1_txresetdone_i && gt0_qplllock_i;

    // 数据位宽适配转换（高位补零/截断）
    wire [63:0] gt0_txdata_wide;
    wire [63:0] gt0_rxdata_wide;
    wire [63:0] gt1_txdata_wide;
    wire [63:0] gt1_rxdata_wide;

    assign gt0_txdata_wide = {{(64-GT_DATA_WIDTH){1'b0}}, gt0_txdata_in};
    assign gt0_rxdata_out  = gt0_rxdata_wide[GT_DATA_WIDTH-1:0];

    assign gt1_txdata_wide = {{(64-GT_DATA_WIDTH){1'b0}}, gt1_txdata_in};
    assign gt1_rxdata_out  = gt1_rxdata_wide[GT_DATA_WIDTH-1:0];

    // =========================================================================
    // GT Wizard 支持层模块实例化
    // =========================================================================
    gtwizard_0_support #(
        .EXAMPLE_SIM_GTRESET_SPEEDUP (EXAMPLE_SIM_GTRESET_SPEEDUP),
        .STABLE_CLOCK_PERIOD         (STABLE_CLOCK_PERIOD)
    )
    gtwizard_0_support_i (
        .soft_reset_tx_in            (soft_reset_i),
        .soft_reset_rx_in            (soft_reset_i),
        .dont_reset_on_data_error_in (tied_to_ground_i),
        
        .q0_clk0_gtrefclk_pad_n_in   (Q0_CLK0_GTREFCLK_PAD_N_IN),
        .q0_clk0_gtrefclk_pad_p_in   (Q0_CLK0_GTREFCLK_PAD_P_IN),
        
        .gt0_tx_mmcm_lock_out        (gt0_txmmcm_lock_i),
        .gt0_rx_mmcm_lock_out        (gt0_rxmmcm_lock_i),
        .gt0_tx_fsm_reset_done_out   (), // 内部悬空或由内部接收
        .gt0_rx_fsm_reset_done_out   (),
        .gt0_data_valid_in           (gt0_track_data_i),
        
        .gt1_tx_mmcm_lock_out        (gt1_txmmcm_lock_i),
        .gt1_rx_mmcm_lock_out        (gt1_rxmmcm_lock_i),
        .gt1_tx_fsm_reset_done_out   (),
        .gt1_rx_fsm_reset_done_out   (),
        .gt1_data_valid_in           (gt1_track_data_i),

        .gt0_txusrclk_out            (gt0_txusrclk_i),
        .gt0_txusrclk2_out           (gt0_txusrclk2_out),
        .gt0_rxusrclk_out            (gt0_rxusrclk_i),
        .gt0_rxusrclk2_out           (gt0_rxusrclk2_out),

        .gt1_txusrclk_out            (gt1_txusrclk_i),
        .gt1_txusrclk2_out           (gt1_txusrclk2_out),
        .gt1_rxusrclk_out            (gt1_rxusrclk_i),
        .gt1_rxusrclk2_out           (gt1_rxusrclk2_out),

        // _____________________ GT0 (X1Y0) _____________________
        .gt0_drpaddr_in              (gtx_drpaddr_i[0*9 +: 9]),
        .gt0_drpdi_in                (gtx_drpdi_i[0*16 +: 16]),
        .gt0_drpdo_out               (gtx_drpdo_o[0*16 +: 16]),
        .gt0_drpen_in                (gtx_drpen_i[0]),
        .gt0_drprdy_out              (gtx_drprdy_o[0]),
        .gt0_drpwe_in                (gtx_drpwe_i[0]),
        .gt0_dmonitorout_out         (gt0_dmonitorout_i),
        .gt0_eyescanreset_in         (tied_to_ground_i),
        .gt0_rxuserrdy_in            (tied_to_vcc_i),
        .gt0_eyescandataerror_out    (gt0_eyescandataerror_i),
        .gt0_eyescantrigger_in       (tied_to_ground_i),
        .gt0_rxcdrhold_in            (gt0_rxcdrhold_i),
        .gt0_rxdata_out              (gt0_rxdata_wide),
        .gt0_gtxrxp_in               (RXP_IN[0]),
        .gt0_gtxrxn_in               (RXN_IN[0]),
        .gt0_rxdfelpmreset_in        (tied_to_ground_i),
        .gt0_rxmonitorout_out        (gt0_rxmonitorout_i),
        .gt0_rxmonitorsel_in         (2'b00),
        .gt0_rxoutclkfabric_out      (gt0_rxoutclkfabric_i),
        .gt0_gtrxreset_in            (tied_to_ground_i),
        .gt0_rxpmareset_in           (gt0_rxpmareset_i),
        //.gt0_rxslide_in              (gt0_rxslide_i),
        .gt0_rxresetdone_out         (gt0_rxresetdone_i),
        .gt0_gttxreset_in            (tied_to_ground_i),
        .gt0_txuserrdy_in            (tied_to_vcc_i),
        .gt0_txdata_in               (gt0_txdata_wide),
        .gt0_gtxtxn_out              (TXN_OUT[0]),
        .gt0_gtxtxp_out              (TXP_OUT[0]),
        .gt0_txoutclkfabric_out      (gt0_txoutclkfabric_i),
        .gt0_txoutclkpcs_out         (gt0_txoutclkpcs_i),
        .gt0_txresetdone_out         (gt0_txresetdone_i),

        // _____________________ GT1 (X1Y1) _____________________
        .gt1_drpaddr_in              (gtx_drpaddr_i[1*9 +: 9]),
        .gt1_drpdi_in                (gtx_drpdi_i[1*16 +: 16]),
        .gt1_drpdo_out               (gtx_drpdo_o[1*16 +: 16]),
        .gt1_drpen_in                (gtx_drpen_i[1]),
        .gt1_drprdy_out              (gtx_drprdy_o[1]),
        .gt1_drpwe_in                (gtx_drpwe_i[1]),
        .gt1_dmonitorout_out         (gt1_dmonitorout_i),
        .gt1_eyescanreset_in         (tied_to_ground_i),
        .gt1_rxuserrdy_in            (tied_to_vcc_i),
        .gt1_eyescandataerror_out    (gt1_eyescandataerror_i),
        .gt1_eyescantrigger_in       (tied_to_ground_i),
        .gt1_rxcdrhold_in            (gt1_rxcdrhold_i),
        .gt1_rxdata_out              (gt1_rxdata_wide),
        .gt1_gtxrxp_in               (RXP_IN[1]),
        .gt1_gtxrxn_in               (RXN_IN[1]),
        .gt1_rxdfelpmreset_in        (tied_to_ground_i),
        .gt1_rxmonitorout_out        (gt1_rxmonitorout_i),
        .gt1_rxmonitorsel_in         (2'b00),
        .gt1_rxoutclkfabric_out      (gt1_rxoutclkfabric_i),
        .gt1_gtrxreset_in            (tied_to_ground_i),
        .gt1_rxpmareset_in           (gt1_rxpmareset_i),
       // .gt1_rxslide_in              (gt1_rxslide_i),
        .gt1_rxresetdone_out         (gt1_rxresetdone_i),
        .gt1_gttxreset_in            (tied_to_ground_i),
        .gt1_txuserrdy_in            (tied_to_vcc_i),
        .gt1_txdata_in               (gt1_txdata_wide),
        .gt1_gtxtxn_out              (TXN_OUT[1]),
        .gt1_gtxtxp_out              (TXP_OUT[1]),
        .gt1_txoutclkfabric_out      (gt1_txoutclkfabric_i),
        .gt1_txoutclkpcs_out         (gt1_txoutclkpcs_i),
        .gt1_txresetdone_out         (gt1_txresetdone_i),

        // ________________________ COMMON PORTS ________________________
        .gt0_qplllock_out            (gt0_qplllock_i), // 提取 QPLL 锁定信号用于内部相与
        .gt0_qpllrefclklost_out      (),
        .gt0_qplloutclk_out          (),
        .gt0_qplloutrefclk_out       (),
        .sysclk_in                   (drpclk_in_i)
    );

endmodule