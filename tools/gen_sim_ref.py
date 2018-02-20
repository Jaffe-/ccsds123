from ccsds_lib import *
import sys
import subprocess
import json

HEADER_SIZE = 19

def main():
    if len(sys.argv) < 3:
        print("usage: gen_sim_ref.py <config file> <verilog param file> <golden file>")
        return -1

    config_file = sys.argv[1]
    config = None

    with open(config_file, 'r') as config_file:
        config = json.loads(config_file.read())

    sim_params_filename = sys.argv[2]
    golden_filename = sys.argv[3]

    parameters = config['parameters']
    image = config['images'][0]
    dimensions = (image["NX"], image["NY"], image["NZ"])

    img_filename = image["filename"]
    if image["order"] != "BIP":
        img_filename = image["filename"] + ".bip"
        convert(image, "BIP", img_filename)

    encoded_filename = golden_filename + ".tmp"
    write_emporda_config(dimensions, "BIP", parameters)
    write_sim_params(dimensions, parameters, sim_params_filename)
    callstring = emporda_callstring(img_filename, dimensions, "BIP", "3", "little", encoded_filename)
    print(callstring)
    subprocess.call(callstring, shell=True)

    # Strip the header from the compressed golden file
    subprocess.call("dd bs=%s skip=1 if=%s of=%s" % (HEADER_SIZE, encoded_filename, golden_filename), shell=True)
    subprocess.call("rm %s" % encoded_filename, shell=True)

main()
