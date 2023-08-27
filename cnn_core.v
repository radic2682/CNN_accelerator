`timescale 1ns/10ps

module cnn_core #(
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
    parameter BIT_A_RESULT = 21 // No Activation -> = <BIT_B_RESULT>
)(
    input                          clk          ,
    input                          reset_n      ,
    input                          i_soft_reset ,

    input  [BIT_WIET*KY*KX*CO-1:0] i_weight     ,
    input  [BIT_IN_F*KY*KX   -1:0] i_in_FM      ,
    input  [BIT_BIAS      *CO-1:0] i_bias       ,

    input                          i_in_valid   ,

    output                         o_core_valid ,
    output [BIT_A_RESULT  *CO-1:0] o_core_result
);

//====================================================================================================================
// Data Enable Signals & DELAY --> 1Cycle

    localparam DELAY = 1;

    wire    [DELAY-1 : 0] 	ce;
    reg     [DELAY-1 : 0] 	r_valid;
    wire    [CO-1 : 0]      w_ot_valid;

    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            r_valid   <= {DELAY{1'b0}};
        end else if(i_soft_reset) begin
            r_valid   <= {DELAY{1'b0}};
        end else begin
            r_valid[DELAY-1]  <= &w_ot_valid; // out when <w_ot_valid> is valided
        end
    end

    assign	ce = r_valid;


//====================================================================================================================
// kernel Instance --> number of CO  ...calculate

    wire [                   CO-1:0] w_in_valid;
    wire [BIT_K_RESULT      *CO-1:0] w_kernel_result;

    genvar co;
    generate
        for(co = 0; co < CO; co = co + 1) begin

            wire [BIT_WIET*KY*KX-1:0] w_weight = i_weight[co*BIT_WIET*KY*KX +: BIT_WIET*KY*KX];

            assign w_in_valid[co] = i_in_valid;


            kernel #(
                    .KX(KX),
                    .KY(KY),
                    .CO(CO),
                    .BIT_IN_F(BIT_IN_F),
                    .BIT_WIET(BIT_WIET),
                    .BIT_BIAS(BIT_BIAS),
                    .BIT_K_MUL_RESULT(BIT_K_MUL_RESULT),
                    .BIT_K_SUM_RESULT(BIT_K_SUM_RESULT),
                    .BIT_K_RESULT(BIT_K_RESULT),
                    .BIT_B_RESULT(BIT_B_RESULT),
                    .BIT_A_RESULT(BIT_A_RESULT)
                ) inst_kernel (
                    .clk            (clk                ),
                    .reset_n        (reset_n            ),
                    .i_soft_reset   (i_soft_reset       ),
                    
                    .i_weight       (w_weight           ),
                    .i_in_valid     (w_in_valid[co]     ),
                    .i_in_FM        (i_in_FM            ),
                    
                    .o_kernel_valid (w_ot_valid[co]     ),
                    .o_kernel_result(w_kernel_result[co*BIT_K_RESULT +: BIT_K_RESULT])
                );
        end
    endgenerate


//====================================================================================================================
// Bias ADDing <w_kernel_result> + <i_bias>

    wire      [BIT_B_RESULT*CO-1 : 0]   w_bias_result;
    reg       [BIT_B_RESULT*CO-1 : 0]   r_bias_result;

    generate
        for (co = 0; co < CO; co = co + 1) begin

            assign  w_bias_result[co*BIT_B_RESULT +: BIT_B_RESULT] = w_kernel_result[co*BIT_K_RESULT +: BIT_K_RESULT] + i_bias[co*BIT_BIAS +: BIT_BIAS];

            always @(posedge clk or negedge reset_n) begin
                if(!reset_n) begin
                    r_bias_result[co*BIT_B_RESULT +: BIT_B_RESULT]   <= {BIT_B_RESULT{1'b0}};
                end else if(i_soft_reset) begin
                    r_bias_result[co*BIT_B_RESULT +: BIT_B_RESULT]   <= {BIT_B_RESULT{1'b0}};
                end else if(&w_ot_valid) begin
                    r_bias_result[co*BIT_B_RESULT +: BIT_B_RESULT]   <= w_bias_result[co*BIT_B_RESULT +: BIT_B_RESULT];
                end
            end

        end
    endgenerate


//====================================================================================================================
// No Activation



//====================================================================================================================
// Result

assign o_core_valid = r_valid[DELAY-1];
assign o_core_result  = r_bias_result;

endmodule

