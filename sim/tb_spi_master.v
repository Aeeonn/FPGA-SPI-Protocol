`timescale 1ns/1ps
//=============================================================================
// tb_spi_master.v
// Self-checking unit test for spi_master.v against the ADXL345 SPI model.
//
// Checks:
//  - DEVID read returns 0xE5 (command/addressing + read path)
//  - Write-then-read-back of bit patterns (MSB-first alignment on MOSI/MISO)
//  - Register contents seen by the sensor match what was written
//  - SCLK runs at 500 kHz and idles high (SPI mode 3)
//  - 'done' is a single 50 MHz cycle pulse, one per transfer
//  - Asynchronous reset in the middle of a transfer releases CS and recovers
//
// Run with +vcd to dump tb_spi_master.vcd
//=============================================================================
module tb_spi_master;

    localparam integer CLK_PERIOD_NS       = 20;    // 50 MHz
    localparam integer EXPECTED_SCLK_NS    = 2000;  // 500 kHz

    reg         clk     = 1'b0;
    reg         rst_n   = 1'b0;
    reg         start   = 1'b0;
    reg  [15:0] tx_data = 16'd0;
    wire [7:0]  rx_data;
    wire        done;
    wire        sclk, cs_n, mosi, miso;

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    spi_master dut (
        .clk_50     (clk),
        .rst_n      (rst_n),
        .start      (start),
        .tx_data    (tx_data),
        .rx_data    (rx_data),
        .done       (done),
        .sclk       (sclk),
        .cs_n_accel (cs_n),
        .mosi       (mosi),
        .miso       (miso)
    );

    adxl345_model sensor (
        .sclk     (sclk),
        .cs_n     (cs_n),
        .sdi      (mosi),
        .sdo      (miso),
        .int1     (),
        .int2     (),
        .x_sample (16'd0)
    );

    integer errors     = 0;
    integer checks     = 0;
    integer done_count = 0;
    integer transfers  = 0;

    initial begin
        $timeformat(-9, 0, " ns", 0);
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_spi_master.vcd");
            $dumpvars(0, tb_spi_master);
        end
    end

    // Watchdog
    initial begin
        #(20_000_000);
        $display("FAIL: tb_spi_master timed out");
        $fatal(1);
    end

    // ---------------- Continuous protocol monitors ----------------
    reg done_q = 1'b0;
    always @(posedge clk) begin
        done_q <= done;
        if (done) done_count = done_count + 1;
        if (done && done_q) begin
            errors = errors + 1;
            $display("[%0t] ERROR: 'done' held high for more than one clock cycle", $time);
        end
        if (rst_n && cs_n && !sclk) begin
            errors = errors + 1;
            $display("[%0t] ERROR: SCLK low while CS is deasserted (mode 3 idles high)", $time);
        end
    end

    // Measure the SCLK period during transfers
    time    last_sclk_rise = 0;
    integer sclk_periods   = 0;
    always @(posedge sclk) begin
        if (!cs_n && rst_n) begin
            if (last_sclk_rise != 0) begin
                sclk_periods = sclk_periods + 1;
                if ($time - last_sclk_rise != EXPECTED_SCLK_NS) begin
                    errors = errors + 1;
                    $display("[%0t] ERROR: SCLK period %0t ns, expected %0d ns", $time, $time - last_sclk_rise, EXPECTED_SCLK_NS);
                end
            end
            last_sclk_rise = $time;
        end else begin
            last_sclk_rise = 0;
        end
    end
    always @(posedge cs_n) last_sclk_rise = 0;

    // ---------------- Driver tasks ----------------
    task spi_transfer(input [15:0] word, output [7:0] data);
        begin
            @(posedge clk);
            tx_data <= word;
            start   <= 1'b1;
            @(posedge clk);
            while (done !== 1'b1) @(posedge clk);
            data  = rx_data;
            start <= 1'b0;
            transfers = transfers + 1;
        end
    endtask

    task write_reg(input [5:0] addr, input [7:0] value);
        reg [7:0] unused;
        begin
            spi_transfer({2'b00, addr, value}, unused);
        end
    endtask

    task read_reg(input [5:0] addr, output [7:0] value);
        begin
            spi_transfer({2'b10, addr, 8'h00}, value);
        end
    endtask

    task check8(input [8*40-1:0] what, input [7:0] got, input [7:0] expected);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("[%0t] ERROR: %0s: got 0x%02h, expected 0x%02h", $time, what, got, expected);
            end else begin
                $display("[%0t] ok: %0s = 0x%02h", $time, what, got);
            end
        end
    endtask

    // ---------------- Test sequence ----------------
    reg [7:0] rd;
    reg [7:0] patterns [0:5];
    integer   k;
    integer   aborted_before;

    initial begin
        patterns[0] = 8'h00; patterns[1] = 8'hFF; patterns[2] = 8'hA5;
        patterns[3] = 8'h5A; patterns[4] = 8'h01; patterns[5] = 8'h80;

        repeat (5) @(posedge clk);
        if (cs_n !== 1'b1 || sclk !== 1'b1) begin
            errors = errors + 1;
            $display("ERROR: CS/SCLK not idle-high during reset");
        end
        rst_n = 1'b1;

        // 1) Device ID
        read_reg(6'h00, rd);
        check8("DEVID", rd, 8'hE5);

        // 2) Write / read-back patterns through OFSX (0x1E)
        for (k = 0; k < 6; k = k + 1) begin
            write_reg(6'h1E, patterns[k]);
            check8("sensor OFSX register after write", sensor.regs[6'h1E], patterns[k]);
            read_reg(6'h1E, rd);
            check8("OFSX read-back", rd, patterns[k]);
        end

        // 3) Back-to-back writes to different registers
        write_reg(6'h2D, 8'h08);
        write_reg(6'h2E, 8'h80);
        read_reg(6'h2D, rd);
        check8("POWER_CTL read-back", rd, 8'h08);
        read_reg(6'h2E, rd);
        check8("INT_ENABLE read-back", rd, 8'h80);

        // 4) Reset in the middle of a transfer
        aborted_before = sensor.aborted;
        @(posedge clk);
        tx_data <= 16'h9E00;
        start   <= 1'b1;
        @(negedge cs_n);
        start   <= 1'b0;
        #(5_500);  // mid-transfer, while SCLK is low
        rst_n = 1'b0;
        #(100);
        checks = checks + 1;
        if (cs_n !== 1'b1 || sclk !== 1'b1) begin
            errors = errors + 1;
            $display("[%0t] ERROR: reset did not release CS / return SCLK high", $time);
        end
        if (sensor.aborted != aborted_before + 1) begin
            errors = errors + 1;
            $display("[%0t] ERROR: sensor did not see the aborted transfer", $time);
        end
        rst_n = 1'b1;
        read_reg(6'h00, rd);
        check8("DEVID after mid-transfer reset", rd, 8'hE5);

        repeat (200) @(posedge clk);

        // ---------------- Summary ----------------
        checks = checks + 1;
        if (done_count != transfers) begin
            errors = errors + 1;
            $display("ERROR: %0d done pulses for %0d transfers", done_count, transfers);
        end
        if (sclk_periods == 0) begin
            errors = errors + 1;
            $display("ERROR: no SCLK periods were measured");
        end
        if (sensor.transactions != transfers) begin
            errors = errors + 1;
            $display("ERROR: sensor saw %0d complete transactions, expected %0d", sensor.transactions, transfers);
        end
        errors = errors + sensor.errors;

        $display("------------------------------------------------------------");
        $display("tb_spi_master: %0d transfers, %0d checks, %0d SCLK periods measured", transfers, checks, sclk_periods);
        if (errors == 0) begin
            $display("TEST PASSED: tb_spi_master");
            $finish;
        end else begin
            $display("TEST FAILED: tb_spi_master (%0d errors)", errors);
            $fatal(1);
        end
    end
endmodule
