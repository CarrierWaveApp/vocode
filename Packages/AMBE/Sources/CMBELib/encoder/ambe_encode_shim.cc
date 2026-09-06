#include "imbe_vocoder/imbe_vocoder.h"
#include "mbelib.h"
#include "ambe_encoder.h"
#include "ambe_encode_shim.h"

struct ambe_enc {
	ambe_encoder encoder;
};

extern "C" ambe_enc *ambe_enc_create(void)
{
	return new ambe_enc();
}

extern "C" void ambe_enc_destroy(ambe_enc *enc)
{
	delete enc;
}

extern "C" void ambe_enc_frame(ambe_enc *enc, const int16_t pcm[160], char cells[96])
{
	int16_t samples[160];
	uint8_t out[96];
	for (int i = 0; i < 160; i++)
		samples[i] = pcm[i];
	enc->encoder.encode(samples, out);
	for (int i = 0; i < 96; i++)
		cells[i] = (char)out[i];
}
