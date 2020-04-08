<!-- vim: tw=72 fo+=a
-->

DPSGO
=====

David's Pretty Satisfactory Gps-disciplined Oscillator


GPS disciplined oscillator
==========================

Accurate frequency reference for measurement equipment.

A 10MHz OCXO is tuned to a timing signal of a GPS, e.g. the 1PPS output.
A frequency syntheziser then generates different signals from this
reference as needed/configured by the end user.


System components
-----------------

OCXO: refurbished 8663-XS with 10MHz output

DAC: AD5761R 16bit high quality low speed DAC with internal reference,
generates tuning signal for OCXO

GPS: uBlox NEO 7M module with 1PPS output

VCXO: Si5351-C frequency generator for programmable output frequencies

 * 10MHz reference output signal

 * some higher frequency, e.g. 60MHz as test input for frequency
   comparison in the FPGA (for automatic tuning)

 * other programmable outputs

FPGA: Lattice LP384: measures difference between the generated reference
output and the GPS reference signal. That information is used to
calculate the tuning voltage for the OCXO.

uC: nRF52840 as system- and display-controller

Power input: 14-16V

PMIC: TPS652510 PMIC generating three rails of:

 * 12V: OCXO

 * 10V: DAC

 * 3.3V: digital logic

Additional LDO for:

 * 1.2V FPGA core voltage (could be used for something else, as 1.2V can
   easily be generated by a MIC5365-1.2YC5)

Display: SSD1306

Interfaces:

 * USB to both GPS receiver and microcontroller

 * potentially Bluetooth or 802.11.5 to microcontroller

 * (internally) JTAG to microcontroller

