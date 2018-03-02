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
    if (argc < 3) {
        std::cout << "Usage:\n"
                  << "endianswap input output\n\n"
                  << " in-format, out-format: BIP, BIL, BSQ\n";
        return -1;
    }

    const std::string infile_name(argv[1]);
    const std::string outfile_name(argv[2]);

    std::ifstream infile(infile_name, std::ifstream::in | std::ifstream::binary);
    std::ofstream outfile(outfile_name, std::ofstream::out | std::ofstream::binary);

    infile.seekg(0,std::ios::end);
    std::streampos size = infile.tellg();
    infile.seekg(0,std::ios::beg);

    std::cout << "Rearranging\n";
    while (!infile.eof()) {
        uint64_t value;
        infile.read((char*)&value, 8);
        uint64_t new_value =
            ((value & 0x00000000000000FF) << 56) |
            ((value & 0x000000000000FF00) << 40) |
            ((value & 0x0000000000FF0000) << 24) |
            ((value & 0x00000000FF000000) << 8)  |
            ((value & 0x000000FF00000000) >> 8)  |
            ((value & 0x0000FF0000000000) >> 24) |
            ((value & 0x00FF000000000000) >> 40) |
            ((value & 0xFF00000000000000) >> 56);
        outfile.write((char*)&new_value, 8);
    }

    std::cout << "Done.\n";
}
