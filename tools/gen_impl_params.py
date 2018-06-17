from ccsds_lib import *
import sys
import json

def main():
    if len(sys.argv) < 2:
        print("usage: gen_impl_params.py <config>")
        return -1

    config_file = sys.argv[1]

    config = None
    with open(config_file, 'r') as config_file:
        config = json.loads(config_file.read())

    parameters = config['parameters']
    image = config['images'][0]
    dimensions = (image["NX"], image["NY"], image["NZ"])

    # Write verilog parameter file to be included in test bench
    write_sim_params(dimensions, parameters, image["signed"] == "true", "tb/impl_params.v")
    write_vhdl_params(dimensions, parameters, image["signed"] == "true", "tb/synth_params.vhd")

main()
