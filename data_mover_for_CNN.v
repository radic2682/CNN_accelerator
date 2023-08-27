`timescale 1ns / 1ps

module data_mover_for_cnn #(

	parameter DATA_ADDR_WIDTH = 32,
	parameter DATA_WIDTH = 32,
	
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
    input 					clk,
    input 					reset_n,

	input 					i_run,

	output   				o_idle,
	output					o_data_p,
	output   				o_run,
	output   				o_write,
	output  				o_done,

	// BRAM 0
	output wire [DATA_ADDR_WIDTH-1:0] o_bram0_addr, // Adress to access BRAM
	output wire                       o_bram0_en, 	// BRAM chip  enable signal
	output wire                       o_bram0_we, 	// BRAM write enable signal
	input  wire [DATA_ADDR_WIDTH-1:0] i_bram0_qout, // data received by BRAM
	output wire [DATA_ADDR_WIDTH-1:0] o_bram0_din, 	// data send to BRAM

	// BRAM 1
	output wire [DATA_ADDR_WIDTH-1:0] o_bram1_addr, // Adress to access BRAM
	output wire                       o_bram1_en, 	// BRAM chip  enable signal
	output wire                       o_bram1_we, 	// BRAM write enable signal
	input  wire [DATA_ADDR_WIDTH-1:0] i_bram1_qout, // data received by BRAM
	output wire [DATA_ADDR_WIDTH-1:0] o_bram1_din, 	// data send to BRAM

	// BRAM 2
	output wire [DATA_ADDR_WIDTH-1:0] o_bram2_addr, // Adress to access BAM
	output wire                       o_bram2_en, 	// BRAM chip  enable ignal
	output wire                       o_bram2_we, 	// BRAM write enable ignal
	input  wire [DATA_ADDR_WIDTH-1:0] i_bram2_qout, // data received by BAM
	output wire [DATA_ADDR_WIDTH-1:0] o_bram2_din 	// data send to BRAM
);



// ======================================================================================
// Main FSM   => Idle, S_DATA_P, Run, Done

	localparam S_IDLE	= 3'b000;
	localparam S_DATA_P	= 3'b001; // Move DATA BRAM to Buffer 
	localparam S_RUN	= 3'b010;
	localparam S_WRITE	= 3'b011;
	localparam S_DONE  	= 3'b100;

	reg [2:0] current_state, next_state;

	wire w_CNN_valid;
	wire is_count_done_W;
	wire w_s_done_all;

	always @(posedge clk or negedge reset_n) begin
	    if(!reset_n) begin
			current_state <= S_IDLE;
	    end else begin
			current_state <= next_state;
	    end
	end

	always @(*) 
	begin
		next_state = current_state; // To prevent Latch.
		case(current_state)
            S_IDLE	: if(i_run)
                        next_state 	= S_DATA_P;
            S_DATA_P: if(w_s_done_all)
                        next_state 	= S_RUN;
            S_RUN   : if(w_CNN_valid)
                        next_state 	= S_WRITE;
            S_WRITE   : if(is_count_done_W)
                        next_state 	= S_DONE;
            S_DONE	: next_state 	= S_IDLE;
            default : next_state = current_state;
		endcase
	end 

	assign o_idle 		= (current_state == S_IDLE);
	assign o_data_p 	= (current_state == S_DATA_P);
	assign o_run 		= (current_state == S_RUN);
	assign o_write 		= (current_state == S_WRITE);
	assign o_done 		= (current_state == S_DONE);



// ====================================================================================== 
// MOVE A : Input FM & Bias buffing

	// ----------------------------------------------------------------------------------
	// FSM for A
	localparam S_IDLE_A	= 2'b00;
	localparam S_MOVE_A	= 2'b01;
	localparam S_DONE_A	= 2'b10;

	reg [1:0] current_state_A, next_state_A;
	wire is_count_done_A;

	always @(posedge clk or negedge reset_n) begin
	    if(!reset_n) begin
			current_state_A <= S_IDLE_A;
	    end else begin
			current_state_A <= next_state_A;
	    end
	end

	always @(*)
	begin
		next_state_A = current_state_A; // To prevent Latch.
		case(current_state_A)
			S_IDLE_A : if(i_run)
				next_state_A = S_MOVE_A;
			S_MOVE_A : if(is_count_done_A)
				next_state_A = S_DONE_A;
			S_DONE_A : if(w_s_done_all)
				next_state_A = S_IDLE_A;
			default  : next_state_A = current_state_A;
		endcase
	end

	wire w_s_move_A = (current_state_A == S_MOVE_A);
	wire w_s_done_A = (current_state_A == S_DONE_A);


	// ----------------------------------------------------------------------------------
	// VALID Delay of BRAM -> 1Cycle BRAM read delay
	reg r_bram_R_valid_A;

	always @(posedge clk or negedge reset_n) begin
	    if(!reset_n) begin
	        r_bram_R_valid_A <= 1'b0;  
	    end else begin
			r_bram_R_valid_A <= w_s_move_A;
		end
	end


	// ----------------------------------------------------------------------------------
	// ADDR count
	localparam BRAM0_R_CYCLE 	 = 7; // log [(KY*KX + CO) / (DATA_WIDTH / BIT_IN_F)] = 7
	localparam BIT_BRAM0_R_CYCLE = 3;

	reg [BIT_BRAM0_R_CYCLE-1:0] addr_counter_A;

	assign is_count_done_A = w_s_move_A && (addr_counter_A == BRAM0_R_CYCLE-1);

	always @(posedge clk or negedge reset_n) begin
	    if(!reset_n) begin
	        addr_counter_A <= 0;
	    end else if (is_count_done_A) begin
	        addr_counter_A <= 0;
	    end else if (w_s_move_A) begin
	        addr_counter_A <= addr_counter_A + 1;
		end
	end


	// ----------------------------------------------------------------------------------
	// Move DATA
	reg  [DATA_WIDTH*BRAM0_R_CYCLE-1:0] r_in_FM_bias_buff;


	always @(posedge clk or negedge reset_n) begin
	    if(!reset_n) begin
            r_in_FM_bias_buff  <= {DATA_WIDTH*BRAM0_R_CYCLE{1'b0}};
	    end else if (r_bram_R_valid_A) begin
	    	r_in_FM_bias_buff = r_in_FM_bias_buff << DATA_WIDTH;
	        r_in_FM_bias_buff = r_in_FM_bias_buff | {{DATA_WIDTH*BRAM0_R_CYCLE-DATA_WIDTH{1'b0}}, i_bram0_qout};
		end
	end

	// Caution! => Hard Coding (need to change when parameters are changed)
	wire [BIT_IN_F*KY*KX-1:0] w_in_FM_buff = r_in_FM_bias_buff[BIT_BIAS*CO+24 +: BIT_IN_F*KY*KX];
	wire [BIT_BIAS*CO-1:0] 	  w_bias_buff  = r_in_FM_bias_buff[24 +: BIT_BIAS*CO];



	// ----------------------------------------------------------------------------------
	// BRAM 0
	assign o_bram0_addr = {{(32-(BIT_BRAM0_R_CYCLE)){1'b0}}, addr_counter_A};
	assign o_bram0_en 	= w_s_move_A;
	assign o_bram0_we 	= 1'b0; // read only
	assign o_bram0_din	= {DATA_ADDR_WIDTH{1'b0}}; // no use



// ====================================================================================== 
// MOVE B : Weight buffing

	// ----------------------------------------------------------------------------------
	// FSM for B
	localparam S_IDLE_B	= 2'b00;
	localparam S_MOVE_B	= 2'b01;
	localparam S_DONE_B	= 2'b10;

	reg [1:0] current_state_B, next_state_B;
	wire is_count_done_B;

	always @(posedge clk or negedge reset_n) begin
	    if(!reset_n) begin
			current_state_B <= S_IDLE_B;
	    end else begin
			current_state_B <= next_state_B;
	    end
	end

	always @(*)
	begin
		next_state_B = current_state_B; // To prevent Latch.
		case(current_state_B)
			S_IDLE_B : if(i_run)
				next_state_B = S_MOVE_B;
			S_MOVE_B : if(is_count_done_B)
				next_state_B = S_DONE_B;
			S_DONE_B : if(w_s_done_all)
				next_state_B = S_IDLE_B;
			default  : next_state_B = current_state_B;
		endcase
	end

	wire w_s_move_B = (current_state_B == S_MOVE_B);
	wire w_s_done_B = (current_state_B == S_DONE_B);


	// ----------------------------------------------------------------------------------
	// VALID Delay of BRAM -> 1Cycle BRAM read delay

	reg r_bram_R_valid_B;

	always @(posedge clk or negedge reset_n) begin
	    if(!reset_n) begin
	        r_bram_R_valid_B <= 1'b0;  
	    end else begin
			r_bram_R_valid_B <= w_s_move_B;
		end
	end


	// ----------------------------------------------------------------------------------
	// ADDR count
	localparam BRAM1_R_CYCLE 	 = 36; // log [KY*KX*CO / (DATA_WIDTH / BIT_IN_F)] = 36
	localparam BIT_BRAM1_R_CYCLE = 6;

	reg [BIT_BRAM1_R_CYCLE-1:0] addr_counter_B;

	assign is_count_done_B = w_s_move_B && (addr_counter_B == BRAM1_R_CYCLE-1);


	always @(posedge clk or negedge reset_n) begin
	    if(!reset_n) begin
	        addr_counter_B <= 0;  
	    end else if (is_count_done_B) begin
	        addr_counter_B <= 0; 
	    end else if (w_s_move_B) begin
	        addr_counter_B <= addr_counter_B + 1;
		end
	end


	// ----------------------------------------------------------------------------------
	// Move DATA
	reg  [DATA_WIDTH*BRAM1_R_CYCLE-1:0] r_weight_buff;

	always @(posedge clk or negedge reset_n) begin
	    if(!reset_n) begin
            r_weight_buff  <= {DATA_WIDTH*BRAM1_R_CYCLE{1'b0}};
	    end else if (r_bram_R_valid_B) begin
	        r_weight_buff = r_weight_buff << DATA_WIDTH;
	        r_weight_buff = r_weight_buff | {{DATA_WIDTH*BRAM1_R_CYCLE-DATA_WIDTH{1'b0}}, i_bram1_qout};
		end
	end

	wire  [BIT_WIET*KY*KX*CO-1:0] w_weight_buff = r_weight_buff;

	// ----------------------------------------------------------------------------------
	// BRAM 1
	assign o_bram1_addr	= {{(32-(BIT_BRAM1_R_CYCLE)){1'b0}}, addr_counter_B};
	assign o_bram1_en 	= w_s_move_B;
	assign o_bram1_we 	= 1'b0; // read only
	assign o_bram1_din	= {DATA_ADDR_WIDTH{1'b0}}; // no use



// ====================================================================================== 
// MOVE A & MOVE B [all done] => main MOVE DONE

	assign w_s_done_all = w_s_done_B && w_s_done_A;



// ======================================================================================
// Instantiation CNN

	// ----------------------------------------------------------------------------------
	// Instantiation CNN
    wire [BIT_A_RESULT*CO-1:0] w_core_result;

	cnn_core inst_cnn_core (
		.clk           (clk),
		.reset_n       (reset_n),
		.i_soft_reset  (1'b0),

		.i_weight      (w_weight_buff),
		.i_in_FM       (w_in_FM_buff),
		.i_bias        (w_bias_buff),

		.i_in_valid    (o_run),

		.o_core_valid  (w_CNN_valid),
		.o_core_result (w_core_result)
	);



// ======================================================================================
// BRAM 2 WRITE

	// ----------------------------------------------------------------------------------
	// ADDR count
	localparam BIT_W_COUNT = 5;

	reg [BIT_W_COUNT-1:0] addr_counter_W;

	assign is_count_done_W = o_write && (addr_counter_W == CO-1);

	always @(posedge clk or negedge reset_n) begin
	    if(!reset_n) begin
	        addr_counter_W <= 0;  
	    end else if (is_count_done_W) begin
	        addr_counter_W <= 0; 
	    end else if (o_write) begin
	        addr_counter_W <= addr_counter_W + 1;
		end
	end


	// ----------------------------------------------------------------------------------
	// Write
	wire [BIT_A_RESULT-1:0] w_result = w_core_result[addr_counter_W*BIT_A_RESULT +: BIT_A_RESULT];


	// ----------------------------------------------------------------------------------
	// BRAM 2
	assign o_bram2_addr	= {{(32-BIT_W_COUNT){1'b0}}, addr_counter_W};
	assign o_bram2_en 	= o_write;
	assign o_bram2_we 	= o_write;
	assign o_bram2_din	= {{(32-BIT_A_RESULT){1'b0}}, w_result};
	// i_bram2_qout // no use


endmodule
