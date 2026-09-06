#ifndef AMBE_ENCODE_SHIM_H
#define AMBE_ENCODE_SHIM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * C wrapper around OP25's software AMBE+2 encoder (GPL v3).
 * 160 samples of 8 kHz S16 audio in, one 3600x2450 frame out as 96 cells
 * in mbelib's ambe_fr[4][24] layout - the same layout ambe_decode_frame
 * consumes, so encode and decode are symmetric.
 */

typedef struct ambe_enc ambe_enc;

ambe_enc *ambe_enc_create(void);
void ambe_enc_destroy(ambe_enc *enc);
void ambe_enc_frame(ambe_enc *enc, const int16_t pcm[160], char cells[96]);

#ifdef __cplusplus
}
#endif

#endif /* AMBE_ENCODE_SHIM_H */
