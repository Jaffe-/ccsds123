from ccsds_lib import *
import sys
import subprocess
import json
import os

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

    # Write emporda config file
    write_emporda_config(dimensions, "BIP", parameters)

    # Write verilog parameter file to be included in test bench
    write_sim_params(dimensions, parameters, sim_params_filename)

    # Call emporda
    callstring = emporda_callstring(img_filename, dimensions, "BIP", "3", "little", encoded_filename)
    print(callstring)
    subprocess.call(callstring, shell=True)
    compressed_size = os.stat(encoded_filename).st_size - HEADER_SIZE

    # Strip the header from the compressed golden file
    subprocess.call("dd bs=%s skip=1 if=%s of=%s" % (HEADER_SIZE, encoded_filename, golden_filename), shell=True)

    # Count trailing zeroes
    with open(golden_filename, 'rb') as f:
        current_pos = -1
        while (True):
            f.seek(current_pos, 2)
            if f.read(1) != '\x00':
                break
            else:
                current_pos -= 1

    # We need to remove trailing zeroes and add zeroes until the compressed size is a multiple of 64 bits
    stripped_change = -current_pos
    stripped_size = compressed_size - stripped_change
    delta = -stripped_change + 8 - (stripped_size % 8)

    if (delta != 0):
        sign = '+' if delta > 0 else ''
        subprocess.call("truncate -s %s%s %s" % (sign, delta, golden_filename), shell=True)

    subprocess.call("rm %s" % encoded_filename, shell=True)

main()
