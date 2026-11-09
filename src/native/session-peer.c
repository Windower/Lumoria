#include "session-peer.h"
#include <sys/socket.h>
#include <unistd.h>
#include <errno.h>

gboolean lumoria_session_peer_allowed (int fd, GError **error)
{
    struct ucred peer;
    socklen_t size = sizeof peer;
    if (getsockopt (fd, SOL_SOCKET, SO_PEERCRED, &peer, &size) != 0) {
        int saved_errno = errno;
        g_set_error (error, G_IO_ERROR, g_io_error_from_errno (saved_errno),
                     "Cannot read session peer credentials: %s", g_strerror (saved_errno));
        return FALSE;
    }
    if (size != sizeof peer || peer.uid == (uid_t) -1 || peer.uid != getuid ()) {
        g_set_error_literal (error, G_IO_ERROR, G_IO_ERROR_PERMISSION_DENIED,
                             "Session peer UID is not authorized");
        return FALSE;
    }
    return TRUE;
}
