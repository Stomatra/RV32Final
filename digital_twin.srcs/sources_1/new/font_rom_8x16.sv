`timescale 1ns / 1ps

module font_rom_8x16 (
    input  logic [7:0] char_code,
    input  logic [3:0] row,
    output logic [7:0] pixels
);
    logic [2:0] row8;

    assign row8 = row[3:1];

    always_comb begin
        pixels = 8'h00;
        unique case (char_code)
            8'h20: pixels = 8'h00; // space
            8'h30: begin // 0
                unique case (row8)
                    3'd0: pixels = 8'h3c;
                    3'd1: pixels = 8'h66;
                    3'd2: pixels = 8'h6e;
                    3'd3: pixels = 8'h76;
                    3'd4: pixels = 8'h66;
                    3'd5: pixels = 8'h66;
                    3'd6: pixels = 8'h3c;
                    default: pixels = 8'h00;
                endcase
            end
            8'h31: begin // 1
                unique case (row8)
                    3'd0: pixels = 8'h18;
                    3'd1: pixels = 8'h38;
                    3'd2: pixels = 8'h18;
                    3'd3: pixels = 8'h18;
                    3'd4: pixels = 8'h18;
                    3'd5: pixels = 8'h18;
                    3'd6: pixels = 8'h7e;
                    default: pixels = 8'h00;
                endcase
            end
            8'h32: begin // 2
                unique case (row8)
                    3'd0: pixels = 8'h3c;
                    3'd1: pixels = 8'h66;
                    3'd2: pixels = 8'h06;
                    3'd3: pixels = 8'h1c;
                    3'd4: pixels = 8'h30;
                    3'd5: pixels = 8'h60;
                    3'd6: pixels = 8'h7e;
                    default: pixels = 8'h00;
                endcase
            end
            8'h33: begin // 3
                unique case (row8)
                    3'd0: pixels = 8'h3c;
                    3'd1: pixels = 8'h66;
                    3'd2: pixels = 8'h06;
                    3'd3: pixels = 8'h1c;
                    3'd4: pixels = 8'h06;
                    3'd5: pixels = 8'h66;
                    3'd6: pixels = 8'h3c;
                    default: pixels = 8'h00;
                endcase
            end
            8'h34: begin // 4
                unique case (row8)
                    3'd0: pixels = 8'h0c;
                    3'd1: pixels = 8'h1c;
                    3'd2: pixels = 8'h3c;
                    3'd3: pixels = 8'h6c;
                    3'd4: pixels = 8'h7e;
                    3'd5: pixels = 8'h0c;
                    3'd6: pixels = 8'h0c;
                    default: pixels = 8'h00;
                endcase
            end
            8'h35: begin // 5
                unique case (row8)
                    3'd0: pixels = 8'h7e;
                    3'd1: pixels = 8'h60;
                    3'd2: pixels = 8'h7c;
                    3'd3: pixels = 8'h06;
                    3'd4: pixels = 8'h06;
                    3'd5: pixels = 8'h66;
                    3'd6: pixels = 8'h3c;
                    default: pixels = 8'h00;
                endcase
            end
            8'h36: begin // 6
                unique case (row8)
                    3'd0: pixels = 8'h1c;
                    3'd1: pixels = 8'h30;
                    3'd2: pixels = 8'h60;
                    3'd3: pixels = 8'h7c;
                    3'd4: pixels = 8'h66;
                    3'd5: pixels = 8'h66;
                    3'd6: pixels = 8'h3c;
                    default: pixels = 8'h00;
                endcase
            end
            8'h37: begin // 7
                unique case (row8)
                    3'd0: pixels = 8'h7e;
                    3'd1: pixels = 8'h06;
                    3'd2: pixels = 8'h0c;
                    3'd3: pixels = 8'h18;
                    3'd4: pixels = 8'h30;
                    3'd5: pixels = 8'h30;
                    3'd6: pixels = 8'h30;
                    default: pixels = 8'h00;
                endcase
            end
            8'h38: begin // 8
                unique case (row8)
                    3'd0: pixels = 8'h3c;
                    3'd1: pixels = 8'h66;
                    3'd2: pixels = 8'h66;
                    3'd3: pixels = 8'h3c;
                    3'd4: pixels = 8'h66;
                    3'd5: pixels = 8'h66;
                    3'd6: pixels = 8'h3c;
                    default: pixels = 8'h00;
                endcase
            end
            8'h39: begin // 9
                unique case (row8)
                    3'd0: pixels = 8'h3c;
                    3'd1: pixels = 8'h66;
                    3'd2: pixels = 8'h66;
                    3'd3: pixels = 8'h3e;
                    3'd4: pixels = 8'h06;
                    3'd5: pixels = 8'h0c;
                    3'd6: pixels = 8'h38;
                    default: pixels = 8'h00;
                endcase
            end
            8'h3a: begin // :
                unique case (row8)
                    3'd2: pixels = 8'h18;
                    3'd5: pixels = 8'h18;
                    default: pixels = 8'h00;
                endcase
            end
            8'h3d: begin // =
                unique case (row8)
                    3'd2: pixels = 8'h7e;
                    3'd4: pixels = 8'h7e;
                    default: pixels = 8'h00;
                endcase
            end
            8'h41: begin // A
                unique case (row8)
                    3'd0: pixels = 8'h18;
                    3'd1: pixels = 8'h3c;
                    3'd2: pixels = 8'h66;
                    3'd3: pixels = 8'h66;
                    3'd4: pixels = 8'h7e;
                    3'd5: pixels = 8'h66;
                    3'd6: pixels = 8'h66;
                    default: pixels = 8'h00;
                endcase
            end
            8'h42: begin // B
                unique case (row8)
                    3'd0: pixels = 8'h7c;
                    3'd1: pixels = 8'h66;
                    3'd2: pixels = 8'h66;
                    3'd3: pixels = 8'h7c;
                    3'd4: pixels = 8'h66;
                    3'd5: pixels = 8'h66;
                    3'd6: pixels = 8'h7c;
                    default: pixels = 8'h00;
                endcase
            end
            8'h43: begin // C
                unique case (row8)
                    3'd0: pixels = 8'h3c;
                    3'd1: pixels = 8'h66;
                    3'd2: pixels = 8'h60;
                    3'd3: pixels = 8'h60;
                    3'd4: pixels = 8'h60;
                    3'd5: pixels = 8'h66;
                    3'd6: pixels = 8'h3c;
                    default: pixels = 8'h00;
                endcase
            end
            8'h44: begin // D
                unique case (row8)
                    3'd0: pixels = 8'h78;
                    3'd1: pixels = 8'h6c;
                    3'd2: pixels = 8'h66;
                    3'd3: pixels = 8'h66;
                    3'd4: pixels = 8'h66;
                    3'd5: pixels = 8'h6c;
                    3'd6: pixels = 8'h78;
                    default: pixels = 8'h00;
                endcase
            end
            8'h45: begin // E
                unique case (row8)
                    3'd0: pixels = 8'h7e;
                    3'd1: pixels = 8'h60;
                    3'd2: pixels = 8'h60;
                    3'd3: pixels = 8'h7c;
                    3'd4: pixels = 8'h60;
                    3'd5: pixels = 8'h60;
                    3'd6: pixels = 8'h7e;
                    default: pixels = 8'h00;
                endcase
            end
            8'h46: begin // F
                unique case (row8)
                    3'd0: pixels = 8'h7e;
                    3'd1: pixels = 8'h60;
                    3'd2: pixels = 8'h60;
                    3'd3: pixels = 8'h7c;
                    3'd4: pixels = 8'h60;
                    3'd5: pixels = 8'h60;
                    3'd6: pixels = 8'h60;
                    default: pixels = 8'h00;
                endcase
            end
            8'h47: begin // G
                unique case (row8)
                    3'd0: pixels = 8'h3c;
                    3'd1: pixels = 8'h66;
                    3'd2: pixels = 8'h60;
                    3'd3: pixels = 8'h6e;
                    3'd4: pixels = 8'h66;
                    3'd5: pixels = 8'h66;
                    3'd6: pixels = 8'h3e;
                    default: pixels = 8'h00;
                endcase
            end
            8'h48: begin // H
                unique case (row8)
                    3'd0: pixels = 8'h66;
                    3'd1: pixels = 8'h66;
                    3'd2: pixels = 8'h66;
                    3'd3: pixels = 8'h7e;
                    3'd4: pixels = 8'h66;
                    3'd5: pixels = 8'h66;
                    3'd6: pixels = 8'h66;
                    default: pixels = 8'h00;
                endcase
            end
            8'h49: begin // I
                unique case (row8)
                    3'd0: pixels = 8'h3c;
                    3'd1: pixels = 8'h18;
                    3'd2: pixels = 8'h18;
                    3'd3: pixels = 8'h18;
                    3'd4: pixels = 8'h18;
                    3'd5: pixels = 8'h18;
                    3'd6: pixels = 8'h3c;
                    default: pixels = 8'h00;
                endcase
            end
            8'h4a: begin // J
                unique case (row8)
                    3'd0: pixels = 8'h1e;
                    3'd1: pixels = 8'h0c;
                    3'd2: pixels = 8'h0c;
                    3'd3: pixels = 8'h0c;
                    3'd4: pixels = 8'h0c;
                    3'd5: pixels = 8'h6c;
                    3'd6: pixels = 8'h38;
                    default: pixels = 8'h00;
                endcase
            end
            8'h4b: begin // K
                unique case (row8)
                    3'd0: pixels = 8'h66;
                    3'd1: pixels = 8'h6c;
                    3'd2: pixels = 8'h78;
                    3'd3: pixels = 8'h70;
                    3'd4: pixels = 8'h78;
                    3'd5: pixels = 8'h6c;
                    3'd6: pixels = 8'h66;
                    default: pixels = 8'h00;
                endcase
            end
            8'h4c: begin // L
                unique case (row8)
                    3'd0: pixels = 8'h60;
                    3'd1: pixels = 8'h60;
                    3'd2: pixels = 8'h60;
                    3'd3: pixels = 8'h60;
                    3'd4: pixels = 8'h60;
                    3'd5: pixels = 8'h60;
                    3'd6: pixels = 8'h7e;
                    default: pixels = 8'h00;
                endcase
            end
            8'h4d: begin // M
                unique case (row8)
                    3'd0: pixels = 8'h63;
                    3'd1: pixels = 8'h77;
                    3'd2: pixels = 8'h7f;
                    3'd3: pixels = 8'h6b;
                    3'd4: pixels = 8'h63;
                    3'd5: pixels = 8'h63;
                    3'd6: pixels = 8'h63;
                    default: pixels = 8'h00;
                endcase
            end
            8'h4e: begin // N
                unique case (row8)
                    3'd0: pixels = 8'h66;
                    3'd1: pixels = 8'h76;
                    3'd2: pixels = 8'h7e;
                    3'd3: pixels = 8'h7e;
                    3'd4: pixels = 8'h6e;
                    3'd5: pixels = 8'h66;
                    3'd6: pixels = 8'h66;
                    default: pixels = 8'h00;
                endcase
            end
            8'h4f: begin // O
                unique case (row8)
                    3'd0: pixels = 8'h3c;
                    3'd1: pixels = 8'h66;
                    3'd2: pixels = 8'h66;
                    3'd3: pixels = 8'h66;
                    3'd4: pixels = 8'h66;
                    3'd5: pixels = 8'h66;
                    3'd6: pixels = 8'h3c;
                    default: pixels = 8'h00;
                endcase
            end
            8'h50: begin // P
                unique case (row8)
                    3'd0: pixels = 8'h7c;
                    3'd1: pixels = 8'h66;
                    3'd2: pixels = 8'h66;
                    3'd3: pixels = 8'h7c;
                    3'd4: pixels = 8'h60;
                    3'd5: pixels = 8'h60;
                    3'd6: pixels = 8'h60;
                    default: pixels = 8'h00;
                endcase
            end
            8'h51: begin // Q
                unique case (row8)
                    3'd0: pixels = 8'h3c;
                    3'd1: pixels = 8'h66;
                    3'd2: pixels = 8'h66;
                    3'd3: pixels = 8'h66;
                    3'd4: pixels = 8'h6a;
                    3'd5: pixels = 8'h6c;
                    3'd6: pixels = 8'h36;
                    default: pixels = 8'h00;
                endcase
            end
            8'h52: begin // R
                unique case (row8)
                    3'd0: pixels = 8'h7c;
                    3'd1: pixels = 8'h66;
                    3'd2: pixels = 8'h66;
                    3'd3: pixels = 8'h7c;
                    3'd4: pixels = 8'h78;
                    3'd5: pixels = 8'h6c;
                    3'd6: pixels = 8'h66;
                    default: pixels = 8'h00;
                endcase
            end
            8'h53: begin // S
                unique case (row8)
                    3'd0: pixels = 8'h3c;
                    3'd1: pixels = 8'h66;
                    3'd2: pixels = 8'h60;
                    3'd3: pixels = 8'h3c;
                    3'd4: pixels = 8'h06;
                    3'd5: pixels = 8'h66;
                    3'd6: pixels = 8'h3c;
                    default: pixels = 8'h00;
                endcase
            end
            8'h54: begin // T
                unique case (row8)
                    3'd0: pixels = 8'h7e;
                    3'd1: pixels = 8'h18;
                    3'd2: pixels = 8'h18;
                    3'd3: pixels = 8'h18;
                    3'd4: pixels = 8'h18;
                    3'd5: pixels = 8'h18;
                    3'd6: pixels = 8'h18;
                    default: pixels = 8'h00;
                endcase
            end
            8'h55: begin // U
                unique case (row8)
                    3'd0: pixels = 8'h66;
                    3'd1: pixels = 8'h66;
                    3'd2: pixels = 8'h66;
                    3'd3: pixels = 8'h66;
                    3'd4: pixels = 8'h66;
                    3'd5: pixels = 8'h66;
                    3'd6: pixels = 8'h3c;
                    default: pixels = 8'h00;
                endcase
            end
            8'h56: begin // V
                unique case (row8)
                    3'd0: pixels = 8'h66;
                    3'd1: pixels = 8'h66;
                    3'd2: pixels = 8'h66;
                    3'd3: pixels = 8'h66;
                    3'd4: pixels = 8'h66;
                    3'd5: pixels = 8'h3c;
                    3'd6: pixels = 8'h18;
                    default: pixels = 8'h00;
                endcase
            end
            8'h57: begin // W
                unique case (row8)
                    3'd0: pixels = 8'h63;
                    3'd1: pixels = 8'h63;
                    3'd2: pixels = 8'h63;
                    3'd3: pixels = 8'h6b;
                    3'd4: pixels = 8'h7f;
                    3'd5: pixels = 8'h77;
                    3'd6: pixels = 8'h63;
                    default: pixels = 8'h00;
                endcase
            end
            8'h58, 8'h78: begin // X, x
                unique case (row8)
                    3'd0: pixels = 8'h66;
                    3'd1: pixels = 8'h66;
                    3'd2: pixels = 8'h3c;
                    3'd3: pixels = 8'h18;
                    3'd4: pixels = 8'h3c;
                    3'd5: pixels = 8'h66;
                    3'd6: pixels = 8'h66;
                    default: pixels = 8'h00;
                endcase
            end
            8'h59: begin // Y
                unique case (row8)
                    3'd0: pixels = 8'h66;
                    3'd1: pixels = 8'h66;
                    3'd2: pixels = 8'h3c;
                    3'd3: pixels = 8'h18;
                    3'd4: pixels = 8'h18;
                    3'd5: pixels = 8'h18;
                    3'd6: pixels = 8'h18;
                    default: pixels = 8'h00;
                endcase
            end
            8'h5a: begin // Z
                unique case (row8)
                    3'd0: pixels = 8'h7e;
                    3'd1: pixels = 8'h06;
                    3'd2: pixels = 8'h0c;
                    3'd3: pixels = 8'h18;
                    3'd4: pixels = 8'h30;
                    3'd5: pixels = 8'h60;
                    3'd6: pixels = 8'h7e;
                    default: pixels = 8'h00;
                endcase
            end
            default: pixels = 8'h00;
        endcase
    end

endmodule
