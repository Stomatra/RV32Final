`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/22/2025 03:04:25 PM
// Design Name: 
// Module Name: counter
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


module counter(
    input  logic         cpu_clk,
    input  logic         cnt_clk,
    input  logic         rst,

    input  logic [31:0]  perip_wdata,
    input  logic         cnt_wen,
    output logic [31:0]  perip_rdata
);
	// counter 是一个跨时钟域的毫秒计时器外设：
	// - CPU 域写入 START/STOP 控制计时是否运行
	// - 计数逻辑运行在 cnt_clk 域
	// - 计数结果通过 Gray code 同步回 CPU 域供软件读取
    localparam START_CMD = 32'h8000_0000;
    localparam STOP_CMD  = 32'hFFFF_FFFF;

    logic [15:0] cnt_1ms;
    logic [31:0] cnt_ms;
    logic [31:0] cnt_ms_gray;
    logic start;
    logic cmd_toggle_cpu;
    logic cmd_value_cpu;
    logic cmd_toggle_seen;
    logic cmd_write_valid;

    (* ASYNC_REG = "TRUE" *) logic        cmd_toggle_sync1;
    (* ASYNC_REG = "TRUE" *) logic        cmd_toggle_sync2;
    (* ASYNC_REG = "TRUE" *) logic        cmd_value_sync1;
    (* ASYNC_REG = "TRUE" *) logic        cmd_value_sync2;
    (* ASYNC_REG = "TRUE" *) logic [31:0] cnt_ms_gray_sync1;
    (* ASYNC_REG = "TRUE" *) logic [31:0] cnt_ms_gray_sync2;

	// Gray code 转二进制，避免多 bit 异步采样时的瞬态错误。
    function automatic logic [31:0] gray_to_binary(input logic [31:0] gray_value);
        integer bit_idx;
        begin
            gray_to_binary[31] = gray_value[31];
            for (bit_idx = 30; bit_idx >= 0; bit_idx = bit_idx - 1) begin
                gray_to_binary[bit_idx] = gray_to_binary[bit_idx + 1] ^ gray_value[bit_idx];
            end
        end
    endfunction

	// 只有写入 START/STOP 命令时，才认为是有效控制写。
    assign cmd_write_valid = cnt_wen && ((perip_wdata == START_CMD) || (perip_wdata == STOP_CMD));
    assign cnt_ms_gray = cnt_ms ^ (cnt_ms >> 1);
    assign perip_rdata = gray_to_binary(cnt_ms_gray_sync2);

	// CPU 域负责：
	// 1. 把计数结果同步回来
	// 2. 通过 toggle + value 形式把启停命令发往计数域
    always_ff @(posedge cpu_clk or posedge rst) begin
        if (rst) begin
            cmd_toggle_cpu <= 1'b0;
            cmd_value_cpu <= 1'b0;
            cnt_ms_gray_sync1 <= 32'h0;
            cnt_ms_gray_sync2 <= 32'h0;
        end else begin
            cnt_ms_gray_sync1 <= cnt_ms_gray;
            cnt_ms_gray_sync2 <= cnt_ms_gray_sync1;

            if (cmd_write_valid) begin
                cmd_toggle_cpu <= ~cmd_toggle_cpu;
                cmd_value_cpu <= (perip_wdata == START_CMD);
            end
        end
    end

	// 计数域消费 toggle 事件，并更新 start 状态。
    always_ff @(posedge cnt_clk or posedge rst) begin
        if (rst) begin
            cmd_toggle_sync1 <= 1'b0;
            cmd_toggle_sync2 <= 1'b0;
            cmd_value_sync1 <= 1'b0;
            cmd_value_sync2 <= 1'b0;
            cmd_toggle_seen <= 1'b0;
            start <= 1'b0;
        end else begin
            cmd_toggle_sync1 <= cmd_toggle_cpu;
            cmd_toggle_sync2 <= cmd_toggle_sync1;
            cmd_value_sync1 <= cmd_value_cpu;
            cmd_value_sync2 <= cmd_value_sync1;

            if (cmd_toggle_sync2 != cmd_toggle_seen) begin
                cmd_toggle_seen <= cmd_toggle_sync2;
                start <= cmd_value_sync2;
            end
        end
    end

	// 以 50MHz 为例，50000 个时钟周期约为 1ms。
    always_ff @(posedge cnt_clk or posedge rst) begin
        if (rst) begin
            cnt_1ms <= 0;
        end else if (start) begin
            if (cnt_1ms == 49999) begin
                cnt_1ms <= 0;
            end else begin
                cnt_1ms <= cnt_1ms + 1;
            end
        end else begin
            cnt_1ms <= 0;
        end
    end

	// 每出现一个 1ms tick，就把毫秒总数加一。
    always_ff @(posedge cnt_clk or posedge rst) begin
        if (rst) begin
            cnt_ms <= 0;
        end else if (start && cnt_1ms == 49999) begin
            cnt_ms <= cnt_ms + 1;
        end
    end

endmodule
