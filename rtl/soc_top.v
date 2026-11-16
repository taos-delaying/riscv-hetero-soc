`timescale 1 ns / 1 ps

// CPU and FFT share 64 KiB of synchronous, true-dual-port memory.
// CPU byte addresses: 0x0000_0000 through 0x0000_ffff.
// The existing dispatcher supplies 14-bit word addresses on memory port B.
module soc_top #(
    parameter MEM_INIT_FILE = "",
    parameter [31:0] PROGADDR_RESET = 32'h0000_0000,
    parameter [31:0] STACKADDR = 32'h0001_0000
) (
    input  wire clk,
    input  wire resetn,
    output wire trap,
    output wire mem_fault,
    output wire fft_done
);
    // Assert external reset across at least one rising clock edge.
    // Delay release so CPU, dispatcher and memory bridge share several reset
    // edges. In particular, this drains the dispatcher's decode/wait pipeline.
    reg [1:0] reset_release;
    always @(posedge clk) begin
        if (!resetn)
            reset_release <= 2'b00;
        else
            reset_release <= {reset_release[0], 1'b1};
    end
    wire system_resetn = resetn && reset_release[1];

    wire cpu_trap;
    wire        mem_valid;
    wire        mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [ 3:0] mem_wstrb;
    wire [31:0] mem_rdata;

    wire        pcpi_valid;
    wire [31:0] pcpi_insn;
    wire [31:0] pcpi_rs1;
    wire [31:0] pcpi_rs2;
    wire        pcpi_wr;
    wire [31:0] pcpi_rd;
    wire        pcpi_wait;
    wire        pcpi_ready;

    wire        fft_sram_en;
    wire [ 3:0] fft_sram_we;
    wire [13:0] fft_sram_addr;
    wire [31:0] fft_sram_wdata;
    wire [31:0] fft_sram_rdata;

    picorv32_new #(
        .ENABLE_PCPI   (1),
        .PROGADDR_RESET(PROGADDR_RESET),
        .STACKADDR     (STACKADDR)
    ) cpu (
        .clk         (clk),
        .resetn      (system_resetn),
        .trap        (cpu_trap),

        .mem_valid   (mem_valid),
        .mem_instr   (),
        .mem_ready   (mem_ready),
        .mem_addr    (mem_addr),
        .mem_wdata   (mem_wdata),
        .mem_wstrb   (mem_wstrb),
        .mem_rdata   (mem_rdata),

        .mem_la_read (),
        .mem_la_write(),
        .mem_la_addr (),
        .mem_la_wdata(),
        .mem_la_wstrb(),

        .pcpi_valid  (pcpi_valid),
        .pcpi_insn   (pcpi_insn),
        .pcpi_rs1    (pcpi_rs1),
        .pcpi_rs2    (pcpi_rs2),
        .pcpi_wr     (pcpi_wr),
        .pcpi_rd     (pcpi_rd),
        .pcpi_wait   (pcpi_wait),
        .pcpi_ready  (pcpi_ready),

        .irq         (32'b0),
        .eoi         (),
        .trace_valid (),
        .trace_data  ()
    );

    pcpi_dispatch fft (
        .clk         (clk),
        .resetn      (system_resetn),
        .pcpi_valid  (pcpi_valid),
        .pcpi_insn   (pcpi_insn),
        .pcpi_rs1    (pcpi_rs1),
        .pcpi_rs2    (pcpi_rs2),
        .pcpi_wr     (pcpi_wr),
        .pcpi_rd     (pcpi_rd),
        .pcpi_wait   (pcpi_wait),
        .pcpi_ready  (pcpi_ready),
        .sram_en     (fft_sram_en),
        .sram_we     (fft_sram_we),
        .sram_addr   (fft_sram_addr),
        .sram_wdata  (fft_sram_wdata),
        .sram_rdata  (fft_sram_rdata)
    );

    // Native CPU valid/ready -> synchronous RAM port A.
    // Edge 1: RAM accepts a request and updates its registered read output;
    //         cpu_mem_pending becomes 1.
    // Edge 2: CPU samples ready/data. RAM is NOT enabled again for this request.
    // The CPU holds its request until the ready handshake, as required by its
    // native interface. Read data remains available through edge 2.
    reg cpu_mem_pending;
    reg cpu_mem_fault;
    wire cpu_addr_in_range = mem_addr[31:16] == 16'b0;
    wire cpu_mem_request = system_resetn && mem_valid &&
                           !cpu_mem_pending && !cpu_mem_fault;
    wire cpu_sram_en = cpu_mem_request && cpu_addr_in_range;

    always @(posedge clk) begin
        if (!system_resetn) begin
            cpu_mem_pending <= 1'b0;
            cpu_mem_fault <= 1'b0;
        end else begin
            cpu_mem_pending <= 1'b0;
            if (cpu_mem_request) begin
                if (cpu_addr_in_range)
                    cpu_mem_pending <= 1'b1;
                else
                    cpu_mem_fault <= 1'b1;
            end
        end
    end

    assign mem_ready = system_resetn && cpu_mem_pending && !cpu_mem_fault;
    assign mem_fault = cpu_mem_fault;
    // mem_fault is a system-level fault: an unmapped CPU request is left
    // unacknowledged until reset. It is not an exception injected into the CPU.
    assign trap = cpu_trap || cpu_mem_fault;
    assign fft_done = system_resetn && pcpi_valid && pcpi_ready;

    soc_sram_dp #(
        .INIT_FILE(MEM_INIT_FILE)
    ) sram (
        .clk    (clk),
        .a_en   (cpu_sram_en),
        .a_we   (mem_wstrb),
        .a_addr (mem_addr[15:2]),
        .a_wdata(mem_wdata),
        .a_rdata(mem_rdata),
        .b_en   (system_resetn && fft_sram_en),
        .b_we   (fft_sram_we),
        .b_addr (fft_sram_addr),
        .b_wdata(fft_sram_wdata),
        .b_rdata(fft_sram_rdata)
    );
endmodule
