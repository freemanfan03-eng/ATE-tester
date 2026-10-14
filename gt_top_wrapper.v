`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/08/07 15:37:36
// Design Name: 
// Module Name: gt_top_wrapper
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module gt_top_wrapper #(

parameter DATA_WDITH = 64
)
(
    // ------------------------------------------------------------------------
    // 1. 外部物理晶振管脚 (Bank 115 / MGTREFCLK0)
    // ------------------------------------------------------------------------
    input  wire gt_refclk_pad_p_in,
	input  wire gt_refclk_pad_n_in,
    // ------------------------------------------------------------------------
    // 2. 系统稳定辅助时钟与软件复位
    // ------------------------------------------------------------------------
    input  wire  sysclk_in,                  // 100MHz 辅助控制时钟
    input  wire  soft_reset_tx_in,             
	input  wire  soft_reset_rx_in,   
	
	input  wire  gt_data_valid_in,
    //-------------------------- Channel 0 - DRP Ports  --------------------------
	(* X_INTERFACE_INFO = "xilinx.com:interface:drp_rtl:1.0 drp0 DADDR" *)
	input   [8:0]   gt0_drpaddr_in,
	(* X_INTERFACE_INFO = "xilinx.com:interface:drp_rtl:1.0 drp0 DI" *)   
	input   [15:0]  gt0_drpdi_in,
	(* X_INTERFACE_INFO = "xilinx.com:interface:drp_rtl:1.0 drp0 DO" *)    
	output  [15:0]  gt0_drpdo_out,
	(* X_INTERFACE_INFO = "xilinx.com:interface:drp_rtl:1.0 drp0 DEN" *)   
	input           gt0_drpen_in,
	(* X_INTERFACE_INFO = "xilinx.com:interface:drp_rtl:1.0 drp0 DRDY" *)  
	output          gt0_drprdy_out,
	(* X_INTERFACE_INFO = "xilinx.com:interface:drp_rtl:1.0 drp0 DWE" *)  
	input           gt0_drpwe_in,

	 //-------------------------- Channel 1 - DRP Ports  --------------------------
   (* X_INTERFACE_INFO = "xilinx.com:interface:drp_rtl:1.0 drp1 DADDR" *)
	input   [8:0]   gt1_drpaddr_in,
	(* X_INTERFACE_INFO = "xilinx.com:interface:drp_rtl:1.0 drp1 DI" *)   
	input   [15:0]  gt1_drpdi_in,
	(* X_INTERFACE_INFO = "xilinx.com:interface:drp_rtl:1.0 drp1 DO" *)    
	output  [15:0]  gt1_drpdo_out,
	(* X_INTERFACE_INFO = "xilinx.com:interface:drp_rtl:1.0 drp1 DEN" *)   
	input           gt1_drpen_in,
	(* X_INTERFACE_INFO = "xilinx.com:interface:drp_rtl:1.0 drp1 DRDY" *)  
	output          gt1_drprdy_out,
	(* X_INTERFACE_INFO = "xilinx.com:interface:drp_rtl:1.0 drp1 DWE" *)  
	input           gt1_drpwe_in,
	
	//
	output   wire gt0_txusrclk_out,
    output   wire gt0_rxusrclk_out,
	//
	output wire gt0_rxresetdone_out,
	output wire gt0_txresetdone_out,
	
	output wire gt1_rxresetdone_out,
	output wire gt1_txresetdone_out,
	output wire gt_locked,
	
	input wire lane0_almost_full,
	input wire lane1_almost_full,
	
	output wire gt0_axis_tready,
	output wire gt1_axis_tready,
	 //---------------- Transmit Ports - TX Data Path interface -----------------
   (* MARK_DEBUG = "true", DONT_TOUCH = "true" *) input   [DATA_WDITH-1:0]  gt0_txdata_in,
    //---------------- Receive Ports - FPGA RX interface Ports -----------------
   (* MARK_DEBUG = "true", DONT_TOUCH = "true" *) output  [DATA_WDITH-1:0]  gt0_rxdata_out,
   
	//---------------- Transmit Ports - TX Data Path interface -----------------
	(* MARK_DEBUG = "true", DONT_TOUCH = "true" *)input   [DATA_WDITH-1:0]   gt1_txdata_in,
	input gt1_txdata_in_1bit,
    //---------------- Receive Ports - FPGA RX interface Ports -----------------
   (* MARK_DEBUG = "true", DONT_TOUCH = "true" *) output  [DATA_WDITH-1:0]   gt1_rxdata_out,
   // ------------------------------------------------------------------------
	// 3. 通道 0 (GT0) 物理接口与数据接口
	// ------------------------------------------------------------------------
	output wire gt0_tx_pad_p_out,             // GTX0 发送管脚 
	output wire gt0_tx_pad_n_out,            
		
	input  wire gt0_rx_pad_p_in,              // GTX0 接收管脚 
	input  wire gt0_rx_pad_n_in,              
	// ------------------------------------------------------------------------
	// 4. 通道 1 (GT1) 物理接口与数据接口
	// ------------------------------------------------------------------------
	output wire gt1_tx_pad_p_out,           // GTX1 发送管脚 
	output wire gt1_tx_pad_n_out,      
	
	input  wire gt1_rx_pad_p_in,             // GTX1 接收管脚 
	input  wire gt1_rx_pad_n_in             
	
    
);

	// 添加 (* ASYNC_REG = "TRUE" *) 属性
	wire  lane0_almost_full_cdc;
	wire  lane1_almost_full_cdc;
	xpm_cdc_single #(
      .DEST_SYNC_FF(2),   // DECIMAL; range: 2-10
      .INIT_SYNC_FF(0),   // DECIMAL; 0=disable simulation init values, 1=enable simulation init values
      .SIM_ASSERT_CHK(0), // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
      .SRC_INPUT_REG(1)   // DECIMAL; 0=do not register input, 1=register input
   )
   xpm_cdc_single_inst_gt0 (
      .dest_out(lane0_almost_full_cdc), // 1-bit output: src_in synchronized to the destination clock domain. This output is
                           // registered.

      .dest_clk(gt0_txusrclk_out), // 1-bit input: Clock signal for the destination clock domain.
      .src_clk(sysclk_in),   // 1-bit input: optional; required when SRC_INPUT_REG = 1
      .src_in(lane0_almost_full)      // 1-bit input: Input signal to be synchronized to dest_clk domain.
   );
   
   
    xpm_cdc_single #(
      .DEST_SYNC_FF(2),   // DECIMAL; range: 2-10
      .INIT_SYNC_FF(0),   // DECIMAL; 0=disable simulation init values, 1=enable simulation init values
      .SIM_ASSERT_CHK(0), // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
      .SRC_INPUT_REG(1)   // DECIMAL; 0=do not register input, 1=register input
   )
   xpm_cdc_single_inst_gt1 (
      .dest_out(lane1_almost_full_cdc), // 1-bit output: src_in synchronized to the destination clock domain. This output is
                           // registered.

      .dest_clk(gt0_txusrclk_out), // 1-bit input: Clock signal for the destination clock domain.
      .src_clk(sysclk_in),   // 1-bit input: optional; required when SRC_INPUT_REG = 1
      .src_in(lane1_almost_full)      // 1-bit input: Input signal to be synchronized to dest_clk domain.
   );
   

	
	assign gt0_axis_tready = (~lane0_almost_full_cdc) & gt0_txresetdone_out;
	assign gt1_axis_tready = (~lane1_almost_full_cdc) & gt1_txresetdone_out;
	
	
	
	(* MARK_DEBUG = "true", DONT_TOUCH = "true" *)reg [31:0]  gt0_rxdata_out_buf;
	always@(posedge gt0_txusrclk_out)begin
	
		gt0_rxdata_out_buf <= gt0_rxdata_out;
	
	end
	
	
	wire [1:0]RXP_IN;
	wire [1:0]RXN_IN;
	wire [1:0]TXP_OUT;
	wire [1:0]TXN_OUT;
	//
	assign RXP_IN[0] = gt0_rx_pad_p_in;
	assign RXP_IN[1] = gt1_rx_pad_p_in;
	assign RXN_IN[0] = gt0_rx_pad_n_in;
	assign RXN_IN[1] = gt1_rx_pad_n_in;
	//
	assign gt0_tx_pad_p_out = TXP_OUT[0] ;
	assign gt1_tx_pad_p_out = TXP_OUT[1] ;
	assign gt0_tx_pad_n_out = TXN_OUT[0] ;
	assign gt1_tx_pad_n_out = TXN_OUT[1] ;
	
	wire  [DATA_WDITH-1:0] gt1_txdata_i = {64{gt1_txdata_in_1bit}};
	
	gtwizard_0_exdes #
	(	.DATA_WDITH(DATA_WDITH),
		.EXAMPLE_SIM_GTRESET_SPEEDUP          (   "TRUE"),    // simulation setting for GT SecureIP model
		.EXAMPLE_USE_CHIPSCOPE                (   1),         // Set to 1 to use Chipscope to drive resets
		.STABLE_CLOCK_PERIOD                  ( 10)

	)gtwizard_0_exdes_inst
	(
		.sysclk_in(sysclk_in),                  // 100MHz 辅助控制时钟
		.soft_reset_tx_in(soft_reset_tx_in),
		.soft_reset_rx_in(soft_reset_rx_in),
		.gt_data_valid_in(gt_data_valid_in),
		//-------------------------- Channel 0 - DRP Ports  --------------------------
		.gt0_drpaddr_in(gt0_drpaddr_in),
		.gt0_drpdi_in(gt0_drpdi_in),
		.gt0_drpdo_out(gt0_drpdo_out),
		.gt0_drpen_in(gt0_drpen_in),
		.gt0_drprdy_out(gt0_drprdy_out),
		.gt0_drpwe_in(gt0_drpwe_in),

		//-------------------------- Channel 1 - DRP Ports  --------------------------
		.gt1_drpaddr_in(gt1_drpaddr_in),
		.gt1_drpdi_in(gt1_drpdi_in),
		.gt1_drpdo_out(gt1_drpdo_out),
		.gt1_drpen_in(gt1_drpen_in),
		.gt1_drprdy_out(gt1_drprdy_out),
		.gt1_drpwe_in(gt1_drpwe_in),
		//---------------- Transmit Ports - TX Data Path interface -----------------
		.gt0_txdata_in(gt0_txdata_in),
		//---------------- Receive Ports - FPGA RX interface Ports -----------------
		.gt0_rxdata_out(gt0_rxdata_out),

		//---------------- Transmit Ports - TX Data Path interface -----------------
		.gt1_txdata_in(gt1_txdata_in),//gt1_txdata_i
		//---------------- Receive Ports - FPGA RX interface Ports -----------------
		.gt1_rxdata_out(gt1_rxdata_out),
		//-------------------------- Channel 1 - DRP Ports  --------------------------
		.gt0_txusrclk_out(gt0_txusrclk_out),
		.gt0_rxusrclk_out(gt0_rxusrclk_out),
		//
		.gt0_rxresetdone_out(gt0_rxresetdone_out),
		.gt0_txresetdone_out(gt0_txresetdone_out),
		
		.gt1_rxresetdone_out(gt1_rxresetdone_out),
		.gt1_txresetdone_out(gt1_txresetdone_out),
		.gt_locked(gt_locked),

		.Q0_CLK1_GTREFCLK_PAD_N_IN(gt_refclk_pad_n_in),
		.Q0_CLK1_GTREFCLK_PAD_P_IN(gt_refclk_pad_p_in),
		.RXN_IN(RXN_IN),
		.RXP_IN(RXP_IN),
		.TXN_OUT(TXN_OUT),
		.TXP_OUT(TXP_OUT)
	);
		
	
endmodule
