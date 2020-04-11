`default_nettype none

module top(
	input  wire SCK,
	input  wire SS,
	input  wire SDI,
	output wire SDO,
	output wire FPGA_INT,

	input  wire PLL_OUT_REF,
	input  wire GPS_PULSE,

	input  wire BTN_RED,

	input  wire ENCODER_A,
	input  wire ENCODER_B,
	input  wire ENCODER_BTN,

	output wire [DISPLAY_PINCOUNT-1:0] LED_MATRIX
	);


	localparam DISPLAY_PIXELCOUNT = 12;
	localparam DISPLAY_PINCOUNT = $rtoi($ceil( (1.0 + $sqrt(1.0 + 4.0 * DISPLAY_PIXELCOUNT)) / 2 ));
	localparam DISPLAY_INDEXBITS = $clog2(DISPLAY_PIXELCOUNT+1);



	// Clock counter
	wire [31:0] system_clock;
	clock_prescaler #(.WIDTH(32)) system_clock_prescaler(PLL_OUT_REF, system_clock, 0);


	reg [31:0] counter = 0;
	reg [31:0] latched_counter = 0;

	reg [3:0] gps_pulse_stabilizer = 0;
	reg [3:0] gps_clock = 0;
	reg [3:0] gps_average_count = 0;
	wire counter_was_received;
	always @(negedge system_clock[0]) begin
		gps_pulse_stabilizer = { GPS_PULSE, gps_pulse_stabilizer[2:0] };
		if(gps_pulse_stabilizer[1:0] == 2'b10) begin
			// rising edge on GPS_PULSE
			if(gps_clock >= gps_average_count) begin
				gps_clock <= 0;
				latched_counter <= counter;
				counter <= 0;
			end else begin
				gps_clock <= gps_clock + 1;
				counter <= counter + 1;
				if(counter_was_received) begin
					latched_counter <= 0;
				end
			end
		end else begin
			counter <= counter + 1;
			if(counter_was_received) begin
				latched_counter <= 0;
			end
		end
	end

	// LED matrix
	wire display_pixelclock = system_clock[15];
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


	// input devices
	wire clear_buttons;
	wire encoder_up;
	// FIXME encoder up/down
	wire encoder_down;
	wire encoder_button;
	// FIXME
	wire button_red;

	reg [3:0] button_state = 4'b0;

	debounced_button #(.DEBOUNCE_CYCLES(7), .CLOCKED_EDGE_OUT(1))
		bt_enc(.clk(system_clock[15]), .in(ENCODER_BTN), .out(encoder_button));
	debounced_button #(.DEBOUNCE_CYCLES(7), .CLOCKED_EDGE_OUT(1))
		bt_red(.clk(system_clock[15]), .in(BTN_RED), .out(button_red));

	always @(negedge system_clock[0]) begin
		if(clear_buttons) begin
			button_state <= 4'b0;
		end else begin
			button_state <= button_state | { encoder_up, encoder_down, encoder_button, button_red };
		end
	end


	// Interrupt generation
	assign FPGA_INT = |{ latched_counter, button_state };


	// SPI interface
	wire spi_miso_en;
	wire spi_miso_out;
	wire [39:0] spi_value_miso;
	wire [39:0] spi_value_mosi;
	wire spi_cs_start;
	wire spi_cs_stop;
	wire spi_value_valid;

	tristate_output miso_driver(SDO, spi_miso_en, spi_miso_out);
	simple_spi_slave #(.WIDTH(40)) spi_slave(
		.system_clk(system_clock[0]),
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

	assign spi_value_miso = { latched_counter, button_state };
	assign counter_was_received = spi_value_valid;
	assign clear_buttons = spi_value_valid;

	always @(negedge system_clock[0]) begin
		if(spi_value_valid) begin
			display_state <= spi_value_mosi[DISPLAY_PIXELCOUNT-1:0];
		end
	end

endmodule
