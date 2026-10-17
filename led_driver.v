module led_driver (
    input  wire        iRSTN,
    input  wire        iCLK,
    input  wire [9:0]  iDIG,
    input  wire        iG_INT2,
    output wire [9:0]  oLED
);

    wire        sign_bit;
    wire [8:0]  abs_val;
    wire [3:0]  magnitude;

    // --- 1. Data Processing ---
    assign sign_bit = iDIG[9];
    assign abs_val = sign_bit ? (~iDIG[8:0] + 1'b1) : iDIG[8:0];
    assign magnitude = abs_val[8:5];

    // --- 2. Brightness Registers ---
    // The "Target" is what the tilt math WANTS the LED to be.
    reg [7:0] target_bright_0, target_bright_1, target_bright_2, target_bright_3, target_bright_4;
    reg [7:0] target_bright_5, target_bright_6, target_bright_7, target_bright_8, target_bright_9;

    // The "Actual" is what the PWM engine is currently displaying (starts at 0).
    reg [7:0] actual_bright_0 = 0, actual_bright_1 = 0, actual_bright_2 = 0, actual_bright_3 = 0, actual_bright_4 = 0;
    reg [7:0] actual_bright_5 = 0, actual_bright_6 = 0, actual_bright_7 = 0, actual_bright_8 = 0, actual_bright_9 = 0;

    // --- 3. Target Brightness Logic (Combinatorial) ---
    always @(*) begin
        // CRITICAL FIX: Explicitly default all targets to 0 every single cycle.
        // This completely eliminates the "Inferred Latch" ghost trail.
        target_bright_0 = 8'd0; target_bright_1 = 8'd0; target_bright_2 = 8'd0; target_bright_3 = 8'd0; target_bright_4 = 8'd0;
        target_bright_5 = 8'd0; target_bright_6 = 8'd0; target_bright_7 = 8'd0; target_bright_8 = 8'd0; target_bright_9 = 8'd0;

        if (magnitude == 4'd0) begin
            // Flat board
            target_bright_4 = 8'd255;
            target_bright_5 = 8'd255;
        end else if (sign_bit == 1'b1) begin
            // Negative Tilt (Shift Right toward LED 9)
            case (magnitude)
                4'd1: begin target_bright_4 = 8'd20; target_bright_5 = 8'd255; target_bright_6 = 8'd20; end
                4'd2: begin target_bright_5 = 8'd20; target_bright_6 = 8'd255; target_bright_7 = 8'd20; end
                4'd3: begin target_bright_6 = 8'd20; target_bright_7 = 8'd255; target_bright_8 = 8'd20; end
                4'd4: begin target_bright_7 = 8'd20; target_bright_8 = 8'd255; target_bright_9 = 8'd20; end
                default: begin target_bright_8 = 8'd20; target_bright_9 = 8'd255; end // Edge
            endcase
        end else begin
            // Positive Tilt (Shift Left toward LED 0)
            case (magnitude)
                4'd1: begin target_bright_3 = 8'd20; target_bright_4 = 8'd255; target_bright_5 = 8'd20; end
                4'd2: begin target_bright_2 = 8'd20; target_bright_3 = 8'd255; target_bright_4 = 8'd20; end
                4'd3: begin target_bright_1 = 8'd20; target_bright_2 = 8'd255; target_bright_3 = 8'd20; end
                4'd4: begin target_bright_0 = 8'd20; target_bright_1 = 8'd255; target_bright_2 = 8'd20; end
                default: begin target_bright_0 = 8'd255; target_bright_1 = 8'd20; end // Edge
            endcase
        end
    end

    // --- 4. The Fade Timer ---
    localparam FADE_SPEED = 16'd50000; // 1 millisecond at 50MHz
    reg [15:0] fade_timer = 0;
    wire fade_tick = (fade_timer == FADE_SPEED);

    always @(posedge iCLK) begin
        if (fade_tick) begin
            fade_timer <= 0;
        end else begin
            fade_timer <= fade_timer + 1'b1;
        end
    end

    // --- 5. The Smooth Fader ---
    always @(posedge iCLK) begin
        if (fade_tick) begin
            // LED 0
            if (actual_bright_0 < target_bright_0) actual_bright_0 <= actual_bright_0 + 1'b1;
            else if (actual_bright_0 > target_bright_0) actual_bright_0 <= actual_bright_0 - 1'b1;
            // LED 1
            if (actual_bright_1 < target_bright_1) actual_bright_1 <= actual_bright_1 + 1'b1;
            else if (actual_bright_1 > target_bright_1) actual_bright_1 <= actual_bright_1 - 1'b1;
            // LED 2
            if (actual_bright_2 < target_bright_2) actual_bright_2 <= actual_bright_2 + 1'b1;
            else if (actual_bright_2 > target_bright_2) actual_bright_2 <= actual_bright_2 - 1'b1;
            // LED 3
            if (actual_bright_3 < target_bright_3) actual_bright_3 <= actual_bright_3 + 1'b1;
            else if (actual_bright_3 > target_bright_3) actual_bright_3 <= actual_bright_3 - 1'b1;
            // LED 4
            if (actual_bright_4 < target_bright_4) actual_bright_4 <= actual_bright_4 + 1'b1;
            else if (actual_bright_4 > target_bright_4) actual_bright_4 <= actual_bright_4 - 1'b1;
            // LED 5
            if (actual_bright_5 < target_bright_5) actual_bright_5 <= actual_bright_5 + 1'b1;
            else if (actual_bright_5 > target_bright_5) actual_bright_5 <= actual_bright_5 - 1'b1;
            // LED 6
            if (actual_bright_6 < target_bright_6) actual_bright_6 <= actual_bright_6 + 1'b1;
            else if (actual_bright_6 > target_bright_6) actual_bright_6 <= actual_bright_6 - 1'b1;
            // LED 7
            if (actual_bright_7 < target_bright_7) actual_bright_7 <= actual_bright_7 + 1'b1;
            else if (actual_bright_7 > target_bright_7) actual_bright_7 <= actual_bright_7 - 1'b1;
            // LED 8
            if (actual_bright_8 < target_bright_8) actual_bright_8 <= actual_bright_8 + 1'b1;
            else if (actual_bright_8 > target_bright_8) actual_bright_8 <= actual_bright_8 - 1'b1;
            // LED 9
            if (actual_bright_9 < target_bright_9) actual_bright_9 <= actual_bright_9 + 1'b1;
            else if (actual_bright_9 > target_bright_9) actual_bright_9 <= actual_bright_9 - 1'b1;
        end
    end

    // --- 6. The Global PWM Engine ---
    reg [7:0] pwm_counter = 0;
    always @(posedge iCLK) begin
        pwm_counter <= pwm_counter + 1'b1;
    end

    // Link the physical pins to the actual brightness compared against the global counter
    assign oLED[0] = (actual_bright_0 > pwm_counter) ? 1'b1 : 1'b0;
    assign oLED[1] = (actual_bright_1 > pwm_counter) ? 1'b1 : 1'b0;
    assign oLED[2] = (actual_bright_2 > pwm_counter) ? 1'b1 : 1'b0;
    assign oLED[3] = (actual_bright_3 > pwm_counter) ? 1'b1 : 1'b0;
    assign oLED[4] = (actual_bright_4 > pwm_counter) ? 1'b1 : 1'b0;
    assign oLED[5] = (actual_bright_5 > pwm_counter) ? 1'b1 : 1'b0;
    assign oLED[6] = (actual_bright_6 > pwm_counter) ? 1'b1 : 1'b0;
    assign oLED[7] = (actual_bright_7 > pwm_counter) ? 1'b1 : 1'b0;
    assign oLED[8] = (actual_bright_8 > pwm_counter) ? 1'b1 : 1'b0;
    assign oLED[9] = (actual_bright_9 > pwm_counter) ? 1'b1 : 1'b0;

endmodule