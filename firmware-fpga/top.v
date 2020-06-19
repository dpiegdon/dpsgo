`default_nettype none

module top(
	input wire MAJOR_CLOCK,
	output wire FPGA_INT,
	input  wire MINOR_CLOCK,

	input wire SS,
	input wire SCK,
	input wire SDI,
	output wire SDO);

	localparam CPOL = 1'b1;
	localparam DOWNCOUNT_WIDTH = 8;
	localparam UPCOUNT_WIDTH = 34;
	localparam WIDTH = UPCOUNT_WIDTH + DOWNCOUNT_WIDTH;

	/*
	 * upcount and downcount combined are the SPI word. they are
	 * transparent shift registers. no counting will be done if
	 * CS is active, so that the controller can replace the
	 * contents unobstructed. downcount is high-side of SPI-word,
	 * upcount is low-side of SPI word. all values are transmitted
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
	 * ==>  |  downcount  |  upcount  |  ==>
	 *      \-------------|-----------/
	 */

	reg [UPCOUNT_WIDTH-1:0] upcount;
	reg [DOWNCOUNT_WIDTH-1:0] downcount;

	reg minor_edge_seen = 0;
	wire allow_downcount = |downcount;
	wire do_upcount = allow_downcount && minor_edge_seen && !&upcount;

	assign FPGA_INT = !allow_downcount;

	wire minor_sync;
	wire minor_rising;
	wire minor_falling;
	synchronizer minor_syncer(MAJOR_CLOCK, MINOR_CLOCK, minor_sync, minor_rising, minor_falling);

	wire ss_sync;
	wire ss_rising;
	wire ss_falling;
	synchronizer ss_syncer(MAJOR_CLOCK, CPOL ^ SCK, ss_sync, ss_rising, ss_falling);
	wire cs_start = (ss_falling);
	wire cs_active = (!ss_sync);
	wire cs_stop = (ss_rising);

	wire sck_sync;
	wire sck_rising;
	wire sck_falling;
	synchronizer sck_syncer(MAJOR_CLOCK, SCK, sck_sync, sck_rising, sck_falling);
	wire sample_in = sck_rising;
	wire latch_out = sck_falling;

	wire mosi_sync;
	synchronizer mosi_syncer(MAJOR_CLOCK, SDI, mosi_sync);

	reg miso_out;
	tristate_output miso_driver(SDO, !SS, miso_out);

	always @(posedge MAJOR_CLOCK) begin
		if(cs_active) begin
			// SPI shift logic
			if(sample_in) begin
				{downcount, upcount} <= { mosi_sync, downcount, upcount[UPCOUNT_WIDTH-1:1] };
			end else if(latch_out) begin
				miso_out <= upcount[0];
			end
			minor_edge_seen <= 0;
		end else begin
			// counting logic
			if(do_upcount) begin
				upcount = upcount + 1;
			end
			if(minor_rising) begin
				if(minor_edge_seen) begin
					downcount = downcount - 1;
				end
				minor_edge_seen <= 1;
			end
			miso_out <= 0;
		end
	end

endmodule

