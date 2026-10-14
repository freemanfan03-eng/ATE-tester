

module gtwizard_top #
(
	parameter GT_DATA_WIDTH = 32,
    parameter EXAMPLE_SIM_GTRESET_SPEEDUP = "TRUE",   // simulation setting for GT SecureIP model
    parameter STABLE_CLOCK_PERIOD         = 20
)
(
    // ----------------------------------
    // 系统时钟与全局复位
    // ----------------------------------
    (* X_INTERFACE_INFO      = "xilinx.com:signal:clock:1.0 SYS_CLK CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME SYS_CLK, FREQ_HZ 100000000" *)
    input  wire sysclk_i,            // 系统时钟，用于DRP等逻辑

    (* X_INTERFACE_INFO      = "xilinx.com:signal:reset:1.0 SYS_RST RST" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME SYS_RST, POLARITY ACTIVE_HIGH" *)
    input  wire soft_reset_i,        // 软复位信号，可来自用户逻辑或按钮

    // -------------------------- Channel - DRP Ports --------------------------
   // =========================================================================
    // Xilinx 标准 DRP (Dynamic Reconfiguration Port) 总线接口声明
    // =========================================================================
// =========================================================================
    // Xilinx 官方标准 DRP (Dynamic Reconfiguration Port) 总线接口修正版
    // =========================================================================
    (* X_INTERFACE_INFO = "xilinx.com:interface:drp_rtl:1.0 drp DADDR" *) // 修正：必须是 DADDR
    input  wire [8:0]  gt0_drpaddr_i,
    
    (* X_INTERFACE_INFO = "xilinx.com:interface:drp_rtl:1.0 drp DI" *)    // 正确
    input  wire [15:0] gt0_drpdi_i,
    
    (* X_INTERFACE_INFO = "xilinx.com:interface:drp_rtl:1.0 drp DO" *)    // 正确
    output wire [15:0] gt0_drpdo_o,
    
    (* X_INTERFACE_INFO = "xilinx.com:interface:drp_rtl:1.0 drp DEN" *)   // 修正：必须是 DEN
    input  wire        gt0_drpen_i,
    
    (* X_INTERFACE_INFO = "xilinx.com:interface:drp_rtl:1.0 drp DRDY" *)  // 修正：必须是 DRDY
    output wire        gt0_drprdy_o,
    
    (* X_INTERFACE_INFO = "xilinx.com:interface:drp_rtl:1.0 drp DWE" *)   // 修正：必须是 DWE
    input  wire        gt0_drpwe_i,
    // =========================================================================
    // =========================================================================

    // ----------------- Transmit Ports - TX Data Path interface -----------------
    output wire        txoutclkfabric_o,
	output wire        gt0_txusrclk_o,
	input  wire        gt0_txdata_valid_i,
    input  wire [GT_DATA_WIDTH-1:0] gt0_txdata_i,

    // ----------------- Receive Ports - FPGA RX interface Ports -----------------
    output wire        rxoutclkfabric_o,
	output wire        gt0_rxusrclk_o,
	output  wire       gt0_rxdata_valid_o,
    output wire [GT_DATA_WIDTH-1:0] gt0_rxdata_o,

    // ----------------------------------
    // GT 收发器物理引脚
    // ----------------------------------
    (* X_INTERFACE_INFO = "xilinx.com:interface:diff_clock_rtl:1.0 GT_DIFF_REFCLK CLK_P" *)
    input  wire Q0_CLK1_GTREFCLK_PAD_P_IN,     // GT参考时钟差分输入P
    (* X_INTERFACE_INFO = "xilinx.com:interface:diff_clock_rtl:1.0 GT_DIFF_REFCLK CLK_N" *)
    input  wire Q0_CLK1_GTREFCLK_PAD_N_IN,     // GT参考时钟差分输入N

    (* X_INTERFACE_INFO = "xilinx.com:display_aurora:GT_Serial_Transceiver_Pins_TX_rtl:1.0 GT_SERIAL_TX TX_P" *)
    output wire TXP_OUT,           // GT发送差分输出P
    (* X_INTERFACE_INFO = "xilinx.com:display_aurora:GT_Serial_Transceiver_Pins_TX_rtl:1.0 GT_SERIAL_TX TX_N" *)
    output wire TXN_OUT,           // GT发送差分输出N

    (* X_INTERFACE_INFO = "xilinx.com:display_aurora:GT_Serial_Transceiver_Pins_RX_rtl:1.0 GT_SERIAL_RX RX_P" *)
    input  wire RXP_IN,           // GT接收差分输入P
    (* X_INTERFACE_INFO = "xilinx.com:display_aurora:GT_Serial_Transceiver_Pins_RX_rtl:1.0 GT_SERIAL_RX RX_N" *)
    input  wire RXN_IN,           // GT接收差分输入N

    // ----------------------------------
    // 状态与调试输出
    // ----------------------------------
    output wire tx_fsm_reset_done_o,  // 发送状态机复位完成
    output wire rx_fsm_reset_done_o,  // 接收状态机复位完成
    output wire tx_pll_locked_o,      // 发送PLL锁定指示
    output wire rx_pll_locked_o,      // 接收PLL锁定指示
    output wire rx_byte_aligned_o,    // 接收字节对齐完成

    // ----------- Transmit Ports - TX Initialization and Reset Ports -----------
    output wire gt_txresetdone_o,
    output wire gt_rxresetdone_o     
);

//**************************** Wire Declarations ******************************//
    //------------------------ GT Wrapper Wires ------------------------------
    //________________________________________________________________________
    //________________________________________________________________________
    //GT0  (X1Y0)
    //------------------------------- CPLL Ports -------------------------------
    wire            gt0_cpllfbclklost_i;
    wire            gt0_cplllock_i;
    wire            gt0_cpllrefclklost_i;
    wire            gt0_cpllreset_i;

    //------------------------- Digital Monitor Ports --------------------------
    wire    [7:0]   gt0_dmonitorout_i;
    //------------------- RX Initialization and Reset Ports --------------------
    wire            gt0_eyescanreset_i;
    wire            gt0_rxuserrdy_i;
    //------------------------ RX Margin Analysis Ports ------------------------
    wire            gt0_eyescandataerror_i;
    wire            gt0_eyescantrigger_i;
   
    //------------------------- Receive Ports - RX AFE -------------------------
    wire            gt0_gtxrxp_i;
    //---------------------- Receive Ports - RX AFE Ports ----------------------
    wire            gt0_gtxrxn_i;
    //------------------- Receive Ports - RX Equalizer Ports -------------------
    wire            gt0_rxdfelpmreset_i;
    wire    [6:0]   gt0_rxmonitorout_i;
    wire    [1:0]   gt0_rxmonitorsel_i;
    //------------- Receive Ports - RX Fabric Output Control Ports -------------
    wire            gt0_rxoutclk_i;
    wire            gt0_rxoutclkfabric_o;
    //----------- Receive Ports - RX Initialization and Reset Ports ------------
    wire            gt0_gtrxreset_i;
    wire            gt0_rxpmareset_i;
    //------------ Receive Ports -RX Initialization and Reset Ports ------------
   // wire            gt0_rxresetdone_i;
    //------------------- TX Initialization and Reset Ports --------------------
    wire            gt0_gttxreset_i;
    wire            gt0_txuserrdy_i;
  
    //-------------- Transmit Ports - TX Driver and OOB signaling --------------
    wire            gt0_gtxtxn_i;
    wire            gt0_gtxtxp_i;
    //--------- Transmit Ports - TX Fabric Clock Output Control Ports ----------
    wire            gt0_txoutclk_i;
    wire            gt0_txoutclkfabric_o;
    wire            gt0_txoutclkpcs_i;
    

    //____________________________COMMON PORTS________________________________
    //-------------------- Common Block  - Ref Clock Ports ---------------------
    wire            gt0_gtrefclk1_common_i;
    //----------------------- Common Block - QPLL Ports ------------------------
    wire            gt0_qplllock_i;
    wire            gt0_qpllrefclklost_i;
    wire            gt0_qpllreset_i;


    //----------------------------- Global Signals -----------------------------

    wire            drpclk_in_i;
    wire            DRPCLK_IN;
    wire            gt0_tx_system_reset_c;
    wire            gt0_rx_system_reset_c;
    wire            tied_to_ground_i;
    wire    [63:0]  tied_to_ground_vec_i;
    wire            tied_to_vcc_i;
    wire    [7:0]   tied_to_vcc_vec_i;
    wire            GTTXRESET_IN;
    wire            GTRXRESET_IN;
    wire            CPLLRESET_IN;
    wire            QPLLRESET_IN;

     //--------------------------- User Clocks ---------------------------------
     wire            gt0_txusrclk_i; 
     wire            gt0_txusrclk2_i; 
     wire            gt0_rxusrclk_i; 
     wire            gt0_rxusrclk2_i; 
 
    //--------------------------- Reference Clocks ----------------------------
    
    wire            q0_clk1_refclk_i;


    //--------------------- Frame check/gen Module Signals --------------------
    wire            gt0_matchn_i;
    
    wire    [5:0]   gt0_txcharisk_float_i;
   
    wire    [15:0]  gt0_txdata_float16_i;
    wire    [47:0]  gt0_txdata_float_i;
    
    
    wire            gt0_block_sync_i;
    wire            gt0_track_data_i = 1;
    wire    [7:0]   gt0_error_count_i;
    wire            gt0_frame_check_reset_i;
    wire            gt0_inc_in_i;
    wire            gt0_inc_out_i;
    wire    [15:0]  gt0_unscrambled_data_i;

    wire            reset_on_data_error_i;
    wire            track_data_out_i;
	
	
	
	 assign tied_to_ground_i             = 1'b0;
	 // assign tied_to_vcc_i                = gt_txresetdone_o;//1'b1;
	 assign  gt0_rxpmareset_i                     =  tied_to_ground_i;
	 
	 assign txoutclkfabric_o = gt0_txoutclkfabric_o;
	 assign rxoutclkfabric_o = gt0_rxoutclkfabric_o;
	//
	gtwizard_0_support #
    (
        .EXAMPLE_SIM_GTRESET_SPEEDUP    (EXAMPLE_SIM_GTRESET_SPEEDUP),
        .STABLE_CLOCK_PERIOD            (STABLE_CLOCK_PERIOD)
    )
    gtwizard_0_support_i
    (
		.soft_reset_tx_in               (soft_reset_i),
		.soft_reset_rx_in               (soft_reset_i),
		.dont_reset_on_data_error_in    (tied_to_ground_i),
		.q0_clk1_gtrefclk_pad_n_in(Q0_CLK1_GTREFCLK_PAD_N_IN),
		.q0_clk1_gtrefclk_pad_p_in(Q0_CLK1_GTREFCLK_PAD_P_IN),
		.gt0_tx_fsm_reset_done_out      (gt0_txfsmresetdone_i),
		.gt0_rx_fsm_reset_done_out      (gt0_rxfsmresetdone_i),
		.gt0_data_valid_in              (gt0_track_data_i),

		.gt0_txusrclk_out(gt0_txusrclk_o),
		.gt0_txusrclk2_out(gt0_txusrclk2_i),
		.gt0_rxusrclk_out(gt0_rxusrclk_o),
		.gt0_rxusrclk2_out(gt0_rxusrclk2_i),


        //_____________________________________________________________________
        //_____________________________________________________________________
        //GT0  (X1Y0)

        //-------------------------- Channel - DRP Ports  --------------------------
        .gt0_drpaddr_in                 (gt0_drpaddr_i),
        .gt0_drpdi_in                   (gt0_drpdi_i),
        .gt0_drpdo_out                  (gt0_drpdo_i),
        .gt0_drpen_in                   (gt0_drpen_i),
        .gt0_drprdy_out                 (gt0_drprdy_i),
        .gt0_drpwe_in                   (gt0_drpwe_i),
        //------------------------- Digital Monitor Ports --------------------------
        .gt0_dmonitorout_out            (gt0_dmonitorout_i),
        //------------------- RX Initialization and Reset Ports --------------------
        .gt0_eyescanreset_in            (tied_to_ground_i),
        .gt0_rxuserrdy_in               (tied_to_vcc_i),
        //------------------------ RX Margin Analysis Ports ------------------------
        .gt0_eyescandataerror_out       (gt0_eyescandataerror_i),
        .gt0_eyescantrigger_in          (tied_to_ground_i),
        //---------------- Receive Ports - FPGA RX interface Ports -----------------
        .gt0_rxdata_out                 (gt0_rxdata_o),
        //------------------------- Receive Ports - RX AFE -------------------------
        .gt0_gtxrxp_in                  (RXP_IN),
        //---------------------- Receive Ports - RX AFE Ports ----------------------
        .gt0_gtxrxn_in                  (RXN_IN),
        //------------------- Receive Ports - RX Equalizer Ports -------------------
        .gt0_rxdfelpmreset_in           (tied_to_ground_i),
        .gt0_rxmonitorout_out           (gt0_rxmonitorout_i),
        .gt0_rxmonitorsel_in            (2'b00),
        //------------- Receive Ports - RX Fabric Output Control Ports -------------
        .gt0_rxoutclkfabric_out         (gt0_rxoutclkfabric_o),
        //----------- Receive Ports - RX Initialization and Reset Ports ------------
        .gt0_gtrxreset_in               (tied_to_ground_i),
        .gt0_rxpmareset_in              (gt0_rxpmareset_i),
        //------------ Receive Ports -RX Initialization and Reset Ports ------------
        .gt0_rxresetdone_out            (gt_rxresetdone_o),
        //------------------- TX Initialization and Reset Ports --------------------
        .gt0_gttxreset_in               (tied_to_ground_i),
        .gt0_txuserrdy_in               (tied_to_vcc_i),
        //---------------- Transmit Ports - TX Data Path interface -----------------
        .gt0_txdata_in                  (gt0_txdata_i),
        //-------------- Transmit Ports - TX Driver and OOB signaling --------------
        .gt0_gtxtxn_out                 (TXN_OUT),
        .gt0_gtxtxp_out                 (TXP_OUT),
        //--------- Transmit Ports - TX Fabric Clock Output Control Ports ----------
        .gt0_txoutclkfabric_out         (gt0_txoutclkfabric_o),
        .gt0_txoutclkpcs_out            (gt0_txoutclkpcs_i),
        //----------- Transmit Ports - TX Initialization and Reset Ports -----------
        .gt0_txresetdone_out            (gt_txresetdone_o),


    //____________________________COMMON PORTS________________________________
    .gt0_qplllock_out(),
    .gt0_qpllrefclklost_out(),
    .gt0_qplloutclk_out(),
    .gt0_qplloutrefclk_out(),
    .sysclk_in(drpclk_in_i)
    );


	assign  drpclk_in_i = sysclk_i;









endmodule
