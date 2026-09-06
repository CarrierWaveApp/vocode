#include "ambe_shim.h"
#include <string.h>

void ambe_ctx_init(ambe_ctx *ctx) {
    mbe_initMbeParms(&ctx->cur, &ctx->prev, &ctx->prevEnh);
}

int ambe_decode_frame(ambe_ctx *ctx, const char *fr, short *out, int uvquality) {
    char ambe_fr[4][24];
    char ambe_d[49];
    char err_str[64];
    int errs = 0, errs2 = 0;

    memcpy(ambe_fr, fr, sizeof(ambe_fr));
    mbe_processAmbe3600x2450Frame(out, &errs, &errs2, err_str, ambe_fr, ambe_d,
                                  &ctx->cur, &ctx->prev, &ctx->prevEnh, uvquality);
    return errs2;
}

int ambe_decode_frame_2400(ambe_ctx *ctx, const char *fr, short *out, int uvquality) {
    char ambe_fr[4][24];
    char ambe_d[49];
    char err_str[64];
    int errs = 0, errs2 = 0;

    memcpy(ambe_fr, fr, sizeof(ambe_fr));
    mbe_processAmbe3600x2400Frame(out, &errs, &errs2, err_str, ambe_fr, ambe_d,
                                  &ctx->cur, &ctx->prev, &ctx->prevEnh, uvquality);
    return errs2;
}
