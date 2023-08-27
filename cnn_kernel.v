`timescale 1ns/10ps

// kernel = MAC core
module kernel #(
	// kernel Size Parameter
	parameter KX = 3, // Number of Kernel X
	parameter KY = 3, // Number of Kernel Y

	// number of Kernel
	parameter CO = 16,

	// Input FM & BIAS & Weight [Bits]
	parameter BIT_IN_F = 8, // Bit Width of Input Feature
	parameter BIT_WIET = 8, // BW of weight parameter
	parameter BIT_BIAS = 8, // BW of bias parameter

	// kernel level Parameter [Bits]
	parameter BIT_K_MUL_RESULT = 16, // <BIT_IN_F> * <BIT_WIET>
	parameter BIT_K_SUM_RESULT = 20, // sum of <BIT_MUL_RESULT>
	parameter BIT_K_RESULT = 20,     // = sum of <BIT_MUL_RESULT>

	// Core level Parameter [Bits]
	parameter BIT_B_RESULT = 21, // Include Bias  -> <BIT_K_RESULT> + <BIT_BIAS>
	parameter BIT_A_RESULT = 21  // No Activation -> = <BIT_B_RESULT>

	)(
	input                       clk            ,
	input                       reset_n        ,
	input                       i_soft_reset   ,
	input  [KY*KX*BIT_WIET-1:0] i_weight       ,
	input  [KY*KX*BIT_IN_F-1:0] i_in_FM        ,
	input                       i_in_valid     ,
	output                      o_kernel_valid ,
	output [  BIT_K_RESULT-1:0] o_kernel_result
);



//====================================================================================================================
// Data Enable Signals & DELAY --> 2Cycle

	localparam DELAY = 2;

	wire [DELAY-1:0] ce     ;
	reg  [DELAY-1:0] r_valid;

	always @(posedge clk or negedge reset_n) begin
		if(!reset_n) begin
			r_valid <= {DELAY{1'b0}};
		end else if(i_soft_reset) begin
			r_valid <= {DELAY{1'b0}};
		end else begin
			r_valid[DELAY-2] <= i_in_valid;
			r_valid[DELAY-1] <= r_valid[DELAY-2];
		end
	end

	assign ce = r_valid;


//====================================================================================================================
// Input_FM * Weight --> w_mul --> r_mul

	wire [KY*KX*BIT_K_MUL_RESULT-1:0] w_mul;
	reg  [KY*KX*BIT_K_MUL_RESULT-1:0] r_mul;

	genvar kx_ky;
	generate
		for(kx_ky = 0; kx_ky < KY*KX; kx_ky = kx_ky + 1) begin

			assign  w_mul[kx_ky * BIT_K_MUL_RESULT +: BIT_K_MUL_RESULT]
					= i_in_FM[kx_ky * BIT_IN_F +: BIT_IN_F] * i_weight[kx_ky * BIT_WIET +: BIT_WIET];
		
			always @(posedge clk or negedge reset_n) begin
			    if(!reset_n) begin
			        r_mul[kx_ky * BIT_K_MUL_RESULT +: BIT_K_MUL_RESULT] <= {BIT_K_MUL_RESULT{1'b0}};
			    end else if(i_soft_reset) begin
			        r_mul[kx_ky * BIT_K_MUL_RESULT +: BIT_K_MUL_RESULT] <= {BIT_K_MUL_RESULT{1'b0}};
			    end else if(i_in_valid)begin
			        r_mul[kx_ky * BIT_K_MUL_RESULT +: BIT_K_MUL_RESULT] <= w_mul[kx_ky * BIT_K_MUL_RESULT +: BIT_K_MUL_RESULT];
			    end
			end

		end
	endgenerate


//====================================================================================================================
// Sum of (Input_FM * Weight)

	reg [BIT_K_SUM_RESULT-1:0] r_kernel_result;
	reg [BIT_K_SUM_RESULT-1:0] r_delayed_kernel_result;

	integer kx_ky_e;
	generate
		always @ (*) begin
			r_kernel_result[0 +: BIT_K_SUM_RESULT]= {BIT_K_SUM_RESULT{1'b0}};

			for(kx_ky_e =0; kx_ky_e < KY*KX; kx_ky_e = kx_ky_e +1) begin
				r_kernel_result[0 +: BIT_K_SUM_RESULT] = r_kernel_result[0 +: BIT_K_SUM_RESULT] + r_mul[kx_ky_e*BIT_K_MUL_RESULT +: BIT_K_MUL_RESULT]; 
			end
		end

		always @(posedge clk or negedge reset_n) begin
		    if(!reset_n) begin
		        r_delayed_kernel_result <= {BIT_K_SUM_RESULT{1'b0}};
		    end else if(i_soft_reset) begin
		        r_delayed_kernel_result <= {BIT_K_SUM_RESULT{1'b0}};
		    end else if(ce[DELAY-2])begin
		        r_delayed_kernel_result <= r_kernel_result;
		    end
		end
	endgenerate


//====================================================================================================================
// Result

	assign o_kernel_valid = r_valid[DELAY-1];
	assign o_kernel_result = r_delayed_kernel_result;

endmodule
