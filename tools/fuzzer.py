import random
from ccsds_lib import *
from time import gmtime, strftime
import sys
import shutil
import json

def random_range(lower, upper):
    return random.randrange(lower, upper + 1, 1)

def fill_parameters(parameters):
    D = random_range(2, 16)
    P = random_range(0, 15)
    omega = random_range(4, 19)
    v_min = random_range(-6, 9)
    v_max = random_range(v_min, 9)
    t_inc = random_range(4, 11)
    R = random_range(max(32, D + omega + 2), 64)
    U_max = random_range(8, 32)
    counter_size = random_range(4, 9)
    initial_count = random_range(1, counter_size - 1)
    K = random_range(0, D - 2)
    mode = random_range(0, 1)
    locsum_mode = random_range(0, 1)

    random_params = {"D": D,
                     "P": P,
                     "R": R,
                     "OMEGA": omega,
                     "TINC_LOG": t_inc,
                     "V_MIN": v_min,
                     "V_MAX": v_max,
                     "UMAX": U_max,
                     "COUNTER_SIZE": counter_size,
                     "INITIAL_COUNT": initial_count,
                     "K": K,
                     "mode": "full" if mode == 1 else "reduced",
                     "locsum_mode": "neighbor" if locsum_mode == 1 else "column",
    }

    # Fill in missing parameters
    for (k, v) in random_params.items():
        if not k in parameters:
            parameters[k] = v

    return parameters

def run_test(fixed_parameters):
    img_filename = "input.bip"
    golden_filename = "golden"
    verilog_filename = "gen_comp_params.v"

    parameters = fill_parameters(fixed_parameters)
    print("Parameters:")
    for (k,v) in parameters.items():
        print("%s = %s" % (k, v))
    pipelines = 3

    # Generate random sized cube
    NX = random_range(10, 100)
    NY = random_range(10, 2500/NX)
    NZ = random_range(3*pipelines, 100)

    dimensions = (NX, NY, NZ)
    gen_cube(img_filename, NX, NY, NZ)

    generate_golden(parameters, dimensions, img_filename, golden_filename)

    # Generate verilog include file
    write_sim_params(dimensions, parameters, verilog_filename)

    # Run simulation
    ret = subprocess.call("./simulate.sh %s %s" % (img_filename, golden_filename), shell=True)
    if ret != 0:
        print("Error detected")

        # If simulation failed we copy image file and configuration to a new directory so
        # the error can be investigated later
        timestamp = strftime("%m%d-%H%M%S", gmtime())
        run_dir = "failed_runs/%s" % timestamp
        if not os.path.exists(run_dir):
            os.makedirs(run_dir)
        shutil.copy(img_filename, run_dir)
        shutil.copy(golden_filename, run_dir)
        shutil.copy(verilog_filename, run_dir)
        shutil.copy("out_0.bin", run_dir)
        shutil.copy("out_1.bin", run_dir)
        with open('%s/conf.json' % run_dir, 'w') as json_file:
            json.dump(parameters, json_file)
            json.dump(dimensions, json_file)
        return False

    return True

def main():
    fixed_parameters = {"D": 16,
                        "out_word_size": 8,
                        "out_endianness": "little",
                        "encoder": "sample"}

    if len(sys.argv) < 2:
        print("usage: fuzzer.py <runs>")
        return -1

    runs = int(sys.argv[1])
    fails = 0
    for i in range(0, runs):
        if not run_test(fixed_parameters.copy()):
            fails += 1
        print("********************************************************************************")

    print("Done. %s out of %s tests passed." % (runs-fails, runs))
main()
