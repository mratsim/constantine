/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

#include <constantine.h>

int from_hex(byte *dst, size_t dst_len, const char *hex_src, size_t src_len) {
    // converts the given `hex_src` to a byte buffer. `buffer` must already be
    // allocated to len(hex_src) // 2!
    if (src_len % 2 != 0) return -1; // Length must be even
    else if(dst_len * 2 != src_len) return -1; // dest length must be half src len

    for (size_t i = 0; i < dst_len; i++) {
        if (sscanf(&hex_src[i * 2], "%2hhx", &dst[i]) != 1) {
            return -(i+1); // Failed to convert hex to byte
        }
    }
    return 0; // Success
}

int compare_binary(const byte* buf1, size_t len1, const byte* buf2, size_t len2) {
    // compares the two binary buffers with length len1 and len2 byte by byte.
    if (len1 != len2){
	return -1; // mismatching length
    }
    for(size_t i = 0; i < len1; i++){
	if(buf1[i] != buf2[i]){
	    return -(i+1); // found a mismatched byte
	}
    }
    return 0; // success
}


int main(){
    ctt_evm_status evm_status;

    // just attempt to compute the sha256 hash of some text
    byte result[32] = {0};
    const char txt[] = "Foo, Bar and Baz are all friends.";

    evm_status = ctt_eth_evm_sha256(result, 32, (const byte*)txt, sizeof(txt));
    if (evm_status != cttEVM_Success) {
	printf(
	    "SHA256 hash calc from input failed %d - %s\n",
	    evm_status,
	    ctt_evm_status_to_string(evm_status)
	    );
	exit(1);
    }

    // Random test case from `map_fp2_to_G2_bls.json` to see if generally the API seems to work
    const char input_str[] = "0000000000000000000000000000000003f80ce4ff0ca2f576d797a3660e3f65b274285c054feccc3215c879e2c0589d376e83ede13f93c32f05da0f68fd6a1000000000000000000000000000000000006488a837c5413746d868d1efb7232724da10eca410b07d8b505b9363bdccf0a1fc0029bad07d65b15ccfe6dd25e20d";
    const char expected_str[] = "000000000000000000000000000000000ea4e7c33d43e17cc516a72f76437c4bf81d8f4eac69ac355d3bf9b71b8138d55dc10fd458be115afa798b55dac34be1000000000000000000000000000000001565c2f625032d232f13121d3cfb476f45275c303a037faa255f9da62000c2c864ea881e2bcddd111edc4a3c0da3e88d00000000000000000000000000000000043b6f5fe4e52c839148dc66f2b3751e69a0f6ebb3d056d6465d50d4108543ecd956e10fa1640dfd9bc0030cc2558d28000000000000000000000000000000000f8991d2a1ad662e7b6f58ab787947f1fa607fce12dde171bc17903b012091b657e15333e11701edcf5b63ba2a561247";
    byte    input[128]; from_hex(input, 128, input_str, 256);
    byte expected[256]; from_hex(expected, 256, expected_str, 512);
    byte    g2Res[256];

    evm_status = ctt_eth_evm_bls12381_map_fp2_to_g2(g2Res, 256, input, 128);
    if(evm_status != cttEVM_Success){
	printf(
	    "Mapping input from Fp2 to G2 failed %d - %s\n",
	    evm_status,
	    ctt_evm_status_to_string(evm_status)
	    );
	exit(1);
    }

    evm_status = compare_binary(g2Res, 256, expected, 256);
    if(evm_status != cttEVM_Success){
	printf(
	    "Unexpected output from Fp2 to G2 mapping %d - %s\n",
	    evm_status,
	    ctt_evm_status_to_string(evm_status)
	    );
	exit(1);
    }
    printf("EVM precompiles example ran successfully.\n");

    return 0;
}
