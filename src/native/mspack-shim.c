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
    if (!d || !filename) return NULL;
    return d->search (d, filename);
}

struct mscabd_cabinet *
lum_cab_open (struct mscab_decompressor *d, const char *filename)
{
    if (!d || !filename) return NULL;
    return d->open (d, filename);
}

void
lum_cab_close (struct mscab_decompressor *d, struct mscabd_cabinet *cab)
{
    if (!d) return;
    d->close (d, cab);
}

int
lum_cab_extract (struct mscab_decompressor *d,
                 struct mscabd_file *file,
                 const char *output)
{
    if (!d || !file || !output) return MSPACK_ERR_ARGS;
    return d->extract (d, file, output);
}

int
lum_cab_last_error (struct mscab_decompressor *d)
{
    if (!d) return MSPACK_ERR_ARGS;
    return d->last_error (d);
}

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

int
lum_cab_get_folder_count (struct mscabd_cabinet *cab)
{
    int count = 0;
    if (!cab) return 0;
    for (struct mscabd_folder *f = cab->folders; f; f = f->next) count++;
    return count;
}

int
lum_cab_get_folder_index (struct mscabd_cabinet *cab, struct mscabd_file *file)
{
    int index = 0;
    if (!cab || !file) return -1;
    for (struct mscabd_folder *f = cab->folders; f; f = f->next, index++) {
        if (f == file->folder) return index;
    }
    return -1;
}

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
