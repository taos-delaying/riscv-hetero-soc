`timescale 1ns / 1ps

// 当前 example_main.c 的系统级功能测试：32 个输入均为 0.5+j0。
// 在下面的配置区选择固件，然后在 Vivado 中启动 Behavioral Simulation。
// 从 MAP 读取变量地址，不写死编译后的布局；不需要 Tcl 脚本或 plusargs。
module tb_soc_fft;
    // ===== 手动配置区 =====
    // 首先使用 "sw" 验证软件版；之后改为 "hw"，关闭仿真并重新启动。
    localparam FIRMWARE_IMPL = "hw";
    // 使用正斜杠的绝对路径，避免依赖 Vivado 仿真的工作目录。
    localparam PROJECT_ROOT = "D:/taosh/Documents/vivado/riscv-hetero-soc";
    localparam integer MAX_CYCLES = 1000000;
    // ===== 以下为测试逻辑 =====

    localparam integer RAM_WORDS = 16384;
    localparam integer FFT_POINTS = 32;
    localparam integer POST_DONE_CYCLES = 128;

    reg clk = 1'b0;
    reg resetn = 1'b0;
    wire trap;
    wire mem_fault;
    wire fft_done;

    string mode = FIRMWARE_IMPL;
    string hex_file;
    string map_file;
    integer cycles = 0;
    integer done_cycle = 0;
    integer fft_done_count = 0;
    integer done_word_index = 0;
    integer samples_word_index = 0;
    integer fft_cycles_word_index = 0;
    reg [31:0] measured_fft_cycles = 0;
    integer word_index;
    integer guard_cycle;
    bit saw_done = 1'b0;

    // 先在 TB 内加载并检查镜像，再逐字写入 DUT，分开定位文件读取与 RAM 赋值问题。
    reg [31:0] firmware_image [0:RAM_WORDS-1];

    // 便于波形观察关键位置，不记录整个 64 KiB RAM。
    wire [31:0] completion_value;
    wire [31:0] sample0_value;
    wire [31:0] fft_cycles_value;
    assign completion_value = dut.sram.mem[done_word_index];
    assign sample0_value = dut.sram.mem[samples_word_index];
    assign fft_cycles_value = dut.sram.mem[fft_cycles_word_index];

    // 本测试台是唯一镜像加载入口。保持 DUT 参数为空，避免重复 $readmemh。
    soc_top #(
        .MEM_INIT_FILE("")
    ) dut (
        .clk(clk),
        .resetn(resetn),
        .trap(trap),
        .mem_fault(mem_fault),
        .fft_done(fft_done)
    );

    // 100 MHz 功能仿真时钟；这不代表布局布线后的频率已经验证。
    always #5 clk = ~clk;

    task automatic fail(input string message);
        begin
            $display("[SOC FFT FAIL] mode=%s cycles=%0d %s", mode, cycles, message);
            $fatal(1, "%s", message);
        end
    endtask

    // 只接受 makehex.py 的逐行十六进制字格式：每个非空行1..8位，允许首尾空白。
    // 显式处理 LF/CRLF，绕开当前环境中 $readmemh 未完整加载镜像的路径。
    task automatic read_hex;
        integer fd;
        integer chars_read;
        integer line_number;
        integer words_read;
        integer char_index;
        integer char_code;
        integer digit_count;
        integer digit_value;
        string line;
        reg [31:0] parsed_word;
        bit trailing_space;
        begin
            fd = $fopen(hex_file, "r");
            if (fd == 0)
                fail($sformatf("Cannot open HEX: %s", hex_file));
            line_number = 0;
            words_read = 0;
            $display("[SOC FFT] HEX loader=line-by-line (LF/CRLF accepted)");

            while (!$feof(fd)) begin
                line = "";
                chars_read = $fgets(line, fd);
                if (chars_read == 0) begin
                    if (!$feof(fd))
                        fail($sformatf("HEX read failed after line %0d", line_number));
                end else begin
                    line_number = line_number + 1;
                    parsed_word = 32'd0;
                    digit_count = 0;
                    trailing_space = 0;
                    for (char_index = 0; char_index < line.len(); char_index = char_index + 1) begin
                        char_code = line[char_index];
                        // 空格、TAB、CR、LF；不把换行符交给十六进制转换。
                        if (char_code == 32 || char_code == 9 || char_code == 13 || char_code == 10) begin
                            if (digit_count != 0)
                                trailing_space = 1;
                        end else begin
                            if (trailing_space)
                                fail($sformatf("HEX line %0d contains more than one token", line_number));
                            digit_value = 0;
                            if (char_code >= 48 && char_code <= 57)
                                digit_value = char_code - 48;
                            else if (char_code >= 65 && char_code <= 70)
                                digit_value = char_code - 65 + 10;
                            else if (char_code >= 97 && char_code <= 102)
                                digit_value = char_code - 97 + 10;
                            else
                                fail($sformatf("HEX invalid character 0x%02h at line %0d column %0d",
                                               char_code, line_number, char_index + 1));
                            if (digit_count >= 8)
                                fail($sformatf("HEX word exceeds 32 bits at line %0d", line_number));
                            parsed_word = {parsed_word[27:0], digit_value[3:0]};
                            digit_count = digit_count + 1;
                        end
                    end
                    if (digit_count != 0) begin
                        if (words_read >= RAM_WORDS)
                            fail($sformatf("HEX contains more than %0d words; extra data at line %0d",
                                           RAM_WORDS, line_number));
                        firmware_image[words_read] = parsed_word;
                        words_read = words_read + 1;
                    end
                end
            end
            $fclose(fd);
            if (words_read != RAM_WORDS)
                fail($sformatf("HEX word count mismatch: expected=%0d actual=%0d",
                               RAM_WORDS, words_read));
            $display("[SOC FFT] HEX parsed: words=%0d word[0]=%08h word[1]=%08h word[16383]=%08h",
                     words_read, firmware_image[0], firmware_image[1], firmware_image[RAM_WORDS-1]);
        end
    endtask

    task automatic read_map;
        integer fd;
        integer chars_read;
        integer fields_read;
        string line;
        string symbol;
        reg [63:0] address;
        reg [63:0] start_address;
        reg [63:0] stack_address;
        reg [63:0] done_address;
        reg [63:0] samples_address;
        reg [63:0] fft_cycles_address;
        bit found_start;
        bit found_stack;
        bit found_done;
        bit found_samples;
        bit found_fft_cycles;
        begin
            found_start = 0;
            found_stack = 0;
            found_done = 0;
            found_samples = 0;
            found_fft_cycles = 0;
            start_address = 0;
            stack_address = 0;
            done_address = 0;
            samples_address = 0;
            fft_cycles_address = 0;

            fd = $fopen(map_file, "r");
            if (fd == 0)
                fail($sformatf("Cannot open MAP: %s", map_file));

            while (!$feof(fd)) begin
                line = "";
                chars_read = $fgets(line, fd);
                if (chars_read > 0) begin
                    address = 0;
                    symbol = "";
                    // GNU ld MAP 使用 0x 前缀和可能长达 16 位的地址。
                    fields_read = $sscanf(line, " 0x%h %s", address, symbol);
                    if (fields_read == 2) begin
                        case (symbol)
                            "_start": begin
                                start_address = address;
                                found_start = 1;
                            end
                            "__stack_top": begin
                                stack_address = address;
                                found_stack = 1;
                            end
                            "fft_example_done": begin
                                done_address = address;
                                found_done = 1;
                            end
                            "fft_samples": begin
                                samples_address = address;
                                found_samples = 1;
                            end
                            "fft_cycles": begin
                                fft_cycles_address = address;
                                found_fft_cycles = 1;
                            end
                        endcase
                    end
                end
            end
            $fclose(fd);

            if (!(found_start && found_stack && found_done && found_samples))
                fail("MAP lacks _start, __stack_top, fft_example_done or fft_samples");
            if (!found_fft_cycles)
                fail("MAP lacks fft_cycles; rebuild the selected firmware and update its HEX/MAP together");
            if (start_address !== 64'h0 || stack_address !== 64'h10000)
                fail("MAP reset/stack addresses do not match current soc_top defaults");
            if ((^done_address === 1'bx) || (^samples_address === 1'bx) ||
                (^fft_cycles_address === 1'bx))
                fail("MAP contains an unknown variable address");
            if (done_address[1:0] != 0 || done_address > 64'hfffc)
                fail("Completion flag is unaligned or outside RAM");
            if (samples_address[1:0] != 0 || samples_address > 64'hff80)
                fail("FFT buffer is unaligned or crosses the end of RAM");
            if (fft_cycles_address[1:0] != 0 || fft_cycles_address > 64'hfffc)
                fail("fft_cycles is unaligned or outside RAM");
            if (done_address >= samples_address && done_address < samples_address + 128)
                fail("Completion flag overlaps the FFT buffer");
            if (fft_cycles_address == done_address ||
                (fft_cycles_address >= samples_address && fft_cycles_address < samples_address + 128))
                fail("fft_cycles overlaps the completion flag or FFT buffer");

            done_word_index = done_address[15:2];
            samples_word_index = samples_address[15:2];
            fft_cycles_word_index = fft_cycles_address[15:2];
            $display("[SOC FFT] mode=%s done_addr=0x%08h samples_addr=0x%08h fft_cycles_addr=0x%08h",
                     mode, done_address[31:0], samples_address[31:0], fft_cycles_address[31:0]);
        end
    endtask

    task automatic sample_cycle;
        begin
            if (cycles >= MAX_CYCLES)
                fail($sformatf("Timeout: pc=0x%08h done=0x%08h fft_done_count=%0d",
                               dut.cpu.reg_pc, completion_value, fft_done_count));
            @(posedge clk);
            // 等待 RTL 非阻塞赋值及组合连线稳定，避免采样竞争。
            #1;
            cycles = cycles + 1;
            if (dut.system_resetn !== 1'b0 && dut.system_resetn !== 1'b1)
                fail("Internal reset is unknown");

            if (dut.system_resetn === 1'b1) begin
                if (mem_fault !== 1'b0)
                    fail($sformatf("Memory fault/X: pc=0x%08h mem_addr=0x%08h",
                                   dut.cpu.reg_pc, dut.mem_addr));
                if (trap !== 1'b0)
                    fail($sformatf("CPU trap/X: pc=0x%08h insn=0x%08h",
                                   dut.cpu.reg_pc, dut.pcpi_insn));
                if (fft_done !== 1'b0 && fft_done !== 1'b1)
                    fail("FFT completion signal is unknown");

                if (fft_done === 1'b1) begin
                    fft_done_count = fft_done_count + 1;
                    $display("[SOC FFT] FFT completion pulse at cycle %0d", cycles);
                    if (mode == "sw")
                        fail("Software image unexpectedly executed an FFT hardware instruction");
                    if (fft_done_count > 1)
                        fail("More than one FFT completion pulse for a one-call program");
                end

                if (completion_value !== 32'd0 && completion_value !== 32'd1)
                    fail($sformatf("Invalid completion flag: 0x%08h", completion_value));
                if (saw_done && completion_value !== 32'd1)
                    fail("Completion flag changed after the program finished");
                if (saw_done && fft_cycles_value !== measured_fft_cycles)
                    fail("fft_cycles changed after the program finished");
            end
        end
    endtask

    task automatic check_results;
        integer k;
        integer errors;
        integer real_component;
        integer imag_component;
        reg [31:0] actual;
        reg [31:0] expected;
        begin
            if (mode == "hw" && fft_done_count != 1)
                fail("Hardware image finished without exactly one FFT completion pulse");
            if (mode == "sw" && fft_done_count != 0)
                fail("Software image produced an FFT hardware completion pulse");

            errors = 0;
            for (k = 0; k < FFT_POINTS; k = k + 1) begin
                actual = dut.sram.mem[samples_word_index + k];
                expected = (k == 0) ? 32'h00004000 : 32'h00000000;
                real_component = $signed(actual[15:0]);
                imag_component = $signed(actual[31:16]);
                $display("[SOC FFT] k=%0d real=%0d imag=%0d word=%08h",
                         k, real_component, imag_component, actual);
                if (actual !== expected) begin
                    errors = errors + 1;
                    $display("[SOC FFT] MISMATCH k=%0d expected=%08h actual=%08h",
                             k, expected, actual);
                end
            end
            if (errors != 0)
                fail($sformatf("FFT result mismatch in %0d of 32 bins", errors));

            $display("[SOC FFT PERF] mode=%s fft_cycles=%0d", mode, measured_fft_cycles);
            $display("[SOC FFT PASS] mode=%s program_cycles=%0d fft_done_count=%0d",
                     mode, done_cycle, fft_done_count);
            $display("[SOC FFT] fft_cycles measures the fft32_q15 call including call/return and timing overhead; no overhead subtracted.");
            $display("[SOC FFT] program_cycles includes startup/input preparation; it is NOT FFT-core latency.");
            $finish;
        end
    endtask

    initial begin
        if (mode != "sw" && mode != "hw")
            fail("FIRMWARE_IMPL must be sw or hw");
        if (MAX_CYCLES <= POST_DONE_CYCLES)
            fail("MAX_CYCLES must exceed the post-completion observation window");

        hex_file = {PROJECT_ROOT, "/build/fft32/", mode, "/firmware.hex"};
        map_file = {PROJECT_ROOT, "/build/fft32/", mode, "/firmware.map"};
        $display("[SOC FFT] HEX=%s", hex_file);
        $display("[SOC FFT] MAP=%s", map_file);
        read_map();

        // 先填 X，确保短镜像/未初始化字不会被误判为有效固件。
        for (word_index = 0; word_index < RAM_WORDS; word_index = word_index + 1)
            firmware_image[word_index] = 32'hxxxxxxxx;
        read_hex();
        for (word_index = 0; word_index < RAM_WORDS; word_index = word_index + 1)
            if (^firmware_image[word_index] === 1'bx)
                fail($sformatf("Parsed HEX buffer is unknown: word=%0d value=%08h; file=%s",
                               word_index, firmware_image[word_index], hex_file));

        // 镜像完整性检查通过后才写入 DUT；CPU 此时仍处于复位状态。
        for (word_index = 0; word_index < RAM_WORDS; word_index = word_index + 1)
            dut.sram.mem[word_index] = firmware_image[word_index];
        for (word_index = 0; word_index < RAM_WORDS; word_index = word_index + 1)
            if (dut.sram.mem[word_index] !== firmware_image[word_index])
                fail($sformatf("RAM copy failed: word=%0d expected=%08h actual=%08h",
                               word_index, firmware_image[word_index], dut.sram.mem[word_index]));
        $display("[SOC FFT] Loaded and verified %0d RAM words", RAM_WORDS);
        if (dut.sram.mem[done_word_index] !== 32'd0)
            fail("Completion flag is not zero in the initial image; check HEX/MAP pairing");
        if (dut.sram.mem[fft_cycles_word_index] !== 32'd0)
            fail("fft_cycles is not zero in the initial image; check HEX/MAP pairing");

        repeat (10) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;

        while (!saw_done) begin
            sample_cycle();
            if (dut.system_resetn === 1'b1 && completion_value === 32'd1) begin
                saw_done = 1;
                done_cycle = cycles;
                measured_fft_cycles = fft_cycles_value;
                if ((^measured_fft_cycles === 1'bx) || measured_fft_cycles == 0)
                    fail($sformatf("Invalid fft_cycles=0x%08h; check rebuilt firmware and cycle counter",
                                   measured_fft_cycles));
                if (measured_fft_cycles > done_cycle)
                    fail("fft_cycles exceeds program_cycles; check firmware/image pairing");
                $display("[SOC FFT] Program completion observed at cycle %0d", done_cycle);
            end
        end

        // 再观察一段时间，检查完成后是否有异常/重复调用/意外写回。
        for (guard_cycle = 0; guard_cycle < POST_DONE_CYCLES; guard_cycle = guard_cycle + 1)
            sample_cycle();
        check_results();
    end
endmodule
