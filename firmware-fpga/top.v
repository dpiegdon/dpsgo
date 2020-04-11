`default_nettype none

module top(
	input  wire SCK,
	input  wire SS,
	input  wire SDI,
	output wire SDO,
	output wire FPGA_INT,
	output wire FPGA_WDT,

	input  wire PLL_OUT_REF,
	input  wire GPS_PULSE,

	input  wire BTN_BLUE,

	input  wire ENCODER_A,
	input  wire ENCODER_B,
	input  wire ENCODER_BTN,

	output wire [DISPLAY_PINCOUNT-1:0] LED_MATRIX
	);


	localparam DISPLAY_PIXELCOUNT = 12;
	localparam DISPLAY_PINCOUNT = $rtoi($ceil( (1.0 + $sqrt(1.0 + 4.0 * DISPLAY_PIXELCOUNT)) / 2 ));
	localparam DISPLAY_INDEXBITS = $clog2(DISPLAY_PIXELCOUNT+1);



	// Clock counter
	wire [31:0] system_clk;
	clock_prescaler #(.WIDTH(32)) system_clock_prescaler(PLL_OUT_REF, system_clk, 0);


	reg [35:0] counter = 0;
	reg [35:0] latched_counter = 0;

	reg [3:0] gps_pulse_stabilizer = 0;
	reg [3:0] gps_clock = 0;
	reg [3:0] gps_average_count = 0;
	wire counter_was_received;
	always @(negedge system_clk[0]) begin
		gps_pulse_stabilizer = { GPS_PULSE, gps_pulse_stabilizer[2:0] };
		if(gps_pulse_stabilizer[1:0] == 2'b10) begin
			// rising edge on GPS_PULSE
			if(gps_clock > gps_average_count) begin
				latched_counter <= counter;
				counter <= 0;
				gps_clock <= 0;
			end else begin
				gps_clock <= gps_clock + 1;
				if(!&counter) begin
					counter <= counter + 1;
				end
				if(counter_was_received) begin
					latched_counter <= 0;
				end
			end
		end else begin
			if(!&counter) begin
				counter <= counter + 1;
			end
			if(counter_was_received) begin
				latched_counter <= 0;
			end
		end
	end

	// LED matrix
	wire display_pixelclock = system_clk[18];
	reg [DISPLAY_PIXELCOUNT-1:0] display_state = 0;
	wire [DISPLAY_PINCOUNT-1:0] display_en;
	wire [DISPLAY_PINCOUNT-1:0] display_out;

	generate
		genvar i;
		for(i = 0; i < DISPLAY_PINCOUNT; i = i+1) begin : display_drivers
			tristate_output driver[i](LED_MATRIX[i], display_en[i], display_out[i]);
		end
	endgenerate

	charlieplex_display #(.PIXELCOUNT(DISPLAY_PIXELCOUNT)) display(
		.pixelclock(display_pixelclock), .enable(1), .pixelstate(display_state), .out_en(display_en), .out_value(display_out));


	// Input devices
	wire clear_inputs;
	wire encoder_a;
	wire encoder_b;
	wire encoder_up = encoder_a;	// FIXME
	wire encoder_down = encoder_b;	// FIXME
	wire encoder_button;
	wire button_blue;

	reg [3:0] input_state = 4'b0;

	debounced_button #(.DEBOUNCE_CYCLES(7), .CLOCKED_EDGE_OUT(1))
		debounce_encoder_a(.clk(system_clk[18]), .in(ENCODER_A), .out(encoder_a));	// FIXME only catches half the edges we need!
	debounced_button #(.DEBOUNCE_CYCLES(7), .CLOCKED_EDGE_OUT(1))
		debounce_encoder_b(.clk(system_clk[18]), .in(ENCODER_B), .out(encoder_b));	// FIXME only catches half the edges we need!
	debounced_button #(.DEBOUNCE_CYCLES(7), .CLOCKED_EDGE_OUT(1))
		debounce_bt_enc(.clk(system_clk[18]), .in(ENCODER_BTN), .out(encoder_button));
	debounced_button #(.DEBOUNCE_CYCLES(7), .CLOCKED_EDGE_OUT(1))
		debounce_bt_blue(.clk(system_clk[18]), .in(BTN_BLUE), .out(button_blue));

	always @(negedge system_clk[0]) begin
		if(clear_inputs) begin
			input_state <= 4'b0;
		end else begin
			input_state <= input_state | { encoder_up, encoder_down, encoder_button, button_blue };
		end
	end


	// SPI interface
	wire spi_miso_en;
	wire spi_miso_out;
	wire [39:0] spi_value_miso = { input_state, latched_counter };
	wire [39:0] spi_value_mosi;
	wire spi_cs_start;
	wire spi_cs_stop;
	wire spi_value_valid;

	tristate_output miso_driver(SDO, spi_miso_en, spi_miso_out);
	simple_spi_slave #(.WIDTH(40)) spi_slave(
		.system_clk(system_clk[0]),
		.pin_ncs(SS),
		.pin_clk(SCK),
		.pin_mosi(SDI),
		.pin_miso(spi_miso_out),
		.pin_miso_en(spi_miso_en),
		.value_miso(spi_value_miso),
		.value_mosi(spi_value_mosi),
		.cs_start(spi_cs_start),
		.cs_stop(spi_cs_stop),
		.value_valid(spi_value_valid));

	assign counter_was_received = spi_value_valid;
	assign clear_inputs = spi_value_valid;

	always @(negedge system_clk[0]) begin
		if(spi_value_valid) begin
			{ gps_average_count, display_state } <= spi_value_mosi[ 4 + DISPLAY_PIXELCOUNT-1 : 0];
		end
	end


	// Interrupt generation
	assign FPGA_INT = |spi_value_miso;
	assign FPGA_WDT = system_clk[25];

endmodule
