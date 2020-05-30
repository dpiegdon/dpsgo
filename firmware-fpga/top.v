`default_nettype none

module top(
	input  wire SCK,
	input  wire SS,
	input  wire SDI,
	output wire SDO,
	output wire FPGA_INT,

	input  wire PLL_INT_REF,
	input  wire GPS_PULSE,
	input  wire TEMP_ALERT,

	input  wire ENCODER_A,
	input  wire ENCODER_B,
	input  wire ENCODER_BTN,
	input  wire BTN_BLUE,
	);


	/* register to hold how many gps-clocks the firmware wants to average over */
	localparam GPSCLOCKWIDTH = 5;
	/* 100MHz, as the maximum clock frequency, fits into 27 bits if counted
	 * for a second: ld(100e6)=26.57 */
	localparam COUNTERWIDTH = 27 + GPSCLOCKWIDTH;

	localparam INPUTWIDTH = 8;
	localparam SPIREGWIDTH = INPUTWIDTH + COUNTERWIDTH;


	// System clock counter
	wire [6:0] system_clk;
	always @(posedge PLL_INT_REF) begin
		system_clk <= system_clk+1;
	end


	// GPS-triggered counter
	reg [COUNTERWIDTH-1:0] counter = 0;
	reg [COUNTERWIDTH-1:0] latched_counter = 0;

	reg [GPSCLOCKWIDTH-1:0] gps_clock = 0;
	reg [GPSCLOCKWIDTH-1:0] gps_average = 0;
	reg [3:0] gps_pulse_stabilizer = 0;

	wire counter_was_received;

	always @(posedge PLL_INT_REF) begin
		gps_pulse_stabilizer = { GPS_PULSE, gps_pulse_stabilizer[3:1] };
		if(gps_pulse_stabilizer[1:0] == 2'b10) begin
			// rising edge on GPS_PULSE
			if(gps_clock == gps_average) begin
				// this averages over 1+gps_average GPS pulses
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


	// external inputs
	wire clear_inputs;
	wire encoder_a;
	wire encoder_b;
	wire encoder_ccw;
	wire encoder_cw;
	wire encoder_button;
	wire button_blue;

	rotary_encoder_pullup #(.DEBOUNCE_CYCLES(0))
		rotary_encoder(.clk(system_clk[6]), .in_a(ENCODER_A), .in_b(ENCODER_B), .out_ccw(encoder_ccw), .out_cw(encoder_cw));
	debounced_button #(.DEBOUNCE_CYCLES(1))
		debounce_bt_enc(.clk(system_clk[6]), .in(ENCODER_BTN), .out(encoder_button));
	debounced_button #(.DEBOUNCE_CYCLES(1))
		debounce_bt_blue(.clk(system_clk[6]), .in(BTN_BLUE), .out(button_blue));

	// IO state
	reg [INPUTWIDTH-1:0] input_state = 0;
	wire [INPUTWIDTH-1:0] current_input = { TEMP_ALERT, encoder_ccw, encoder_cw, encoder_button, button_blue };
	reg [INPUTWIDTH-1:0] previous_input = 0;

	always @(posedge PLL_INT_REF) begin
		if(clear_inputs) begin
			input_state <= 0;
		end else begin
			// IO clock is slower, so only mark rising edges
			input_state <= input_state | ((previous_input ^ current_input) & ~current_input);
		end
		previous_input <= current_input;
	end


	// SPI interface
	wire spi_miso_en;
	wire spi_miso_out;
	wire [SPIREGWIDTH-1:0] spi_value_miso;
	wire [SPIREGWIDTH-1:0] spi_value_mosi;
	wire spi_cs_start;
	wire spi_cs_stop;
	wire spi_value_valid;

	assign counter_was_received = spi_value_valid;
	assign clear_inputs = spi_value_valid;

	tristate_output miso_driver(SDO, spi_miso_en, spi_miso_out);
	simple_spi_slave #(.WIDTH(SPIREGWIDTH), .CPOL(1'b1)) spi_slave(
		.system_clk(PLL_INT_REF),
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

	assign spi_value_miso = { latched_counter, input_state };

	always @(posedge PLL_INT_REF) begin
		if(spi_value_valid) begin
			gps_average <= spi_value_mosi[GPSCLOCKWIDTH-1:0];
		end
	end


	// Interrupt generation
	assign FPGA_INT = |spi_value_miso;

endmodule
