`timescale 1ns/1ps
//=============================================================================
// tb_led_driver.v
// Self-checking unit test for led_driver.v.
//
// Checks:
//  - Tilt-to-LED mapping for every magnitude band, both directions
//  - The fader moves each LED's brightness by one step per 1 ms tick
//  - PWM duty cycle on each pin equals its current brightness / 256
//  - A full fade settles at the target brightness
//=============================================================================
module tb_led_driver;

    localparam integer CLK_PERIOD_NS = 20;  // 50 MHz

    reg        clk = 1'b0;
    reg  [9:0] dig;  // starts as X so the first applied value triggers always @(*)
    wire [9:0] led;

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    led_driver dut (
        .iRSTN   (1'b1),
        .iCLK    (clk),
        .iDIG    (dig),
        .iG_INT2 (1'b0),
        .oLED    (led)
    );

    integer errors = 0;
    integer checks = 0;

    initial $timeformat(-9, 0, " ns", 0);

    initial begin
        #(400_000_000);
        $display("FAIL: tb_led_driver timed out");
        $fatal(1);
    end

    function [7:0] target(input integer i);
        case (i)
            0: target = dut.target_bright_0;  1: target = dut.target_bright_1;
            2: target = dut.target_bright_2;  3: target = dut.target_bright_3;
            4: target = dut.target_bright_4;  5: target = dut.target_bright_5;
            6: target = dut.target_bright_6;  7: target = dut.target_bright_7;
            8: target = dut.target_bright_8;  default: target = dut.target_bright_9;
        endcase
    endfunction

    function [7:0] actual(input integer i);
        case (i)
            0: actual = dut.actual_bright_0;  1: actual = dut.actual_bright_1;
            2: actual = dut.actual_bright_2;  3: actual = dut.actual_bright_3;
            4: actual = dut.actual_bright_4;  5: actual = dut.actual_bright_5;
            6: actual = dut.actual_bright_6;  7: actual = dut.actual_bright_7;
            8: actual = dut.actual_bright_8;  default: actual = dut.actual_bright_9;
        endcase
    endfunction

    // Apply a signed X reading and compare all ten brightness targets
    task check_mapping(input integer x, input [9:0] bright_mask, input [9:0] dim_mask);
        integer i;
        reg [7:0] expected;
        reg       ok;
        begin
            dig = x[9:0];
            #1;
            ok = 1'b1;
            for (i = 0; i < 10; i = i + 1) begin
                expected = bright_mask[i] ? 8'd255 : (dim_mask[i] ? 8'd20 : 8'd0);
                if (target(i) !== expected) ok = 1'b0;
            end
            checks = checks + 1;
            if (!ok) begin
                errors = errors + 1;
                $display("ERROR: x=%0d: wrong LED targets (bright mask %b, dim mask %b expected)", x, bright_mask, dim_mask);
                for (i = 9; i >= 0; i = i - 1) $display("    LED%0d target=%0d", i, target(i));
            end
        end
    endtask

    // Count PWM high cycles over one full 256-cycle PWM period
    task check_pwm(input integer i);
        integer n, high;
        reg [7:0] bright;
        begin
            @(posedge clk);
            while (dut.pwm_counter !== 8'd0) @(posedge clk);
            bright = actual(i);
            high = 0;
            for (n = 0; n < 256; n = n + 1) begin
                #1;
                if (led[i]) high = high + 1;
                @(posedge clk);
            end
            checks = checks + 1;
            if (high != bright) begin
                errors = errors + 1;
                $display("[%0t] ERROR: LED%0d PWM high for %0d/256 cycles, brightness is %0d", $time, i, high, bright);
            end else begin
                $display("[%0t] ok: LED%0d PWM duty %0d/256 matches brightness", $time, i, high);
            end
        end
    endtask

    task wait_fade_ticks(input integer n);
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) begin
                @(posedge clk);
                while (dut.fade_tick !== 1'b1) @(posedge clk);
            end
            @(posedge clk);
        end
    endtask

    integer i;
    initial begin
        // ---- 1) Mapping table (magnitude = |x| >> 5) ----
        //                 x     bright LEDs      dim LEDs
        check_mapping(    0, 10'b0000110000, 10'b0000000000);
        check_mapping(   31, 10'b0000110000, 10'b0000000000);
        check_mapping(  -31, 10'b0000110000, 10'b0000000000);
        check_mapping(   32, 10'b0000010000, 10'b0000101000);
        check_mapping(   64, 10'b0000001000, 10'b0000010100);
        check_mapping(   96, 10'b0000000100, 10'b0000001010);
        check_mapping(  128, 10'b0000000010, 10'b0000000101);
        check_mapping(  160, 10'b0000000001, 10'b0000000010);
        check_mapping(  511, 10'b0000000001, 10'b0000000010);
        check_mapping(  -32, 10'b0000100000, 10'b0001010000);
        check_mapping(  -64, 10'b0001000000, 10'b0010100000);
        check_mapping(  -96, 10'b0010000000, 10'b0101000000);
        check_mapping( -128, 10'b0100000000, 10'b1010000000);
        check_mapping( -160, 10'b1000000000, 10'b0100000000);
        check_mapping( -511, 10'b1000000000, 10'b0100000000);
        $display("ok: tilt-to-LED mapping (%0d cases)", checks);

        // ---- 2) Fade-in: one brightness step per 1 ms tick ----
        dig = 10'd0;  // flat: LEDs 4 and 5 fade towards 255
        for (i = 0; i < 10; i = i + 1) begin
            if (actual(i) !== 8'd0) begin
                errors = errors + 1;
                $display("ERROR: LED%0d brightness not 0 at power-up", i);
            end
        end
        wait_fade_ticks(3);
        checks = checks + 1;
        if (actual(4) !== 8'd3 || actual(5) !== 8'd3 || actual(0) !== 8'd0) begin
            errors = errors + 1;
            $display("[%0t] ERROR: after 3 ticks brightness LED4=%0d LED5=%0d LED0=%0d (expected 3,3,0)", $time, actual(4), actual(5), actual(0));
        end else begin
            $display("[%0t] ok: fader stepped LED4/LED5 to 3 after 3 ms", $time);
        end

        check_pwm(4);
        check_pwm(0);

        // ---- 3) Full fade settles at target ----
        wait_fade_ticks(255);
        checks = checks + 1;
        if (actual(4) !== 8'd255 || actual(5) !== 8'd255) begin
            errors = errors + 1;
            $display("[%0t] ERROR: fade did not settle at 255 (LED4=%0d LED5=%0d)", $time, actual(4), actual(5));
        end else begin
            $display("[%0t] ok: LED4/LED5 settled at full brightness", $time);
        end
        check_pwm(5);

        // ---- 4) Tilt change: old LEDs fade out, new LED fades in ----
        dig = 10'd200;  // strong positive tilt -> LED0 bright, LED1 dim
        wait_fade_ticks(10);
        checks = checks + 1;
        if (actual(4) !== 8'd245 || actual(0) !== 8'd10 || actual(1) !== 8'd10) begin
            errors = errors + 1;
            $display("[%0t] ERROR: after tilt change LED4=%0d LED0=%0d LED1=%0d (expected 245,10,10)", $time, actual(4), actual(0), actual(1));
        end else begin
            $display("[%0t] ok: LED4 fading out, LED0/LED1 fading in", $time);
        end
        wait_fade_ticks(20);
        checks = checks + 1;
        if (actual(1) !== 8'd20) begin
            errors = errors + 1;
            $display("[%0t] ERROR: dim neighbour LED1=%0d, expected to stop at 20", $time, actual(1));
        end else begin
            $display("[%0t] ok: dim neighbour LED1 stopped at its target of 20", $time);
        end
        check_pwm(1);

        $display("------------------------------------------------------------");
        $display("tb_led_driver: %0d checks", checks);
        if (errors == 0) begin
            $display("TEST PASSED: tb_led_driver");
            $finish;
        end else begin
            $display("TEST FAILED: tb_led_driver (%0d errors)", errors);
            $fatal(1);
        end
    end
endmodule
