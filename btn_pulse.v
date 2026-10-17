module btn_pulse (iCLK, iBTN, oBTN_PULSE);
	input wire iCLK;
	input wire iBTN;
	output reg oBTN_PULSE;
	
	reg [1:0] KEY_SYNC;
	
	always @(posedge iCLK) begin
		KEY_SYNC <= { KEY_SYNC[0], ~iBTN };
		oBTN_PULSE <= KEY_SYNC[0] & ~KEY_SYNC[1];
	end
endmodule