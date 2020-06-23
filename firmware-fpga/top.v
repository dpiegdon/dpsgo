`default_nettype none

module top(
	input  wire SCK,
	input  wire SS,
	input  wire SDI,
	output wire SDO,
	output wire FPGA_INT,

	input wire MAJOR_CLOCK,
	input  wire MINOR_CLOCK,
	);


	localparam CPOL = 1'b1;

	localparam DOWNCOUNT_WIDTH = 16;
	localparam UPCOUNT_WIDTH = 40;


	/*
	 * upcount and downcount combined are the SPI word. they are
	 * transparent shift registers. no counting will be done if
	 * CS is active, so that the controller can replace the
	 * contents unobstructed. downcount is high-side of SPI-word,
	 * upcount is low-side of SPI word. transmission is done
	 * MSB first. after CS deassert wait until next rising edge on
	 * MINOR_CLOCK, *then* start counting in upcount synced to
	 * MAJOR_CLOCK. each time another MINOR_CLOCK is caught,
	 * downcount is decreased, until downcount is zero. then all
	 * counting stops and an interrupt is asserted to the
	 * controller.
	 * to properly capture the differences in the clocks,
	 * MINOR_CLOCK must be the slower clock of both.
	 *
	 *      /-------------|-----------\
	 * <=== |  downcount  |  upcount  |  <===
	 *      \-------------|-----------/
	 */


	// SPI interface and counter
	reg [UPCOUNT_WIDTH-1:0] upcount = 0;
	reg [DOWNCOUNT_WIDTH-1:0] downcount = 0;

	reg minor_edge_seen = 0;
	wire downcount_done = |downcount;
	wire do_upcount = downcount_done && minor_edge_seen && !&upcount;

	wire minor_rising;
	synchronizer #(.EXTRA_DEPTH(3)) minor_syncer(.clk(MAJOR_CLOCK), .in(MINOR_CLOCK), .out(), .rising_edge(minor_rising), .falling_edge());

	wire cs_start;
	wire cs_active;
	synchronizer #(.EXTRA_DEPTH(3)) ss_syncer(.clk(MAJOR_CLOCK), .in(!SS), .out(cs_active), .rising_edge(cs_start), .falling_edge());

	wire sck_sample;
	wire sck_latch;
	synchronizer #(.EXTRA_DEPTH(3)) sck_syncer(.clk(MAJOR_CLOCK), .in(SCK ^ CPOL), .out(), .rising_edge(sck_sample), .falling_edge(sck_latch));

	wire mosi_sync;
	synchronizer #(.EXTRA_DEPTH(3)) mosi_syncer(.clk(MAJOR_CLOCK), .in(SDI), .out(mosi_sync), .rising_edge(), .falling_edge());

	wire miso_bit = downcount[DOWNCOUNT_WIDTH-1];
	reg miso_buffer = 0;
	tristate_output miso_driver(SDO, !SS, miso_buffer);

	assign FPGA_INT = (!downcount_done) && !cs_active;

	always @(posedge MAJOR_CLOCK) begin
		if(cs_active) begin
			if(cs_start) begin
				minor_edge_seen <= 0;
			end else begin
				// SPI shift logic
				if(sck_sample) begin
					{ downcount, upcount } <= { downcount[DOWNCOUNT_WIDTH-2:0], upcount, mosi_sync };
				end else if(sck_latch) begin
					miso_buffer <= miso_bit;
				end
			end
		end else begin
			// counting logic
			if(do_upcount) begin
				// upcount is very wide, so let's use
				// look-ahead to increase adding speed.
				upcount[11:0] <= upcount[11:0] + 1;
				if(&upcount[11:0]) begin
					upcount[23:12] <= upcount[23:12] + 1;
					if(&upcount[23:12]) begin
						upcount[35:24] <= upcount[35:24] + 1;
						if(&upcount[35:24]) begin
							upcount[UPCOUNT_WIDTH-1:36] <= upcount[UPCOUNT_WIDTH-1:36] + 1;
						end
					end
				end
			end
			if(minor_rising && !downcount_done) begin
				if(minor_edge_seen) begin
					// same goes here: use look-ahead to
					// increase subtraction speed.
					downcount[3:0] <= downcount[3:0] - 1;
					if(!|downcount[3:0]) begin
						downcount[11:4] <= downcount[11:4] - 1;
						if(!|downcount[11:4]) begin
							downcount[11:4] <= downcount[11:4] - 1;
							if(!|downcount[11:4]) begin
								downcount[DOWNCOUNT_WIDTH-1:12] <= downcount[DOWNCOUNT_WIDTH-1:12] - 1;
							end
						end
					end
				end
				minor_edge_seen <= 1;
			end
			miso_buffer <= miso_bit;
		end
	end

endmodule

