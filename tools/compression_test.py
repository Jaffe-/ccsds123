import json
import sys
import os
import subprocess

EMPORDA_FILENAME = "emporda_config_temp.txt"
COMP_FILENAME = "comp_temp"
CONVERTED_FILENAME = "converted_img"
HEADER_SIZE = 19

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

def emporda_callstring(image_filename, dimensions, order, datatype, endianness):
    return "emporda -c -i %s -o %s -ig %s %s %s %s 0 -so %s -e %s -f %s -v" % \
             (image_filename, COMP_FILENAME, dimensions[2], dimensions[1], dimensions[0], datatype,
              2 if order == "BIP" else 0, 1 if endianness == "little" else 0, EMPORDA_FILENAME)

def make_image_list(basedir):
    pics = {"HICO_L1B": [{"idx": [1, 2, 3, 4, 6], "dim": [512, 2000], "signed": True},
                         {"idx": [5], "dim": [500, 2000], "signed": True}]}#,
            # "HICO_L2": [{"idx": [1, 2, 3, 4, 6], "dim": [512, 2000], "signed": True}],
            # "AVIRIS_L1": [{"idx": [1], "dim": [754, 2776], "signed": True}],
            # "AVIRIS_L2": [{"idx": [1, 2, 3, 4], "dim": [614, 512], "signed": True}]}
    img_descs = []

    for (img_type, descs) in pics.items():
        for desc in descs:
            signed = desc["signed"]
            dim = desc["dim"]
            idcs = desc["idx"]
            for i in idcs:
                for pca_dim in [10, 20, 30, 40, 50]:
                    filestr = "%s/%s_%sBSQ_M_PCA%s.bsq" % (basedir, img_type, i, pca_dim)
                    img_desc = {"filename": filestr,
                                "order": "BSQ",
                                "endianness": "little",
                                "signed": signed,
                                "NX": dim[0],
                                "NY": dim[1],
                                "NZ": pca_dim}
                    img_descs.append(img_desc)
    return img_descs

def main():
    if len(sys.argv) < 2:
        print("No config given")
        return -1

    config_file = sys.argv[1]
    config = None

    with open(config_file, 'r') as config_file:
        config = json.loads(config_file.read())

    parameters = config['parameters']
    #    images = config['images']
    images = make_image_list("/mnt/bigdisk/HSIs/PCAd/int16")
    results = []

    for image_desc in images:
        image_results = []
        for order in ["BIP"]:#, "FLIP"]:
            image_filename = image_desc["filename"]

            if order == "FLIP":
                dimensions = (image_desc["NY"], image_desc["NZ"], image_desc["NX"])
                comp_order = "BIP"
                to_order = "BSQ"
            else:
                dimensions = (image_desc["NX"], image_desc["NY"], image_desc["NZ"])
                comp_order = order
                to_order = order

            # If the order of the image is not the necessary order for this run, we need to do a conversion
            if to_order != image_desc["order"]:
                print("Converting from %s to %s (%s)" % (image_desc["order"], to_order, order))
                subprocess.call("cube_rearrange %s %s %s %s %s %s %s 2" %
                                (image_filename, image_desc["order"], CONVERTED_FILENAME, to_order,
                                 image_desc["NX"], image_desc["NY"], image_desc["NZ"]), shell=True)
                image_filename = CONVERTED_FILENAME
            for encoder in ["sample"]:
                # When sample adaptive encoder is used, BSQ and BIP will yield the same results, so no need to run
                # this for BSQ images
                if encoder == "sample" and order == "BSQ":
                    continue
                parameters["encoder"] = encoder
                for mode in ["full"]:
                    parameters["mode"] = mode
                    for locsum_mode in ["neighbor"]:
                        parameters["locsum_mode"] = locsum_mode
                        id_string = "%s %s %s %s %s" % (image_desc["filename"], order, encoder, mode, locsum_mode)
                        print("******** Starting %s, %s ********" % (id_string, comp_order))

                        # Write the configuration for this run of Emporda
                        write_emporda_config(dimensions, comp_order, parameters)

                        # Build the call string for Emporda and run
                        datatype = '3' if image_desc["signed"] else '2'
                        callstring = emporda_callstring(image_filename, dimensions, comp_order, datatype, image_desc["endianness"])
                        print(callstring)
                        subprocess.call(callstring, shell=True)

                        compressed_size = os.stat(COMP_FILENAME).st_size
                        compression_ratio = float(compressed_size) / (dimensions[0] * dimensions[1] * dimensions[2] * 2);

                        image_results.append((image_desc["filename"], order, encoder, mode, locsum_mode, compressed_size))
                        print("Done %s:\t%s" % (id_string, compression_ratio))
        results.append(image_results[:])

    for result in results:
        for img_result in result:
            bits = (img_result[5] - HEADER_SIZE) * 8
            print("%s\t%s\t%s\t%s\t%s:\t%s\t%s" % (img_result + (bits,)))
        print("----------------------------------------------")


main()
