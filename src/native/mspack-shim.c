#include <mspack.h>
#include <stdlib.h>

struct mscab_decompressor *
lum_cab_new (void)
{
    return mspack_create_cab_decompressor (NULL);
}

void
lum_cab_free (struct mscab_decompressor *d)
{
    if (d) mspack_destroy_cab_decompressor (d);
}

struct mscabd_cabinet *
lum_cab_search (struct mscab_decompressor *d, const char *filename)
{
    return d->search (d, filename);
}

struct mscabd_cabinet *
lum_cab_open (struct mscab_decompressor *d, const char *filename)
{
    return d->open (d, filename);
}

void
lum_cab_close (struct mscab_decompressor *d, struct mscabd_cabinet *cab)
{
    d->close (d, cab);
}

int
lum_cab_extract (struct mscab_decompressor *d,
                 struct mscabd_file *file,
                 const char *output)
{
    return d->extract (d, file, output);
}

int
lum_cab_last_error (struct mscab_decompressor *d)
{
    return d->last_error (d);
}

/* Accessors for mscabd_cabinet */
struct mscabd_file *
lum_cab_get_files (struct mscabd_cabinet *cab)
{
    return cab ? cab->files : NULL;
}

struct mscabd_cabinet *
lum_cab_get_next (struct mscabd_cabinet *cab)
{
    return cab ? cab->next : NULL;
}

/* Accessors for mscabd_file */
const char *
lum_cabf_get_filename (struct mscabd_file *f)
{
    return f ? f->filename : NULL;
}

unsigned int
lum_cabf_get_length (struct mscabd_file *f)
{
    return f ? f->length : 0;
}

struct mscabd_file *
lum_cabf_get_next (struct mscabd_file *f)
{
    return f ? f->next : NULL;
}
