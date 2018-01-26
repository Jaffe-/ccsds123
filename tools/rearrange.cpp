#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>

int main(int argc, char **argv)
{
    if (argc < 6) {
        std::cout << "Usage:\n"
                  << "rearrange input output Nx Ny Nz bpc\n";
        return -1;
    }

    const std::string infile_name(argv[1]);
    const std::string outfile_name(argv[2]);
    const int Nx = std::stoi(std::string(argv[3]));
    const int Ny = std::stoi(std::string(argv[4]));
    const int Nz = std::stoi(std::string(argv[5]));
    const int bpc = std::stoi(std::string(argv[6]));

    std::vector<uint16_t> image(Nx*Ny*Nz);
    std::vector<uint16_t> processed_image(Nx*Ny*Nz);
    std::ifstream infile(infile_name, std::ifstream::in | std::ifstream::binary);

    infile.seekg(0,std::ios::end);
    std::streampos size = infile.tellg();
    infile.seekg(0,std::ios::beg);

    const int expected_size = Nx*Ny*Nz*bpc;

    if (size < expected_size) {
        std::cout << "ERROR: File size is smaller than the given cube size\n";
        return -1;
    }
    else if (size > expected_size) {
        std::cout << "WARNING: File size is large than the given cube size\n";
    }

    std::cout << "Loading image\n";
    infile.read((char*)&image[0], Nx*Ny*Nz*bpc);

    std::cout << "Rearranging\n";
    int i = 0;
    for (int z = 0; z < Nz; z++) {
        for (int y = 0; y < Ny; y++) {
            for (int x = 0; x < Nx; x++) {
                processed_image[i++] = image[y*Nx*Nz + x*Nz + z];
            }
        }
    }

    std::cout << "Writing output file\n";

    std::ofstream outfile(outfile_name, std::ofstream::out | std::ofstream::binary);
    outfile.write((char*)&processed_image[0], Nx*Ny*Nz*bpc);

    std::cout << "Done.\n";
}
