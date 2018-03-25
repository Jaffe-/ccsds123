#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>
#include <string>
#include <algorithm>
#include <map>
#include <tuple>
#include <cmath>

uint16_t mask(int n) {
    int mask = 1;
    for (int i = 0; i < n; i++)
        mask |= 1 << i;
}

int main(int argc, char **argv)
{
    if (argc < 4) {
        std::cout << "Usage:\n"
                  << "truncate file out-bpc\n";
    }

    const std::string infile_name(argv[1]);
    const std::string outfile_name(argv[2]);
    const int out_bpc = std::stoi(std::string(argv[3]));

    const size_t BUF_SIZE = 1024;

    std::ifstream infile(infile_name, std::ifstream::in | std::ifstream::binary);

    infile.seekg(0,std::ios::end);
    std::streampos size = infile.tellg() / 2;
    infile.seekg(0,std::ios::beg);

    std::ofstream outfile(outfile_name, std::ofstream::out | std::ofstream::binary);

    const int n_blocks = int(std::ceil(double(size)/BUF_SIZE));
    const int size_last = (size % BUF_SIZE == 0) ? BUF_SIZE : (size % BUF_SIZE);

    std::cout << "n_blocks=" << n_blocks << ", size_last=" << size_last << "\n";

    std::vector<uint16_t> out_block(BUF_SIZE);
    std::vector<uint16_t> block(BUF_SIZE);
    int out_i = 0;
    uint16_t next_out_sample = 0;;
    int buf_start = 0;
    int blocks_written = 0;
    int j = 0;

    for (int i = 0; i < n_blocks; i++) {
        int read_size = (i == n_blocks - 1) ? size_last : BUF_SIZE;
        infile.read((char*)&block[0], 2*read_size);
        for (int iw = 0; iw < read_size; iw++) {
            uint16_t truncated_word = (block[iw] >> (16 - out_bpc)) & mask(out_bpc);
            next_out_sample |= (truncated_word & mask(16 - buf_start)) << buf_start;
            uint16_t n_out = buf_start + out_bpc;
            if (n_out >= 16) {
                out_block[out_i++] = next_out_sample;
                next_out_sample = truncated_word >> (16 - buf_start);
                buf_start = n_out % 16;
            }
            else {
                buf_start = n_out;
            }

            if (out_i == BUF_SIZE) {
                outfile.write((char*)&out_block[0], 2*BUF_SIZE);
                out_i = 0;
                blocks_written ++;
            }

        }
    }

    std::cout << "Bocks written: " << blocks_written << "\n";

    if (buf_start > 0)
        out_block[out_i++] = next_out_sample;

    // Check if we need to write som remaining bytes from out_block
    if (out_i != 0) {
        outfile.write((char*)&out_block[0], (2*out_i));
    }
}
