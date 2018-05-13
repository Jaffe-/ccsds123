from ccsds_lib import *
import sys
import json

def main():
    if len(sys.argv) < 3:
        print("usage: gen_sim_ref.py <config file> <verilog param file> <golden file>")
        return -1

    config_file = sys.argv[1]
    sim_params_filename = sys.argv[2]
    golden_filename = sys.argv[3]

    config = None
    with open(config_file, 'r') as config_file:
        config = json.loads(config_file.read())

    parameters = config['parameters']
    image = config['images'][0]
    dimensions = (image["NX"], image["NY"], image["NZ"])

    img_filename = image["filename"]
    if image["order"] != "BIP":
        img_filename = image["filename"] + ".bip"
        convert(image, "BIP", img_filename)

    encoded_filename = golden_filename + ".tmp"

    # Write verilog parameter file to be included in test bench
    write_sim_params(dimensions, parameters, image["signed"] == "true", sim_params_filename)

    # Call Emporda to generate the golden reference file
    generate_golden(parameters, dimensions, image["signed"] == "true", img_filename, golden_filename)

main()
