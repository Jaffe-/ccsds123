#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>
#include <string>
#include <algorithm>
#include <map>
#include <tuple>

int main(int argc, char **argv)
{
    if (argc < 6) {
        std::cout << "Usage:\n"
                  << "rearrange input in-format output out-format Nx Ny Nz bpc\n\n"
                  << " in-format, out-format: BIP, BIL, BSQ\n";
        return -1;
    }

    const std::string infile_name(argv[1]);
    std::string in_format(argv[2]);
    const std::string outfile_name(argv[3]);
    std::string out_format(argv[4]);
    const int Nx = std::stoi(std::string(argv[5]));
    const int Ny = std::stoi(std::string(argv[6]));
    const int Nz = std::stoi(std::string(argv[7]));
    const int bpc = std::stoi(std::string(argv[8]));

    std::transform(in_format.begin(), in_format.end(), in_format.begin(), ::tolower);
    std::transform(out_format.begin(), out_format.end(), out_format.begin(), ::tolower);

    std::map<std::string, std::tuple<int, int, int>> mappings {
        {"bil",  {1,  Nx*Nz, Nx}},
        {"bip",  {Nz, Nx*Nz, 1}},
        {"bsq",  {1,  Nx,    Nx*Ny}},
    };

    if (mappings.find(in_format) == mappings.end()) {
        std::cout << "Input format invalid\n";
        return -1;
    }
    if (mappings.find(out_format) == mappings.end()) {
        std::cout << "Output format invalid\n";
        return -1;
    }

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
    int in_nx, in_ny, in_nz;
    int out_nx, out_ny, out_nz;
    std::tie(in_nx, in_ny, in_nz) = mappings[in_format];
    std::tie(out_nx, out_ny, out_nz) = mappings[out_format];
    for (int x = 0; x < Nx; x++) {
        for (int y = 0; y < Ny; y++) {
            for (int z = 0; z < Nz; z++) {
                processed_image[x*out_nx + y*out_ny + z*out_nz] = image[x*in_nx + y*in_ny + z*in_nz];
            }
        }
    }

    std::cout << "Writing output file\n";

    std::ofstream outfile(outfile_name, std::ofstream::out | std::ofstream::binary);
    outfile.write((char*)&processed_image[0], Nx*Ny*Nz*bpc);

    std::cout << "Done.\n";
}
