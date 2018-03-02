import sys;
import struct;

def gen_cube(filename, NX, NY, NZ):
    with open(filename, 'wb') as f:
        for i in range(0, NX*NY*NZ):
            f.write(struct.pack('<H', i % 2**16))

def main():
    if len(sys.argv) <= 4:
        print("Usage: gen_cube filename NX NY NZ")
        return

    filename = sys.argv[1]
    NX = int(sys.argv[2])
    NY = int(sys.argv[3])
    NZ = int(sys.argv[4])

    gen_cube(filename, NX, NY, NZ)

main()
