import subprocess

EMPORDA_FILENAME = "emporda_config_temp.txt"

def write_emporda_config(dimensions, order, parameters):
    subframe_interleaving_depth = 0
    if order == 'BIP':
        subframe_interleaving_depth = dimensions[2]

    emporda_params = {
        "DYNAMIC_RANGE": parameters['D'],
        "SAMPLE_ENCODING_ORDER": 1 if order == "BSQ" else 0,
        "SUBFRAME_INTERLEAVING_DEPTH": subframe_interleaving_depth,
        "OUTPUT_WORD_SIZE": parameters['out_word_size'],
        "ENTROPY_CODER_TYPE": 0 if parameters['encoder'] == 'sample' else 1,
        "NUMBER_PREDICTION_BANDS": parameters['P'],
        "PREDICTION_MODE": 0 if parameters['mode'] == 'full' else 1,
        "LOCAL_SUM_MODE": 0 if parameters['locsum_mode'] == 'neighbor' else 1,
        "REGISTER_SIZE": parameters['R'],
        "WEIGHT_COMPONENT_RESOLUTION": parameters['OMEGA'],
        "WEIGHT_UPDATE_SECI": parameters['TINC_LOG'],
        "WEIGHT_UPDATE_SE": parameters['V_MIN'],
        "WEIGHT_UPDATE_SEFP": parameters['V_MAX'],
        "WEIGHT_INITIALIZATION_METHOD": 0,
        "WEIGHT_INITIALIZATION_TF": 0,
        "WEIGHT_INITIALIZATION_RESOLUTION": 0,
        "UNARY_LENGTH_LIMIT": parameters['UMAX'],
        "RESCALING_COUNTER_SIZE": parameters['COUNTER_SIZE'],
        "INITIAL_COUNT_EXPONENT": parameters['INITIAL_COUNT'],
        "ACCUMULATOR_INITIALIZATION_TF": 0,
        "ACCUMULATOR_INITIALIZATION_CONSTANT": parameters['K'],
        }

    with open(EMPORDA_FILENAME, 'w') as f:
        for (emporda_str, val) in emporda_params.items():
            f.write("%s=%s\n" % (emporda_str, val))

def emporda_callstring(image_filename, dimensions, order, datatype, endianness, outfile):
    return "emporda -c -i %s -o %s -ig %s %s %s %s 0 -so %s -e %s -f %s -v" % \
             (image_filename, outfile, dimensions[2], dimensions[1], dimensions[0], datatype,
              2 if order == "BIP" else 0, 1 if endianness == "little" else 0, EMPORDA_FILENAME)

def convert(image_desc, to_order, out_filename):
    print("Converting from %s to %s" % (image_desc["order"], to_order))
    subprocess.call("cube_rearrange %s %s %s %s %s %s %s 2" %
                        (image_desc["filename"], image_desc["order"], out_filename, to_order,
                         image_desc["NX"], image_desc["NY"], image_desc["NZ"]), shell=True)

def write_sim_params(dimensions, parameters, filename):
    sim_params = {
        "NX": dimensions[0],
        "NY": dimensions[1],
        "NZ": dimensions[2],
        "D": parameters["D"],
        "P": parameters["P"],
        "R": parameters["R"],
        "OMEGA": parameters["OMEGA"],
        "TINC_LOG": parameters["TINC_LOG"],
        "V_MIN": parameters["V_MIN"],
        "V_MAX": parameters["V_MAX"],
        "KZ_PRIME": parameters["K"],
        "COUNTER_SIZE": parameters["COUNTER_SIZE"],
        "INITIAL_COUNT": parameters["INITIAL_COUNT"],
        "UMAX": parameters["UMAX"],
        "COL_ORIENTED": 1 if parameters["locsum_mode"] == "column" else 0,
        "REDUCED": 1 if parameters["mode"] == "reduced" else 0,
        "LITTLE_ENDIAN": 1 if parameters["out_endianness"] == "little" else 0,
        }

    with open(filename, 'w') as f:
        for (param_name, val) in sim_params.items():
            f.write("parameter %s = %s;\n" % (param_name, val))
