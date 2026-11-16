`timescale 1 ns / 1 ps

module pcpi_dispatch(
    input clk, resetn,

    input             pcpi_valid,
	input      [31:0] pcpi_insn,
	input      [31:0] pcpi_rs1,
	input      [31:0] pcpi_rs2,
	output            pcpi_wr,
	output     [31:0] pcpi_rd,
	output reg        pcpi_wait,
	output reg        pcpi_ready,

    output            sram_en,//本拍是否访问SRAM
    output reg [3:0]  sram_we,//4个字节的写使能
    output reg [13:0] sram_addr,//要访问的字下标。SRAM总大小64KiB
    output     [31:0] sram_wdata,
    input      [31:0] sram_rdata
);
    assign pcpi_rd = 32'd0;
    assign pcpi_wr = 1'b0;

    reg instr_fft_32, instr_fft_16;
    wire instr_any_fft = |{instr_fft_32, instr_fft_16};
    //wire instr_any_fft = |pcpi_insn[28:25]; 不能这样写，忽略了pcpi_valid信号

    reg pcpi_wait_q;
	wire fft_start = pcpi_wait && !pcpi_wait_q;

    //译码单元
	always @(posedge clk) begin
		instr_fft_32 <= 0;
		instr_fft_16 <= 0;

		if (resetn && pcpi_valid && pcpi_insn[6:0] == 7'b0101011 && pcpi_insn[31:29] == 3'b010 && pcpi_insn[14:12] == 3'b000) begin
			case (pcpi_insn[28:25])
				4'b0101: instr_fft_32 <= 1;
				4'b0100: instr_fft_16 <= 1;
			endcase
		end

		pcpi_wait <= instr_any_fft;
		pcpi_wait_q <= pcpi_wait;
	end

    reg [4:0] fft_counter;
    reg fft_waiting;
    reg [31:0] fft_in [0:31];
    wire [31:0] fft_out [0:31];

    reg read_sram_en, write_sram_en, read_valid;
    assign sram_en = read_sram_en | write_sram_en;

    //读SRAM，用于FFT计算
    always @(posedge clk) begin//给它地址，下一拍才能读到你要的数据，所以地址要比数据早1拍
        if (resetn && read_valid) begin
            fft_in[fft_counter] <= sram_rdata;
        end
    end

    // always @(posedge clk) begin
    //     if (!resetn) begin
    //         read_valid <= 0;
    //     end
    //     else 
    //         read_valid <= read_sram_en;
    // end

    reg fft_compute_start, fft_finish;
    reg [13:0] output_sram_addr;

    //控制逻辑
    reg [3:0] FFT_STATE, FFT_NEXT;
    localparam IDLE    = 3'b000;
    localparam READ_BEGIN    = 3'b001;
    localparam READ_MIDDLE = 3'b010;
    localparam READ_END = 3'b011;
    localparam COMPUTE_MIDDLE   = 3'b100;
    localparam COMPUTE_END    = 3'b101;
    localparam WRITE_MIDDLE   = 3'b110;
    localparam WRITE_END  = 3'b111;

    // 次态组合逻辑 ///今天学到非常棒的这一招：时序逻辑里面用作条件判断的是组合逻辑信号！
    always @(*) begin
        FFT_NEXT = FFT_STATE;            // 默认保持
        case (FFT_STATE)
            IDLE:        if (fft_start) FFT_NEXT = READ_BEGIN;
            READ_BEGIN:  FFT_NEXT = READ_MIDDLE;
            READ_MIDDLE: if (fft_counter == 5'd31) FFT_NEXT = READ_END;
            READ_END:    FFT_NEXT = COMPUTE_MIDDLE;
            COMPUTE_MIDDLE: if(fft_counter == 5'd5) FFT_NEXT = COMPUTE_END;
            COMPUTE_END: FFT_NEXT = WRITE_MIDDLE;
            WRITE_MIDDLE:if (fft_counter == 5'd31) FFT_NEXT = WRITE_END;
            WRITE_END:   FFT_NEXT = IDLE;
            default:     FFT_NEXT = IDLE;
        endcase
    end

    // 状态寄存器
    always @(posedge clk) begin
        if (!resetn) FFT_STATE <= IDLE;
        else         FFT_STATE <= FFT_NEXT;
    end

    // 动作逻辑：基于 next_state（或 next_state 与当前 state 结合）
    always @(posedge clk) begin
        if (!resetn) begin
            read_sram_en  <= 0;
            read_valid <= 0;
            write_sram_en <= 0;
            sram_we       <= 4'b0000;
            fft_compute_start <= 0;
            fft_finish <= 0;
        end
        else begin
            case (FFT_NEXT)
                IDLE:begin
                    sram_addr        <= pcpi_rs1[15:2];
                    fft_counter      <= 5'd0;
                    read_sram_en     <= instr_any_fft;
                    read_valid <= 0;
                    write_sram_en    <= 0;
                    sram_we          <= 4'b0000;
                    fft_compute_start <= 0;
                    fft_finish <= 0;
                end
                READ_BEGIN: begin
                    read_sram_en <= 1;
                    read_valid <= 1;
                    sram_addr <= sram_addr + 1;
                    fft_counter <= 0;
                    write_sram_en    <= 0;
                    sram_we          <= 4'b0000;
                    fft_compute_start <= 0;
                    fft_finish <= 0;
                end
                READ_MIDDLE: begin
                    read_sram_en <= 1;
                    read_valid <= 1;
                    sram_addr <= sram_addr + 1;
                    fft_counter <= fft_counter + 1;
                    write_sram_en    <= 0;
                    sram_we          <= 4'b0000;
                    fft_compute_start <= 0;
                    fft_finish <= 0;
                end
                READ_END:begin
                    read_sram_en <= 0;
                    read_valid <= 0;
                    sram_addr <= 14'd0;
                    fft_counter <= 5'd0;
                    write_sram_en    <= 0;
                    sram_we          <= 4'b0000;
                    fft_compute_start <= 1;
                    fft_finish <= 0;
                end
                COMPUTE_MIDDLE:begin
                    read_sram_en <= 0;
                    read_valid <= 0;
                    sram_addr <= 14'd0;
                    fft_counter <= fft_counter + 1;
                    write_sram_en    <= 0;
                    sram_we          <= 4'b0000;
                    fft_compute_start <= 1;
                    fft_finish <= 0;
                end
                COMPUTE_END:begin
                    read_sram_en <= 0;
                    read_valid <= 0;
                    sram_addr <= pcpi_rs2[15:2];
                    fft_counter <= 5'd0;
                    write_sram_en    <= 1;
                    sram_we          <= 4'b1111;
                    fft_compute_start <= 0;
                    fft_finish <= 0;
                end
                WRITE_MIDDLE:begin
                    read_sram_en <= 0;
                    read_valid <= 0;
                    sram_addr <= sram_addr + 1;
                    fft_counter <= fft_counter + 1;
                    write_sram_en    <= 1;
                    sram_we          <= 4'b1111;
                    fft_compute_start <= 0;
                    fft_finish <= 0;
                end
                WRITE_END:begin
                    read_sram_en <= 0;
                    read_valid <= 0;
                    sram_addr <= 14'd0;
                    fft_counter <= 5'd0;
                    write_sram_en    <= 0;
                    sram_we          <= 4'b0000;
                    fft_compute_start <= 0;
                    fft_finish <= 1;
                end
            endcase
        end
    end

    // always @(posedge clk) begin
    //     fft_finish <= 0;
	// 	if (!resetn) begin
	// 		fft_waiting <= 1;
    //         read_sram_en <= 0;
    //         write_sram_en <= 0;
    //     end else if (fft_waiting) begin
    //         sram_addr <= pcpi_rs1[15:2];//SRAM地址是字下标
    //         output_sram_addr <= pcpi_rs2[15:2];
	// 		fft_counter <= 5'd0;//最大值不能达到N fft的点数
	// 		fft_waiting <= !fft_start;
    //         read_sram_en <= pcpi_wait;
    //         write_sram_en <= 0;
    //         sram_we <= 4'b0000;
	// 	end else begin
    //         sram_addr <= sram_addr + 1;
	// 		fft_counter <= fft_counter + 1;
	// 		if (read_sram_en && fft_counter == 5'd31) begin
    //             read_sram_en <= 0;
	// 			fft_compute_start <= 1;
	// 		end
    //         else if (fft_compute_start && fft_counter == pcpi_insn[28:25]) begin//后续优化，是2^N + N
    //             read_sram_en <= 0;//我想用有限状态机！(后续可选是否修改)
    //             write_sram_en <= 1;
    //             sram_addr <= output_sram_addr;
    //             sram_we <= 4'b1111;
    //             fft_counter <= 5'd0;//下面是写SRAM再到31之后，要怎么做 fft_finish
    //             fft_compute_start <= 0;
    //         end
    //         else if (write_sram_en && fft_counter == 5'd31) begin
    //             write_sram_en <= 0;
    //             sram_we <= 4'b0000;
    //             fft_finish <= 1;

    //             fft_waiting <= 1;
    //         end
	// 	end
	// end

    //写SRAM，用于保存FFT计算结果
    assign sram_wdata = fft_out[fft_counter];

    fft32_dit2 fft32_dit2_inst1 (
        .clk(clk),
        .rst_n(resetn & (fft_compute_start | write_sram_en)),
        .data0_in_real(fft_in[0][15:0]),
        .data0_in_imag(fft_in[0][31:16]),
        .data1_in_real(fft_in[1][15:0]),
        .data1_in_imag(fft_in[1][31:16]),
        .data2_in_real(fft_in[2][15:0]),
        .data2_in_imag(fft_in[2][31:16]),
        .data3_in_real(fft_in[3][15:0]),
        .data3_in_imag(fft_in[3][31:16]),
        .data4_in_real(fft_in[4][15:0]),
        .data4_in_imag(fft_in[4][31:16]),
        .data5_in_real(fft_in[5][15:0]),
        .data5_in_imag(fft_in[5][31:16]),
        .data6_in_real(fft_in[6][15:0]),
        .data6_in_imag(fft_in[6][31:16]),
        .data7_in_real(fft_in[7][15:0]),
        .data7_in_imag(fft_in[7][31:16]),
        .data8_in_real(fft_in[8][15:0]),
        .data8_in_imag(fft_in[8][31:16]),
        .data9_in_real(fft_in[9][15:0]),
        .data9_in_imag(fft_in[9][31:16]),
        .data10_in_real(fft_in[10][15:0]),
        .data10_in_imag(fft_in[10][31:16]),
        .data11_in_real(fft_in[11][15:0]),
        .data11_in_imag(fft_in[11][31:16]),
        .data12_in_real(fft_in[12][15:0]),
        .data12_in_imag(fft_in[12][31:16]),
        .data13_in_real(fft_in[13][15:0]),
        .data13_in_imag(fft_in[13][31:16]),
        .data14_in_real(fft_in[14][15:0]),
        .data14_in_imag(fft_in[14][31:16]),
        .data15_in_real(fft_in[15][15:0]),
        .data15_in_imag(fft_in[15][31:16]),
        .data16_in_real(fft_in[16][15:0]),
        .data16_in_imag(fft_in[16][31:16]),
        .data17_in_real(fft_in[17][15:0]),
        .data17_in_imag(fft_in[17][31:16]),
        .data18_in_real(fft_in[18][15:0]),
        .data18_in_imag(fft_in[18][31:16]),
        .data19_in_real(fft_in[19][15:0]),
        .data19_in_imag(fft_in[19][31:16]),
        .data20_in_real(fft_in[20][15:0]),
        .data20_in_imag(fft_in[20][31:16]),
        .data21_in_real(fft_in[21][15:0]),
        .data21_in_imag(fft_in[21][31:16]),
        .data22_in_real(fft_in[22][15:0]),
        .data22_in_imag(fft_in[22][31:16]),
        .data23_in_real(fft_in[23][15:0]),
        .data23_in_imag(fft_in[23][31:16]),
        .data24_in_real(fft_in[24][15:0]),
        .data24_in_imag(fft_in[24][31:16]),
        .data25_in_real(fft_in[25][15:0]),
        .data25_in_imag(fft_in[25][31:16]),
        .data26_in_real(fft_in[26][15:0]),
        .data26_in_imag(fft_in[26][31:16]),
        .data27_in_real(fft_in[27][15:0]),
        .data27_in_imag(fft_in[27][31:16]),
        .data28_in_real(fft_in[28][15:0]),
        .data28_in_imag(fft_in[28][31:16]),
        .data29_in_real(fft_in[29][15:0]),
        .data29_in_imag(fft_in[29][31:16]),
        .data30_in_real(fft_in[30][15:0]),
        .data30_in_imag(fft_in[30][31:16]),
        .data31_in_real(fft_in[31][15:0]),
        .data31_in_imag(fft_in[31][31:16]),
        .data0_out_real(fft_out[0][15:0]),
        .data0_out_imag(fft_out[0][31:16]),
        .data1_out_real(fft_out[1][15:0]),
        .data1_out_imag(fft_out[1][31:16]),
        .data2_out_real(fft_out[2][15:0]),
        .data2_out_imag(fft_out[2][31:16]),
        .data3_out_real(fft_out[3][15:0]),
        .data3_out_imag(fft_out[3][31:16]),
        .data4_out_real(fft_out[4][15:0]),
        .data4_out_imag(fft_out[4][31:16]),
        .data5_out_real(fft_out[5][15:0]),
        .data5_out_imag(fft_out[5][31:16]),
        .data6_out_real(fft_out[6][15:0]),
        .data6_out_imag(fft_out[6][31:16]),
        .data7_out_real(fft_out[7][15:0]),
        .data7_out_imag(fft_out[7][31:16]),
        .data8_out_real(fft_out[8][15:0]),
        .data8_out_imag(fft_out[8][31:16]),
        .data9_out_real(fft_out[9][15:0]),
        .data9_out_imag(fft_out[9][31:16]),
        .data10_out_real(fft_out[10][15:0]),
        .data10_out_imag(fft_out[10][31:16]),
        .data11_out_real(fft_out[11][15:0]),
        .data11_out_imag(fft_out[11][31:16]),
        .data12_out_real(fft_out[12][15:0]),
        .data12_out_imag(fft_out[12][31:16]),
        .data13_out_real(fft_out[13][15:0]),
        .data13_out_imag(fft_out[13][31:16]),
        .data14_out_real(fft_out[14][15:0]),
        .data14_out_imag(fft_out[14][31:16]),
        .data15_out_real(fft_out[15][15:0]),
        .data15_out_imag(fft_out[15][31:16]),
        .data16_out_real(fft_out[16][15:0]),
        .data16_out_imag(fft_out[16][31:16]),
        .data17_out_real(fft_out[17][15:0]),
        .data17_out_imag(fft_out[17][31:16]),
        .data18_out_real(fft_out[18][15:0]),
        .data18_out_imag(fft_out[18][31:16]),
        .data19_out_real(fft_out[19][15:0]),
        .data19_out_imag(fft_out[19][31:16]),
        .data20_out_real(fft_out[20][15:0]),
        .data20_out_imag(fft_out[20][31:16]),
        .data21_out_real(fft_out[21][15:0]),
        .data21_out_imag(fft_out[21][31:16]),
        .data22_out_real(fft_out[22][15:0]),
        .data22_out_imag(fft_out[22][31:16]),
        .data23_out_real(fft_out[23][15:0]),
        .data23_out_imag(fft_out[23][31:16]),
        .data24_out_real(fft_out[24][15:0]),
        .data24_out_imag(fft_out[24][31:16]),
        .data25_out_real(fft_out[25][15:0]),
        .data25_out_imag(fft_out[25][31:16]),
        .data26_out_real(fft_out[26][15:0]),
        .data26_out_imag(fft_out[26][31:16]),
        .data27_out_real(fft_out[27][15:0]),
        .data27_out_imag(fft_out[27][31:16]),
        .data28_out_real(fft_out[28][15:0]),
        .data28_out_imag(fft_out[28][31:16]),
        .data29_out_real(fft_out[29][15:0]),
        .data29_out_imag(fft_out[29][31:16]),
        .data30_out_real(fft_out[30][15:0]),
        .data30_out_imag(fft_out[30][31:16]),
        .data31_out_real(fft_out[31][15:0]),
        .data31_out_imag(fft_out[31][31:16])
    );

	always @(posedge clk) begin
		//pcpi_wr <= 0;只有后续有需要时，在这里加
		pcpi_ready <= 0;
		if (fft_finish && resetn) begin
			//pcpi_wr <= 1;
			pcpi_ready <= 1;
		end
	end

endmodule