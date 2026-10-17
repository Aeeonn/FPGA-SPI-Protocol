module spi_master (
    // --- System Inputs ---
    input wire clk_50,   // 50 MHz system clock
    input wire rst_n,    // Active-low reset

    // Application Interface
    input wire start,    // Pulse high to start
    input wire [15:0] tx_data,  // 16 bits to send (Command + Data)
    output reg [7:0] rx_data,  // 8 bits received payload
    output reg done,     // Pulses high when finished

    // --- SPI Physical Interface ---
    output reg sclk,     // Serial Clock
    output reg cs_n_accel,     // Chip Select (Active Low)
    output wire mosi,     // Master Out Slave In
    input wire miso      // Master In Slave Out
);

	// --- Local parameters ---
	localparam IDLE = 2'b00;
	localparam TRANSFER = 2'b01;
	localparam DONE = 2'b10;
	
    // --- Internal Signals ---
    reg enable_tick;             // Pulses high for 1 cycle at 1MHz
    reg [5:0] clk_counter;       // 6-bit counter (can hold 0-63)    // State definitions

	reg [1:0] state;
	reg [15:0] shift_tx;  // To hold the data we are sending out
	reg [7:0] shift_rx; // Hold data receiving
	reg [4:0]  bit_count; // To count 16 bits
	
	assign mosi = shift_tx[15];
	
	
	//Tick at 1MHz for sclk
	always @(posedge clk_50 or negedge rst_n) begin
		if(!rst_n) begin
			clk_counter <= 1'b0;
			enable_tick <= 1'b0;
		end else begin
			if(clk_counter == 49) begin
				enable_tick <= 1'b1;
				clk_counter <= 1'b0;
			end else begin
				enable_tick <= 1'b0;
				clk_counter <= clk_counter + 1;
			end
		end
	end
	
	
    // Shift Registers & State Machine
	always @(posedge clk_50 or negedge rst_n) begin
		if (!rst_n) begin
            state <= IDLE;
            sclk <= 1'b1;  // SPI Mode 3 idles HIGH
            cs_n_accel <= 1'b1; // CS idles HIGH (no chip is selected)
            done <= 1'b0;
            rx_data <= 8'd0;
            shift_tx <= 16'd0;
            shift_rx <= 8'd0;
            bit_count <= 5'd0;
			
		end else begin
            // Clear the 'done' flag immediately by default.
            // This guarantees 'done' is only ever HIGH for exactly 1 clock cycle (20ns).
            done <= 1'b0; 

            // Only run the SPI state machine when the 1MHz tick fires
            if (enable_tick) begin
                case (state)
                    IDLE: begin
                        cs_n_accel <= 1'b1; 
                        sclk <= 1'b1;
                        if (start == 1'b1) begin
                            shift_tx <= tx_data;
                            cs_n_accel <= 1'b0;      // Drop CS to wake up ADXL345
                            bit_count <= 5'd16;      // We need to send 16 bits (8 bits cmd + 8 bits data)
                            state <= TRANSFER;
                        end
                    end
                    
                    TRANSFER: begin
                        sclk <= ~sclk; // Toggle the SPI clock every tick
                        
                        if (sclk == 1'b1) begin
                            // FALLING EDGE
                            if (bit_count < 5'd16) begin 
                                shift_tx <= {shift_tx[14:0], 1'b0};
                            end
                        end else begin
                            // RISING EDGE
                            shift_rx <= {shift_rx[6:0], miso};
                            bit_count <= bit_count - 1'b1;
                            
                            if (bit_count == 5'd1) begin
                                state <= DONE;
                            end
                        end
                    end
                    
                    DONE: begin
                        cs_n_accel <= 1'b1;
                        rx_data <= shift_rx;
                        done <= 1'b1; // Will be cleared to 0 on the next 50MHz clock cycle!
                        state <= IDLE;
                    end
                    
                    default: state <= IDLE;
                endcase
            end
		end
	end
endmodule