import sys
import ccsds_lib

def main():
    if len(sys.argv) <= 4:
        print("Usage: gen_cube filename NX NY NZ")
        return

    filename = sys.argv[1]
    NX = int(sys.argv[2])
    NY = int(sys.argv[3])
    NZ = int(sys.argv[4])

    ccsds_lib.gen_cube(filename, NX, NY, NZ)

main()
