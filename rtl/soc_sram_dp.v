`timescale 1 ns / 1 ps

// 16384 words x 32 bits = 64 KiB; both ports use WORD addresses.
// Synchronous read: an enabled rising edge samples the address and updates
// rdata after that edge. rdata holds its value while the port is disabled.
// Write masks select individual byte lanes; zero means a read-only access.
//
// This is an FPGA RAM inference model, not an ASIC SRAM macro instance.
// Neither the array nor read-output registers are reset.
// Keep CPU code/stack and FFT buffers separate. Simultaneous accesses to the
// same word on different ports, with either port writing, are not supported.
module soc_sram_dp #(
    parameter INIT_FILE = ""
) (
    input  wire        clk,
    input  wire        a_en,
    input  wire [ 3:0] a_we,
    input  wire [13:0] a_addr,
    input  wire [31:0] a_wdata,
    output reg  [31:0] a_rdata,
    input  wire        b_en,
    input  wire [ 3:0] b_we,
    input  wire [13:0] b_addr,
    input  wire [31:0] b_wdata,
    output reg  [31:0] b_rdata
);
    reg [31:0] mem [0:16383];

    // Optional FPGA configuration-time contents, one 32-bit hex word per
    // entry. An empty filename leaves contents unspecified; reset does not
    // reload the file. For ASIC use, supply a separate program-loading path.
    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    always @(posedge clk) begin
        if (a_en) begin
            if (a_we[0]) mem[a_addr][ 7: 0] <= a_wdata[ 7: 0];
            if (a_we[1]) mem[a_addr][15: 8] <= a_wdata[15: 8];
            if (a_we[2]) mem[a_addr][23:16] <= a_wdata[23:16];
            if (a_we[3]) mem[a_addr][31:24] <= a_wdata[31:24];
            a_rdata <= mem[a_addr];
        end
    end

    always @(posedge clk) begin
        if (b_en) begin
            if (b_we[0]) mem[b_addr][ 7: 0] <= b_wdata[ 7: 0];
            if (b_we[1]) mem[b_addr][15: 8] <= b_wdata[15: 8];
            if (b_we[2]) mem[b_addr][23:16] <= b_wdata[23:16];
            if (b_we[3]) mem[b_addr][31:24] <= b_wdata[31:24];
            b_rdata <= mem[b_addr];
        end
    end
endmodule
