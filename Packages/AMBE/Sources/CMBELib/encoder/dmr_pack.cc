// Packs the nine quantized AMBE+2 codewords b[0..8] into mbelib's
// ambe_fr[4][24] cell layout: c0 = Golay(24,12), c1 = Golay(23,12) with
// pseudo-random modulation, c2 = 11 bits, c3 = 14 bits. Cell index = bit
// position, LSB at index 0, matching mbe_demodulateAmbe3600x2450Data.
//
// The u-vector construction follows OP25's p25p2_vf::encode_vcw
// (C) Copyright 2014 Max H. Parke KA1RBI, GPL v3. The PN generator
// mirrors mbelib's demodulator so the two are exact inverses.

#include <stdint.h>
#include "op25_golay.h"

void dmr_cells_pack(uint8_t cells[96], const int b[9])
{
	uint32_t u0 =
		((b[0] & 0x78) << 5) |
		((b[1] & 0x1e) << 3) |
		((b[2] & 0x1e) >> 1);
	uint32_t u1 =
		((b[3] & 0x1fe) << 3) |
		((b[4] & 0x78) >> 3);
	uint32_t u2 =
		((b[5] & 0x1e) << 6) |
		((b[6] & 0xe) << 3) |
		((b[7] & 0xe)) |
		((b[8] & 0x4) >> 2);
	uint32_t u3 =
		((b[1] & 0x1) << 13) |
		((b[2] & 0x1) << 12) |
		((b[0] & 0x7) << 9) |
		((b[3] & 0x1) << 8) |
		((b[4] & 0x7) << 5) |
		((b[5] & 0x1) << 4) |
		((b[6] & 0x1) << 3) |
		((b[7] & 0x1) << 2) |
		((b[8] & 0x3));

	uint32_t c0 = golay_24_encode(u0);
	uint32_t c1 = golay_23_encode(u1);

	for (int i = 0; i < 96; i++)
		cells[i] = 0;
	for (int j = 0; j < 24; j++)
		cells[0 * 24 + j] = (c0 >> j) & 1;
	for (int j = 0; j < 23; j++)
		cells[1 * 24 + j] = (c1 >> j) & 1;
	for (int j = 0; j < 11; j++)
		cells[2 * 24 + j] = (u2 >> j) & 1;
	for (int j = 0; j < 14; j++)
		cells[3 * 24 + j] = (u3 >> j) & 1;

	// Pseudo-random modulation of c1, seeded by the 12 data bits of c0,
	// exactly as mbelib regenerates it on decode
	unsigned short pr = (unsigned short)(16 * u0);
	for (int j = 22; j >= 0; j--) {
		pr = (unsigned short)((173 * pr) + 13849);
		cells[1 * 24 + j] ^= (pr >> 15) & 1;
	}
}
