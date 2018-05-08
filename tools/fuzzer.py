import random
from ccsds_lib import *
from time import gmtime, strftime
import sys
import shutil
import json

def random_range(lower, upper):
    return random.randrange(lower, upper + 1, 1)

def fill_parameters(parameters):
    D = parameters['D'] if 'D' in parameters else random_range(2, 16)
    P = random_range(0, 15)
    omega = parameters['OMEGA'] if 'OMEGA' in parameters else random_range(4, 19)
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
    pipelines = random_range(1, 8)

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
                     "PIPELINES": pipelines,
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

    # Generate random sized cube
    NX = random_range(10, 100)
    NY = random_range(10, 2500/NX)
    NZ = random_range(3*parameters["PIPELINES"], 100)

    dimensions = (NX, NY, NZ)
    gen_cube(img_filename, NX, NY, NZ)

    generate_golden(parameters, dimensions, False, img_filename, golden_filename)

    # Generate verilog include file
    write_sim_params(dimensions, parameters, verilog_filename)

    # Run simulation
    sim_ret = subprocess.call("./simulate.sh %s %s" % (img_filename, golden_filename), shell=True)

    if sim_ret != 0 or not compare_bitstreams("out_0.bin", golden_filename) or not compare_bitstreams("out_1.bin", golden_filename):
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
        return (False, parameters)

    return (True, parameters)

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
    used_parameters = []
    for i in range(0, runs):
        (passed, parameters) = run_test(fixed_parameters.copy())
        used_parameters.append(parameters)
        if not passed:
            fails += 1
        print("********************************************************************************")

    print("Done. %s out of %s tests passed.\n" % (runs-fails, runs))
    print("Parameters that have been covered:")
    for (k, _) in used_parameters[0].items():
        sys.stdout.write("%s: " % k)
        already_printed = []
        for i in range(0, runs):
            val = used_parameters[i][k]
            if not val in already_printed:
                sys.stdout.write("%s, " % val)
                already_printed.append(val)
        print("\b\b ")
main()
