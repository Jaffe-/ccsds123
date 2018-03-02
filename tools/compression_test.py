import json
import sys
import os
import subprocess
from ccsds_lib import *

COMP_FILENAME = "comp_temp"
CONVERTED_FILENAME = "converted_img"
HEADER_SIZE=19

def make_image_list(basedir):
    pics = {"HICO_L1B": [{"idx": [1, 2, 3, 4, 6], "dim": [512, 2000], "signed": True},
                         {"idx": [5], "dim": [500, 2000], "signed": True}]}
            #"HICO_L2": [{"idx": [1, 2, 3, 4, 6], "dim": [512, 2000], "signed": True}],
            #"AVIRIS_L1": [{"idx": [1], "dim": [754, 2776], "signed": True}],
            #"AVIRIS_L2": [{"idx": [1, 2, 3, 4], "dim": [614, 512], "signed": True}]}
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
        print("usage: compression_test.py <config file>")
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
            if image_desc["order"] != to_order:
                convert(image_desc, to_order, CONVERTED_FILENAME)
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
                        callstring = emporda_callstring(image_filename, dimensions, comp_order, datatype, image_desc["endianness"], COMP_FILENAME)
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
