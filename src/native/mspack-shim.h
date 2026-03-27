#ifndef MSPACK_SHIM_H
#define MSPACK_SHIM_H

#include <mspack.h>

struct mscab_decompressor * lum_cab_new (void);
void lum_cab_free (struct mscab_decompressor *d);

struct mscabd_cabinet * lum_cab_search (struct mscab_decompressor *d, const char *filename);
struct mscabd_cabinet * lum_cab_open (struct mscab_decompressor *d, const char *filename);
void lum_cab_close (struct mscab_decompressor *d, struct mscabd_cabinet *cab);
int lum_cab_extract (struct mscab_decompressor *d, struct mscabd_file *file, const char *output);
int lum_cab_last_error (struct mscab_decompressor *d);

struct mscabd_file * lum_cab_get_files (struct mscabd_cabinet *cab);
struct mscabd_cabinet * lum_cab_get_next (struct mscabd_cabinet *cab);

const char * lum_cabf_get_filename (struct mscabd_file *f);
unsigned int lum_cabf_get_length (struct mscabd_file *f);
struct mscabd_file * lum_cabf_get_next (struct mscabd_file *f);

#endif
