#!/usr/bin/python3

from math import pi as pi
from collections import OrderedDict

# calculate "type III" loop compensation circuit parameters
# for all output rails of TPS652510.
# see datasheet section "Loop Compensation" (pg. 17 ff.)


# System parameters
# =================

# input voltage [V]
v_in = 15

# main switching frequency [Hz]
f_switch = 900e3

# cross over frequency [Hz]
f_c = f_switch / 10.

# error amplifier transconductance [1/Ohm]
g_M = 130e-6

# COMP to ILX gm [A/V]
gm_ps = 10.

# internal voltage reference [V]
v_ref = 0.8

# equivalent series resistance of output rail capacitors [Ohm]
r_esr = 0.1

# amount of inductor ripple relative to max output current (see pg 15)
k_ind = 0.2

# Rail parameters
# ===============

rails = [
    {
        # output voltage [V]
        'V': 12.,
        # output current [A]
        'I': 300e-3,    # (250mA average, 500mA max)
        # output capacitive load [F]
        'C': 14e-6,

        # PICK some realistic part values:
        'RC': 7500,
        'CC': 100e-9,
        'CROLL': 100e-12,
        'L': 4.7e-6,
    },
    {
        'V': 3.3,
        'I': 220e-3,
        'C': 7e-6,

        # PICK some realistic part values:
        'RC': 3000.,
        'CC': 33e-9,
        'CROLL': 220e-12,
        'L': 4.7e-6,
    },
    {
        'V': 1.2,
        'I': 555e-6,
        'C': 1.1e-6,

        # PICK some realistic part values:
        'RC': 470,
        'CC': 4.7e-6,
        'CROLL': 220e-12,
        'L': 220e-6,
    },
]


# Derived values
# ==============

# effective resistance of load
def R(v, i):
    return v/i

# compensation network resistor
def RC(v, c):
    return 2*pi*f_c*c / (g_M * gm_ps)

# compensation network 
def CC(r, c, rc):
    return r * c / rc

def CROLL(c, rc):
    return r_esr * c / rc

print("THESE ARE PRELIMINARY VALUES. STILL NEED TO BE VERIFIED.")

for rail in rails:
    v = rail['V']
    i = rail['I']
    c = rail['C']

    if 'R' in rail:
        r = rail['R']
    else:
        r = R(v, i)

    if 'RC' in rail:
        rc = rail['RC']
    else:
        rc = RC(v, c)

    if 'CC' in rail:
        cc = rail['CC']
    else:
        cc = CC(r, c, rc)

    if 'CROLL' in rail:
        croll = rail['CROLL']
    else:
        croll = CROLL(c, rc)

    fp_roll = 1 / (2 * pi * rc * croll)

    # also calculate optimal inductor values
    if 'L' in rail:
        l = rail['L']
    else:
        l = (v_in - v) * v / (i * k_ind * v_in * f_switch)

    ripple = (v_in - v) * v / (l * v_in * f_switch)

    c_min = i*i*l / (v * ripple)

    print("rail V:{} I:{} C:{}\n\tR:{}\n\tRC:{}\n\tCC:{}\n\tCROLL:{}\n\tFPROLL:{}\n\tL:{}\n\tRIPPLE:{}\n\tCMIN:{}".format(
                v, i, c, r, rc, cc, croll, fp_roll, l, ripple, c_min))

    if fp_roll < 2 * f_c:
        print("\n\tWARNING: fp_roll is too close to f_c={}!\n".format(f_c))
