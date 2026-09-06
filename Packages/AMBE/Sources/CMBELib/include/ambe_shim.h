#ifndef AMBE_SHIM_H
#define AMBE_SHIM_H

#include "mbelib.h"

// Decoder state across frames
typedef struct {
    mbe_parms cur;
    mbe_parms prev;
    mbe_parms prevEnh;
} ambe_ctx;

void ambe_ctx_init(ambe_ctx *ctx);

// fr: 96 cells, [4][24] flattened
// out: 160 int16 samples at 8 kHz
// returns uncorrectable error count
int ambe_decode_frame(ambe_ctx *ctx, const char *fr, short *out, int uvquality);

// Same contract for D-STAR's AMBE 3600x2400 mode
int ambe_decode_frame_2400(ambe_ctx *ctx, const char *fr, short *out, int uvquality);

#endif
