module rv32_divider (
    input  logic        clk,
    input  logic        rst,

    input  logic        start,
    input  logic [1:0]  op,
    input  logic [31:0] rs1,
    input  logic [31:0] rs2,

    output logic        busy,
    output logic        done,
    output logic [31:0] result
);

    localparam logic [1:0] DIV_OP_DIV  = 2'd0;
    localparam logic [1:0] DIV_OP_DIVU = 2'd1;
    localparam logic [1:0] DIV_OP_REM  = 2'd2;
    localparam logic [1:0] DIV_OP_REMU = 2'd3;

    logic [5:0]  cnt;

    logic        signed_op;
    logic        want_rem;
    logic        quotient_neg;
    logic        remainder_neg;

    logic [31:0] dividend_orig;
    logic [31:0] divisor_abs;

    logic [31:0] dividend_shift;
    logic [31:0] quotient;
    logic [32:0] remainder;

    logic [31:0] quotient_final;
    logic [31:0] remainder_final;

    logic        div_by_zero;
    logic        signed_overflow;

    assign quotient_final  = quotient_neg  ? (~quotient + 32'd1) : quotient;
    assign remainder_final = remainder_neg ? (~remainder[31:0] + 32'd1) : remainder[31:0];

    assign signed_op = (op == DIV_OP_DIV) || (op == DIV_OP_REM);
    assign want_rem  = (op == DIV_OP_REM) || (op == DIV_OP_REMU);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            busy           <= 1'b0;
            done           <= 1'b0;
            result         <= 32'h0;
            cnt            <= 6'd0;
            dividend_orig  <= 32'h0;
            dividend_shift <= 32'h0;
            divisor_abs    <= 32'h0;
            quotient       <= 32'h0;
            remainder      <= 33'h0;
            quotient_neg   <= 1'b0;
            remainder_neg  <= 1'b0;
            div_by_zero    <= 1'b0;
            signed_overflow <= 1'b0;
        end else begin
            done <= 1'b0;

            if (start && !busy) begin
                busy <= 1'b1;
                cnt  <= 6'd32;

                div_by_zero <= (rs2 == 32'h0);
                signed_overflow <= signed_op &&
                                   (rs1 == 32'h8000_0000) &&
                                   (rs2 == 32'hFFFF_FFFF);

                quotient_neg  <= signed_op && (rs1[31] ^ rs2[31]);
                remainder_neg <= signed_op && rs1[31];

                dividend_orig <= rs1;
                divisor_abs  <= (signed_op && rs2[31]) ? (~rs2 + 32'd1) : rs2;

                dividend_shift <= (signed_op && rs1[31]) ? (~rs1 + 32'd1) : rs1;
                quotient       <= 32'h0;
                remainder      <= 33'h0;
            end else if (busy) begin
                if (div_by_zero) begin
                    busy <= 1'b0;
                    done <= 1'b1;

                    if (want_rem) begin
                        result <= dividend_orig;
                    end else begin
                        result <= 32'hFFFF_FFFF;
                    end
                end else if (signed_overflow) begin
                    busy <= 1'b0;
                    done <= 1'b1;

                    if (want_rem) begin
                        result <= 32'h0000_0000;
                    end else begin
                        result <= 32'h8000_0000;
                    end
                end else if (cnt != 0) begin
                    logic [32:0] rem_shift;
                    logic [32:0] rem_sub;

                    rem_shift = {remainder[31:0], dividend_shift[31]};
                    rem_sub   = rem_shift - {1'b0, divisor_abs};

                    dividend_shift <= {dividend_shift[30:0], 1'b0};

                    if (!rem_sub[32]) begin
                        remainder <= rem_sub;
                        quotient  <= {quotient[30:0], 1'b1};
                    end else begin
                        remainder <= rem_shift;
                        quotient  <= {quotient[30:0], 1'b0};
                    end

                    cnt <= cnt - 6'd1;
                end else begin
                    busy <= 1'b0;
                    done <= 1'b1;

                    if (want_rem) begin
                        result <= remainder_final;
                    end else begin
                        result <= quotient_final;
                    end
                end
            end
        end
    end

endmodule
