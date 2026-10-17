`timescale 1ns/1ps
//=============================================================================
// adxl345_model.v
// Simulation-only behavioral model of the ADXL345 4-wire SPI interface.
//
//  - SPI mode 3: samples SDI on SCLK rising edges, drives SDO on falling edges
//  - Single-byte register reads/writes (R/W bit 7, MB bit 6, 6-bit address)
//  - DEVID (0x00) reads back 0xE5, like the real part
//  - When POWER_CTL.Measure is set, a new sample is produced every
//    ODR_PERIOD_NS and DATA_READY is raised; it is routed to INT1/INT2 by
//    INT_ENABLE / INT_MAP. Reading a DATA register clears DATA_READY.
//  - Protocol checker: flags CPOL violations, SCLK > 5 MHz, malformed
//    transactions and reads of stale data.
//=============================================================================
module adxl345_model #(
    parameter integer ODR_PERIOD_NS = 10_000_000  // 100 Hz, the ADXL345 default
)(
    input  wire        sclk,
    input  wire        cs_n,
    input  wire        sdi,
    output wire        sdo,
    output wire        int1,
    output wire        int2,
    input  wire [15:0] x_sample  // value latched into DATAX1:DATAX0 on each sample
);
    localparam [5:0] REG_DEVID      = 6'h00;
    localparam [5:0] REG_POWER_CTL  = 6'h2D;
    localparam [5:0] REG_INT_ENABLE = 6'h2E;
    localparam [5:0] REG_INT_MAP    = 6'h2F;
    localparam [5:0] REG_INT_SOURCE = 6'h30;
    localparam [5:0] REG_DATAX0     = 6'h32;
    localparam [5:0] REG_DATAX1     = 6'h33;
    localparam [5:0] REG_DATAZ1     = 6'h37;

    localparam integer SCLK_MIN_PERIOD_NS = 200;  // 5 MHz max SCLK

    reg [7:0] regs [0:63];

    // Scoreboard counters, read hierarchically by the testbenches
    integer errors        = 0;
    integer transactions  = 0;
    integer aborted       = 0;  // CS released before 16 SCLK cycles
    integer writes        = 0;
    integer samples       = 0;
    integer overruns      = 0;  // new sample while previous one was unread
    integer stale_reads   = 0;  // DATAX0 read while no new data was ready
    integer x_reads       = 0;
    reg [5:0] write_addr_log [0:255];
    reg [7:0] write_data_log [0:255];

    reg        in_xfer;
    reg [4:0]  bit_cnt;
    reg [15:0] shift_in;
    reg [7:0]  shift_out;
    reg        is_read;
    reg [5:0]  addr;
    reg        sdo_r;
    reg        data_ready;
    time       last_rise;

    integer i;
    initial begin
        for (i = 0; i < 64; i = i + 1) regs[i] = 8'h00;
        regs[REG_DEVID]      = 8'hE5;
        regs[6'h2C]          = 8'h0A;  // BW_RATE reset value (100 Hz)
        regs[REG_INT_SOURCE] = 8'h02;
        in_xfer    = 1'b0;
        bit_cnt    = 5'd0;
        shift_in   = 16'd0;
        shift_out  = 8'd0;
        is_read    = 1'b0;
        addr       = 6'd0;
        sdo_r      = 1'b0;
        data_ready = 1'b0;
        last_rise  = 0;
    end

    // SDO is only driven while the device is selected
    assign sdo = cs_n ? 1'bz : sdo_r;

    wire dr_irq = data_ready & regs[REG_INT_ENABLE][7];
    assign int2 = dr_irq &  regs[REG_INT_MAP][7];
    assign int1 = dr_irq & ~regs[REG_INT_MAP][7];

    function is_read_only(input [5:0] a);
        is_read_only = (a == REG_DEVID) || (a >= REG_INT_SOURCE && a <= 6'h39);
    endfunction

    // ---------------- Chip select ----------------
    always @(negedge cs_n) begin
        if (sclk !== 1'b1) begin
            errors = errors + 1;
            $display("[%0t] ADXL345 ERROR: SCLK not high when CS asserted (mode 3 requires CPOL=1)", $time);
        end
        in_xfer  = 1'b1;
        bit_cnt  = 5'd0;
        shift_in = 16'd0;
        is_read  = 1'b0;
        sdo_r    = 1'b0;
    end

    always @(posedge cs_n) begin
        if (in_xfer) begin
            in_xfer = 1'b0;
            if (bit_cnt == 5'd16) begin
                transactions = transactions + 1;
            end else begin
                aborted = aborted + 1;
                $display("[%0t] ADXL345 NOTE: transaction aborted after %0d SCLK cycles", $time, bit_cnt);
            end
        end
    end

    // ---------------- Shift in on rising edge ----------------
    always @(posedge sclk) begin
        if (cs_n === 1'b0) begin
            if (last_rise != 0 && ($time - last_rise) < SCLK_MIN_PERIOD_NS) begin
                errors = errors + 1;
                $display("[%0t] ADXL345 ERROR: SCLK period %0t ns violates 5 MHz maximum", $time, $time - last_rise);
            end
            last_rise = $time;

            shift_in = {shift_in[14:0], sdi};
            bit_cnt  = bit_cnt + 1'b1;

            if (bit_cnt == 5'd8) begin
                is_read = shift_in[7];
                addr    = shift_in[5:0];
                if (shift_in[6]) begin
                    errors = errors + 1;
                    $display("[%0t] ADXL345 ERROR: multi-byte (MB) transfers are not used by this design", $time);
                end
                if (is_read) begin
                    shift_out = regs[addr];
                    if (addr == REG_DATAX0) begin
                        x_reads = x_reads + 1;
                        if (!data_ready) stale_reads = stale_reads + 1;
                    end
                    if (addr >= REG_DATAX0 && addr <= REG_DATAZ1) begin
                        data_ready = 1'b0;
                        regs[REG_INT_SOURCE][7] = 1'b0;
                    end
                end
            end else if (bit_cnt == 5'd16 && !is_read) begin
                if (writes < 256) begin
                    write_addr_log[writes] = addr;
                    write_data_log[writes] = shift_in[7:0];
                end
                writes = writes + 1;
                if (!is_read_only(addr)) regs[addr] = shift_in[7:0];
                $display("[%0t] ADXL345: write reg 0x%02h = 0x%02h", $time, addr, shift_in[7:0]);
            end else if (bit_cnt > 5'd16) begin
                errors = errors + 1;
                $display("[%0t] ADXL345 ERROR: more than 16 SCLK cycles in one transaction", $time);
            end
        end
    end

    // ---------------- Shift out on falling edge ----------------
    always @(negedge sclk) begin
        if (cs_n === 1'b0 && is_read && bit_cnt >= 5'd8 && bit_cnt < 5'd16) begin
            sdo_r     = shift_out[7];
            shift_out = {shift_out[6:0], 1'b0};
        end
    end

    // ---------------- Sample generator ----------------
    always begin
        #(ODR_PERIOD_NS);
        if (regs[REG_POWER_CTL][3]) begin
            if (data_ready) overruns = overruns + 1;
            regs[REG_DATAX0]        = x_sample[7:0];
            regs[REG_DATAX1]        = x_sample[15:8];
            regs[REG_INT_SOURCE][7] = 1'b1;
            data_ready              = 1'b1;
            samples                 = samples + 1;
        end
    end
endmodule
