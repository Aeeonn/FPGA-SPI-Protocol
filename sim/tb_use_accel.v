`timescale 1ns/1ps
//=============================================================================
// tb_use_accel.v
// System-level test: the USE_ACCEL top level wired to the ADXL345 model.
//
// Checks:
//  - Reset behaviour (HEX0 indicator, SPI bus idle)
//  - ~20 ms power-up delay before the first SPI access
//  - Configuration sequence: INT_ENABLE=0x80, INT_MAP=0x80, POWER_CTL=0x08
//  - Interrupt-driven reads: only reads DATAX after INT2, never misses a sample
//  - X readings reach the LED driver and select the right LED
//  - Re-initialisation after pressing KEY[0] again
//
// The sensor model's output data rate is sped up (ODR_PERIOD_NS) to keep
// simulation short; the RTL is unchanged.
//=============================================================================
module tb_use_accel;

    localparam integer CLK_PERIOD_NS = 20;       // 50 MHz
    localparam integer ODR_PERIOD_NS = 200_000;  // 5 kHz sample rate in simulation
    localparam integer MIN_BOOT_NS   = 20_000_000;

    reg         clk      = 1'b0;
    reg  [1:0]  key      = 2'b10;  // KEY[0] pressed (reset asserted)
    reg  [15:0] x_sample = 16'd0;

    wire [7:0]  hex0, hex1, hex2, hex3, hex4, hex5;
    wire [9:0]  ledr;
    wire [2:1]  gsensor_int;
    wire        sclk, cs_n, sdi, sdo;

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    USE_ACCEL dut (
        .ADC_CLK_10    (1'b0),
        .MAX10_CLK1_50 (clk),
        .MAX10_CLK2_50 (1'b0),
        .HEX0          (hex0),
        .HEX1          (hex1),
        .HEX2          (hex2),
        .HEX3          (hex3),
        .HEX4          (hex4),
        .HEX5          (hex5),
        .KEY           (key),
        .LEDR          (ledr),
        .SW            (10'd0),
        .GSENSOR_CS_N  (cs_n),
        .GSENSOR_INT   (gsensor_int),
        .GSENSOR_SCLK  (sclk),
        .GSENSOR_SDI   (sdi),
        .GSENSOR_SDO   (sdo)
    );

    adxl345_model #(.ODR_PERIOD_NS(ODR_PERIOD_NS)) sensor (
        .sclk     (sclk),
        .cs_n     (cs_n),
        .sdi      (sdi),
        .sdo      (sdo),
        .int1     (gsensor_int[1]),
        .int2     (gsensor_int[2]),
        .x_sample (x_sample)
    );

    integer errors = 0;
    integer checks = 0;

    initial begin
        $timeformat(-6, 1, " us", 0);
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_use_accel.vcd");
            $dumpvars(0, tb_use_accel);
        end
    end

    initial begin
        #(200_000_000);
        $display("FAIL: tb_use_accel timed out");
        $fatal(1);
    end

    task fail(input [8*80-1:0] msg);
        begin
            errors = errors + 1;
            $display("[%0t] ERROR: %0s", $time, msg);
        end
    endtask

    // Index of the LED whose brightness target is 255 (lowest index if several)
    function integer bright_led(input integer dummy);
        begin
            bright_led = -1;
            if      (dut.inst1.my_fancy_leds.target_bright_0 == 8'd255) bright_led = 0;
            else if (dut.inst1.my_fancy_leds.target_bright_1 == 8'd255) bright_led = 1;
            else if (dut.inst1.my_fancy_leds.target_bright_2 == 8'd255) bright_led = 2;
            else if (dut.inst1.my_fancy_leds.target_bright_3 == 8'd255) bright_led = 3;
            else if (dut.inst1.my_fancy_leds.target_bright_4 == 8'd255) bright_led = 4;
            else if (dut.inst1.my_fancy_leds.target_bright_5 == 8'd255) bright_led = 5;
            else if (dut.inst1.my_fancy_leds.target_bright_6 == 8'd255) bright_led = 6;
            else if (dut.inst1.my_fancy_leds.target_bright_7 == 8'd255) bright_led = 7;
            else if (dut.inst1.my_fancy_leds.target_bright_8 == 8'd255) bright_led = 8;
            else if (dut.inst1.my_fancy_leds.target_bright_9 == 8'd255) bright_led = 9;
        end
    endfunction

    // Wait for the controller to finish configuring the sensor
    task wait_for_measure_mode;
        begin
            while (sensor.regs[6'h2D][3] !== 1'b1) @(posedge clk);
        end
    endtask

    task check_config_sequence(input integer first);
        begin
            checks = checks + 1;
            if (sensor.writes < first + 3) begin
                fail("fewer than 3 configuration writes");
            end else if (sensor.write_addr_log[first]     !== 6'h2E || sensor.write_data_log[first]     !== 8'h80 ||
                         sensor.write_addr_log[first + 1] !== 6'h2F || sensor.write_data_log[first + 1] !== 8'h80 ||
                         sensor.write_addr_log[first + 2] !== 6'h2D || sensor.write_data_log[first + 2] !== 8'h08) begin
                fail("configuration sequence is not INT_ENABLE=80, INT_MAP=80, POWER_CTL=08");
            end else begin
                $display("[%0t] ok: configuration sequence INT_ENABLE=0x80, INT_MAP=0x80, POWER_CTL=0x08", $time);
            end
        end
    endtask

    // Present a new X reading and check it propagates to the LED driver
    task check_reading(input integer x, input integer expected_led);
        integer reads_before;
        integer led;
        begin
            x_sample = x[15:0];
            // Two full sample/read cycles guarantee the new value has been read
            reads_before = sensor.x_reads;
            while (sensor.x_reads < reads_before + 2) @(posedge clk);
            while (dut.inst1.state !== 4'd13 && dut.inst1.state !== 4'd12) @(posedge clk);
            @(posedge clk);
            led = bright_led(0);
            checks = checks + 1;
            if (dut.inst1.full_x !== x[15:0]) begin
                errors = errors + 1;
                $display("[%0t] ERROR: X=%0d: controller read 0x%04h, expected 0x%04h", $time, x, dut.inst1.full_x, x[15:0]);
            end else if (led != expected_led) begin
                errors = errors + 1;
                $display("[%0t] ERROR: X=%0d: brightest LED is %0d, expected %0d", $time, x, led, expected_led);
            end else begin
                $display("[%0t] ok: X=%0d read as 0x%04h -> LED%0d", $time, x, dut.inst1.full_x, led);
            end
        end
    endtask

    // Record when the first SPI transaction starts after reset release
    time release_time   = 0;
    time first_cs_time  = 0;
    always @(negedge cs_n) if (first_cs_time == 0 && release_time != 0) first_cs_time = $time;

    integer writes_before;
    initial begin
        // ---- Reset ----
        repeat (10) @(posedge clk);
        #1;
        checks = checks + 1;
        if (hex0 !== 8'h00) fail("HEX0 reset indicator not lit while KEY[0] held");
        if (cs_n !== 1'b1 || sclk !== 1'b1) fail("SPI bus not idle during reset");
        if (hex1 !== 8'hFF || hex5 !== 8'hFF) fail("unused HEX displays not blanked");

        key[0] = 1'b1;
        release_time = $time;
        repeat (5) @(posedge clk);
        #1;
        if (hex0 !== 8'hFF) fail("HEX0 reset indicator not cleared after reset release");

        // ---- Boot delay + configuration ----
        wait_for_measure_mode;
        checks = checks + 1;
        if (first_cs_time - release_time < MIN_BOOT_NS) begin
            fail("first SPI access happened before the ~20 ms power-up delay");
        end else begin
            $display("[%0t] ok: first SPI access %0t after reset release", $time, first_cs_time - release_time);
        end
        check_config_sequence(0);

        // ---- Interrupt-driven reads ----
        //            X     LED
        check_reading(   0,  4);
        check_reading(  40,  4);
        check_reading( 100,  2);
        check_reading( 250,  0);
        check_reading( -40,  5);
        check_reading(-100,  7);
        check_reading(-250,  9);
        check_reading( 511,  0);
        check_reading(-511,  9);

        checks = checks + 1;
        if (sensor.overruns != 0)    fail("controller missed samples (sensor overrun)");
        if (sensor.stale_reads != 0) fail("controller read DATAX without a DATA_READY interrupt");
        $display("[%0t] ok: %0d samples produced, %0d read, %0d overruns, %0d stale reads",
                 $time, sensor.samples, sensor.x_reads, sensor.overruns, sensor.stale_reads);

        // ---- Press KEY[0] again: controller must re-initialise the sensor ----
        writes_before = sensor.writes;
        key[0] = 1'b0;
        repeat (50) @(posedge clk);
        sensor.regs[6'h2D] = 8'h00;  // emulate the sensor dropping back to standby
        key[0] = 1'b1;
        @(posedge clk);
        wait_for_measure_mode;
        check_config_sequence(writes_before);
        check_reading(70, 3);

        // ---- Summary ----
        errors = errors + sensor.errors;
        if (sensor.aborted != 0) fail("SPI transactions were aborted");

        $display("------------------------------------------------------------");
        $display("tb_use_accel: %0d checks, %0d SPI transactions", checks, sensor.transactions);
        if (errors == 0) begin
            $display("TEST PASSED: tb_use_accel");
            $finish;
        end else begin
            $display("TEST FAILED: tb_use_accel (%0d errors)", errors);
            $fatal(1);
        end
    end
endmodule
