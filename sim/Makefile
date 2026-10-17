# Simulation testbenches (Icarus Verilog)
#   make            run all tests
#   make tb_spi_master
#   make wave       dump tb_spi_master.vcd and regenerate docs/spi_read_waveform.svg
#   make clean

IVERILOG ?= iverilog
VVP      ?= vvp
PYTHON   ?= python3
IVFLAGS  := -g2012
BUILD    := build

SRC_tb_spi_master := tb_spi_master.v adxl345_model.v ../spi_master.v
SRC_tb_led_driver := tb_led_driver.v ../led_driver.v
SRC_tb_use_accel  := tb_use_accel.v adxl345_model.v ../USE_ACCEL.v ../adxl345_controller.v \
                     ../spi_master.v ../led_driver.v

TESTS := tb_spi_master tb_led_driver tb_use_accel

.PHONY: all clean wave $(TESTS)

all: $(TESTS)

$(TESTS): %: $(BUILD)/%.vvp
	cd $(BUILD) && $(VVP) -n $*.vvp

.SECONDEXPANSION:
$(BUILD)/%.vvp: $$(SRC_$$*) | $(BUILD)
	$(IVERILOG) $(IVFLAGS) -s $* -o $@ $(SRC_$*)

$(BUILD):
	mkdir -p $(BUILD)

wave: $(BUILD)/tb_spi_master.vvp
	cd $(BUILD) && $(VVP) -n tb_spi_master.vvp +vcd
	$(PYTHON) vcd_to_svg.py $(BUILD)/tb_spi_master.vcd ../docs/spi_read_waveform.svg

clean:
	rm -rf $(BUILD)
