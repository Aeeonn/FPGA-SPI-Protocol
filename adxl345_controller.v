module adxl345_controller (
    input  wire        clk_50,
    input  wire        rst_n,
	output reg [7:0]		   rst_indicator,
    
    // Physical SPI pins going out to the sensor
    output wire        sclk,
    output wire        cs_n_accel,
	input wire 	   	   int2,
    output wire        mosi,
    input  wire        miso,
    
    // User outputs (so you can see the data on LEDs or pass it to another module)
    output wire  [9:0]  x_data_out
);

    // --- Internal Wires to connect to the SPI Master ---
    reg         spi_start;
    reg  [15:0] spi_tx_data;
    wire [7:0]  spi_rx_data;
    wire        spi_done;


	// Instantiation of the spi master 
	spi_master inst1 (
		.clk_50(clk_50), 
		.rst_n(rst_n), 
		.start(spi_start), 
		.tx_data(spi_tx_data), 
		.rx_data(spi_rx_data), 
		.done(spi_done), 
		.sclk(sclk), 
		.cs_n_accel(cs_n_accel), 
		.mosi(mosi), 
		.miso(miso)
	);
	
    
    // State Definitions
	localparam STATE_INIT        		= 4'd0; // Bumped to 4 bits to hold up to 15 states
	localparam STATE_CONFIG_INT_ENABLE  = 4'd1;
	localparam STATE_WAIT_CONFIG_ENABLE = 4'd2;
	localparam STATE_CONFIG_INT_MAP     = 4'd3;
	localparam STATE_WAIT_CONFIG_MAP    = 4'd4;
	localparam STATE_POWER_ON    		= 4'd5;
	localparam STATE_IDLE_SLEEP         = 4'd6;
	localparam STATE_WAIT_POWER  		= 4'd7;
	localparam STATE_READ_X_LOW  		= 4'd8;
	localparam STATE_WAIT_X_LOW  		= 4'd9;
	localparam STATE_READ_X_HIGH 		= 4'd10;
	localparam STATE_WAIT_X_HIGH 		= 4'd11;
	localparam STATE_WFI				= 4'd12;
	localparam STATE_WAIT_INT_CLEAR 	= 4'd13;

	reg [3:0] state;

    reg [23:0] delay_count; // General purpose counter for delays
	reg [7:0] raw_x_low;
	reg [7:0] raw_x_high;
	
	// Used to detect an interrupt
	// If 0b001, INT detected. 
	reg [2:0] int2_sync; 

    always @(posedge clk_50 or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_INIT;
			rst_indicator <= 8'b0; // HEX segment reset indicator
            spi_start <= 1'b0;
            spi_tx_data <= 16'd0;
            raw_x_low <= 8'd0;
			raw_x_high <= 8'd0;
            delay_count <= 16'd0;
			int2_sync <= 3'h0;
        end else begin
			rst_indicator <= 8'hFF;
			int2_sync <= {int2_sync[1:0], int2};
		
            case (state)
                STATE_INIT: begin
                    // Wait a bit for the ADXL345 to fully boot up
                    if (delay_count == 24'h0FFFFF) begin
                        state <= STATE_CONFIG_INT_ENABLE;
                        delay_count <= 16'd0;
                    end else begin
                        delay_count <= delay_count + 1'b1;
                    end
                end
				
				// Send IE signal to ADXL
				STATE_CONFIG_INT_ENABLE: begin
					spi_tx_data <= 16'h2E80; // Register 0x2E with data 0x80 (DATA_READY)
					spi_start <= 1'b1;
					state <= STATE_WAIT_CONFIG_ENABLE; 
				end
				
				// Wait for ADXL to complete receive then move on (because of the slow SCLK, it has to finish sending before loading more data in tx reg)
				// Without it, FPGA would blow past this as for the time to send a 16 bit word with sclk, the 50MHz clk goes through 1700 cycles!
				STATE_WAIT_CONFIG_ENABLE: begin
					if(spi_done) begin
						spi_start <= 1'b0;
						state <= STATE_CONFIG_INT_MAP;
					end
				end
				
				// Send INT MAP to ADXL
				STATE_CONFIG_INT_MAP: begin
					spi_tx_data <= 16'h2F80; // Same as above with register 0x2F
					spi_start <= 1'b1;
					state <= STATE_WAIT_CONFIG_MAP; 
				end
				
				// Same as above
				STATE_WAIT_CONFIG_MAP: begin
					if(spi_done) begin
						spi_start <= 1'b0;
						state <= STATE_POWER_ON;
					end
				end
                
				// After configuring the ADXL, we can power it up!
                STATE_POWER_ON: begin
					spi_tx_data <= 16'h2D08; // Register 0x2D with data 0x08 (MEASURE)
					spi_start <=  1'b1;
					state <= STATE_WAIT_POWER;
                end
                
				// Same as above
                STATE_WAIT_POWER: begin
					if(spi_done == 1'b1) begin
						spi_start <= 1'b0; 
						state <= STATE_WFI;
					end
                end
				
				// Here we wait for the interrupts. They're by default at 100Hz rate, or once every 0.01s
				STATE_WFI: begin
					if(int2_sync[2] == 1'b1) begin
						state <= STATE_READ_X_LOW;
					end
				end
				
				// Can begin READING from ADXL now (we're done configuration, and just waiting)                
                STATE_READ_X_LOW: begin
					// We want to READ register 0x32. READING implies MSB = 1, therefore 0xB2 to account for that.
					// The lower 8 bits are garbage and could be anything as we're simply reading from that register. 
					// Whatever is being READ from 0x32, will be put in MISO then back into shift_rx. 
					
                    spi_tx_data <= 16'hB200;
                    spi_start <= 1'b1;
                    state <= STATE_WAIT_X_LOW;
                end
				
                // Same waiting as above, but save data in a different register to avoid overwrite
                STATE_WAIT_X_LOW: begin
                    if (spi_done == 1'b1) begin
                        spi_start <= 1'b0;
                        raw_x_low <= spi_rx_data; // Save read data from ADXL (low bits, as the accel reads 16 bits)
                        state <= STATE_READ_X_HIGH;
                    end
                end
				
				// Same as above
                STATE_READ_X_HIGH: begin
                    spi_tx_data <= 16'hB300; 
                    spi_start <= 1'b1;
                    state <= STATE_WAIT_X_HIGH;
                end
				
				// Same as above
                STATE_WAIT_X_HIGH: begin
                    if (spi_done == 1'b1) begin
                        spi_start <= 1'b0;
                        raw_x_high <= spi_rx_data; 
                        state <= STATE_WAIT_INT_CLEAR;
                    end
                end
				
				// Because 50MHz is so much faster than sclk, we have to wait for the ADXL to reset INT pin
				STATE_WAIT_INT_CLEAR: begin
					// Pause here until the ADXL345 finishes pulling the physical wire LOW
					if (int2_sync[2] == 1'b0) begin
						state <= STATE_WFI;
					end
				end
            endcase
        end
    end
	
	// --- Data Processing Layer ---
    wire [15:0] full_x = {raw_x_high, raw_x_low};

    led_driver my_fancy_leds (
        .iRSTN(rst_n),
        .iCLK(clk_50),
        .iDIG(full_x[9:0]), // Pass it the bottom 10 bits of our read data
        .iG_INT2(1'b0),     // Unused by the LED driver (INT2 is handled by the state machine above)
        .oLED(x_data_out)   // Send the output to your top level!
    );
endmodule