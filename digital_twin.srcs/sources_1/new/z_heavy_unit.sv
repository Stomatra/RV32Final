`timescale 1ns / 1ps

module z_heavy_unit (
    input  logic        clk,
    input  logic        rst,
    input  logic        start,
    input  logic [3:0]  op,
    input  logic [31:0] rs1,
    input  logic [31:0] rs2,
    output logic        busy,
    output logic        done,
    output logic [31:0] result
);
    localparam logic [3:0] ZH_CLZ    = 4'd0;
    localparam logic [3:0] ZH_CTZ    = 4'd1;
    localparam logic [3:0] ZH_CPOP   = 4'd2;
    localparam logic [3:0] ZH_CLMUL  = 4'd3;
    localparam logic [3:0] ZH_CLMULH = 4'd4;
    localparam logic [3:0] ZH_CLMULR = 4'd5;
    localparam logic [3:0] ZH_XPERM4 = 4'd6;
    localparam logic [3:0] ZH_XPERM8 = 4'd7;

    logic [3:0]  op_q;
    logic [31:0] a_q, b_q, perm_q;
    logic [63:0] clmul_q;
    logic [63:0] clmul_multiplicand_q;
    logic [5:0]  index_q;
    logic [5:0]  count_q;
    logic        found_q;
    logic [63:0] clmul_next;
    logic [3:0]  xperm4_value;
    logic [7:0]  xperm8_value;

    always_comb begin
        clmul_next = b_q[0] ? (clmul_q ^ clmul_multiplicand_q) : clmul_q;

        // Use fixed slices and small muxes. Dynamic part-selects here used to
        // infer a deep write decoder on perm_q and dominated the CPU path.
        case (b_q[3:0])
            4'd0: xperm4_value = a_q[3:0];
            4'd1: xperm4_value = a_q[7:4];
            4'd2: xperm4_value = a_q[11:8];
            4'd3: xperm4_value = a_q[15:12];
            4'd4: xperm4_value = a_q[19:16];
            4'd5: xperm4_value = a_q[23:20];
            4'd6: xperm4_value = a_q[27:24];
            4'd7: xperm4_value = a_q[31:28];
            default: xperm4_value = 4'h0;
        endcase

        case (b_q[7:0])
            8'd0: xperm8_value = a_q[7:0];
            8'd1: xperm8_value = a_q[15:8];
            8'd2: xperm8_value = a_q[23:16];
            8'd3: xperm8_value = a_q[31:24];
            default: xperm8_value = 8'h0;
        endcase
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            busy <= 1'b0;
            done <= 1'b0;
            result <= 32'h0;
            op_q <= 4'hf;
            a_q <= 32'h0;
            b_q <= 32'h0;
            perm_q <= 32'h0;
            clmul_q <= 64'h0;
            clmul_multiplicand_q <= 64'h0;
            index_q <= 6'h0;
            count_q <= 6'h0;
            found_q <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                busy <= 1'b1;
                op_q <= op;
                a_q <= rs1;
                b_q <= rs2;
                perm_q <= 32'h0;
                clmul_q <= 64'h0;
                clmul_multiplicand_q <= {32'h0, rs1};
                index_q <= 6'h0;
                count_q <= 6'h0;
                found_q <= 1'b0;
            end else if (busy) begin
                case (op_q)
                    ZH_CLZ: begin
                        if (!found_q && !a_q[31]) count_q <= count_q + 6'd1;
                        else found_q <= 1'b1;
                        a_q <= {a_q[30:0], 1'b0};
                        if (index_q == 6'd31) begin
                            result <= count_q + ((!found_q && !a_q[31]) ? 6'd1 : 6'd0);
                            busy <= 1'b0; done <= 1'b1;
                        end else index_q <= index_q + 6'd1;
                    end
                    ZH_CTZ: begin
                        if (!found_q && !a_q[0]) count_q <= count_q + 6'd1;
                        else found_q <= 1'b1;
                        a_q <= {1'b0, a_q[31:1]};
                        if (index_q == 6'd31) begin
                            result <= count_q + ((!found_q && !a_q[0]) ? 6'd1 : 6'd0);
                            busy <= 1'b0; done <= 1'b1;
                        end else index_q <= index_q + 6'd1;
                    end
                    ZH_CPOP: begin
                        if (a_q[0]) count_q <= count_q + 6'd1;
                        a_q <= {1'b0, a_q[31:1]};
                        if (index_q == 6'd31) begin
                            result <= count_q + (a_q[0] ? 6'd1 : 6'd0);
                            busy <= 1'b0; done <= 1'b1;
                        end else index_q <= index_q + 6'd1;
                    end
                    ZH_CLMUL, ZH_CLMULH, ZH_CLMULR: begin
                        clmul_q <= clmul_next;
                        b_q <= {1'b0, b_q[31:1]};
                        clmul_multiplicand_q <= {clmul_multiplicand_q[62:0], 1'b0};
                        if (index_q == 6'd31) begin
                            case (op_q)
                                ZH_CLMUL:  result <= clmul_next[31:0];
                                ZH_CLMULH: result <= clmul_next[63:32];
                                default:   result <= clmul_next[62:31];
                            endcase
                            busy <= 1'b0; done <= 1'b1;
                        end else index_q <= index_q + 6'd1;
                    end
                    ZH_XPERM4: begin
                        perm_q <= {xperm4_value, perm_q[31:4]};
                        b_q <= {4'h0, b_q[31:4]};
                        if (index_q == 6'd7) begin
                            result <= {xperm4_value, perm_q[31:4]};
                            busy <= 1'b0; done <= 1'b1;
                        end else index_q <= index_q + 6'd1;
                    end
                    ZH_XPERM8: begin
                        perm_q <= {xperm8_value, perm_q[31:8]};
                        b_q <= {8'h0, b_q[31:8]};
                        if (index_q == 6'd3) begin
                            result <= {xperm8_value, perm_q[31:8]};
                            busy <= 1'b0; done <= 1'b1;
                        end else index_q <= index_q + 6'd1;
                    end
                    default: begin result <= 32'h0; busy <= 1'b0; done <= 1'b1; end
                endcase
            end
        end
    end
endmodule
