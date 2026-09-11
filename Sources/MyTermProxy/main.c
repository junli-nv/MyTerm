#include <sys/types.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <poll.h>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void fail(const char *message) { fprintf(stderr, "MyTerm proxy: %s\n", message); exit(1); }
static void transfer(int fd, unsigned char *bytes, size_t size, int writing) {
    size_t offset = 0;
    while (offset < size) {
        ssize_t n = writing ? write(fd, bytes + offset, size - offset) : read(fd, bytes + offset, size - offset);
        if (n > 0) offset += (size_t)n;
        else if (n < 0 && errno == EINTR) continue;
        else fail("proxy handshake failed or timed out");
    }
}
static int connect_proxy(const char *host, const char *port) {
    struct addrinfo hints = {0}, *addresses = NULL;
    hints.ai_socktype = SOCK_STREAM; hints.ai_family = AF_UNSPEC;
    if (getaddrinfo(host, port, &hints, &addresses)) fail("cannot resolve proxy host");
    int connected = -1;
    for (struct addrinfo *item = addresses; item; item = item->ai_next) {
        int fd = socket(item->ai_family, item->ai_socktype, item->ai_protocol);
        if (fd < 0) continue;
        fcntl(fd, F_SETFL, O_NONBLOCK);
        int result = connect(fd, item->ai_addr, item->ai_addrlen);
        if (result < 0 && errno == EINPROGRESS) {
            struct pollfd event = {fd, POLLOUT, 0};
            if (poll(&event, 1, 15000) > 0) {
                int error = 0; socklen_t length = sizeof(error);
                result = getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0 && error == 0 ? 0 : -1;
            }
        }
        if (result == 0) { connected = fd; break; }
        close(fd);
    }
    freeaddrinfo(addresses);
    if (connected < 0) fail("cannot connect to proxy");
    fcntl(connected, F_SETFL, 0);
    struct timeval timeout = {15, 0};
    setsockopt(connected, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(connected, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    return connected;
}
static void http_connect(int fd, const char *host, unsigned port) {
    char address[1200], request[2600], response[32769];
    snprintf(address, sizeof(address), strchr(host, ':') ? "[%s]:%u" : "%s:%u", host, port);
    int length = snprintf(request, sizeof(request), "CONNECT %s HTTP/1.1\r\nHost: %s\r\n\r\n", address, address);
    if (length < 0 || (size_t)length >= sizeof(request)) fail("target address too long");
    transfer(fd, (unsigned char *)request, (size_t)length, 1);
    size_t count = 0;
    while (count < sizeof(response) - 1) {
        transfer(fd, (unsigned char *)response + count, 1, 0); count++;
        if (count >= 4 && memcmp(response + count - 4, "\r\n\r\n", 4) == 0) break;
    }
    response[count] = 0;
    if (count == sizeof(response) - 1) fail("HTTP proxy response header too large");
    int minor, code;
    if (sscanf(response, "HTTP/1.%d %d", &minor, &code) != 2 || (minor != 0 && minor != 1)) fail("invalid HTTP proxy response");
    if (code == 407) fail("proxy requires authentication; this version supports unauthenticated proxies");
    if (code < 200 || code > 299) fail("HTTP proxy rejected CONNECT");
}
static void socks_connect(int fd, const char *host, unsigned port) {
    unsigned char hello[] = {5, 1, 0}, reply[4], request[262] = {5, 1, 0, 0};
    transfer(fd, hello, sizeof(hello), 1); transfer(fd, reply, 2, 0);
    if (reply[0] != 5 || reply[1] != 0) fail("SOCKS5 proxy requires unsupported authentication");
    size_t length = 4;
    if (inet_pton(AF_INET, host, request + 4) == 1) { request[3] = 1; length += 4; }
    else if (inet_pton(AF_INET6, host, request + 4) == 1) { request[3] = 4; length += 16; }
    else {
        size_t size = strlen(host);
        if (!size || size > 255) fail("SOCKS5 target name too long");
        request[3] = 3; request[4] = (unsigned char)size; memcpy(request + 5, host, size); length += size + 1;
    }
    request[length++] = (unsigned char)(port >> 8); request[length++] = (unsigned char)port;
    transfer(fd, request, length, 1); transfer(fd, reply, 4, 0);
    if (reply[0] != 5 || reply[1] != 0) fail("SOCKS5 proxy rejected connection");
    size_t size = reply[3] == 1 ? 4 : reply[3] == 4 ? 16 : 0;
    if (reply[3] == 3) { transfer(fd, reply, 1, 0); size = reply[0]; }
    if (!size) fail("invalid SOCKS5 bound address");
    unsigned char ignored[257]; transfer(fd, ignored, size + 2, 0);
}
struct buffer { unsigned char data[65536]; size_t size; };
static int read_into(int fd, struct buffer *buffer) {
    ssize_t size = read(fd, buffer->data + buffer->size, sizeof(buffer->data) - buffer->size);
    if (size > 0) buffer->size += (size_t)size;
    else if (size == 0) return 0;
    else if (errno != EAGAIN && errno != EINTR) fail("tunnel read failed");
    return 1;
}
static void write_from(int fd, struct buffer *buffer) {
    ssize_t size = write(fd, buffer->data, buffer->size);
    if (size > 0) { buffer->size -= (size_t)size; memmove(buffer->data, buffer->data + size, buffer->size); }
    else if (size < 0 && errno != EAGAIN && errno != EINTR) fail("tunnel write failed");
}
static void relay(int fd) {
    struct buffer outgoing = {{0}, 0}, incoming = {{0}, 0};
    int input_open = 1, socket_open = 1, shut = 0;
    fcntl(fd, F_SETFL, O_NONBLOCK);
    fcntl(STDIN_FILENO, F_SETFL, fcntl(STDIN_FILENO, F_GETFL) | O_NONBLOCK);
    fcntl(STDOUT_FILENO, F_SETFL, fcntl(STDOUT_FILENO, F_GETFL) | O_NONBLOCK);
    while (socket_open || incoming.size) {
        if (!input_open && !outgoing.size && !shut) { shutdown(fd, SHUT_WR); shut = 1; }
        struct pollfd events[] = {
            {input_open ? STDIN_FILENO : -1, outgoing.size < sizeof(outgoing.data) ? POLLIN : 0, 0},
            {(socket_open && incoming.size < sizeof(incoming.data)) || outgoing.size ? fd : -1,
             (socket_open && incoming.size < sizeof(incoming.data) ? POLLIN : 0) | (outgoing.size ? POLLOUT : 0), 0},
            {incoming.size ? STDOUT_FILENO : -1, POLLOUT, 0}
        };
        if (poll(events, 3, -1) < 0) { if (errno == EINTR) continue; fail("tunnel poll failed"); }
        if ((events[0].revents & (POLLIN | POLLHUP)) && outgoing.size < sizeof(outgoing.data)) input_open = read_into(STDIN_FILENO, &outgoing);
        if ((events[1].revents & (POLLIN | POLLHUP)) && incoming.size < sizeof(incoming.data)) socket_open = read_into(fd, &incoming);
        if (events[1].revents & POLLOUT) write_from(fd, &outgoing);
        if (events[2].revents & POLLOUT) write_from(STDOUT_FILENO, &incoming);
        if ((events[0].revents | events[1].revents | events[2].revents) & (POLLERR | POLLNVAL)) fail("tunnel disconnected");
    }
}
int main(int argc, char **argv) {
    if (argc != 6) fail("usage: MyTermProxy http|socks5 proxy-host proxy-port target-host target-port");
    signal(SIGPIPE, SIG_IGN);
    for (int i = 2; i < 6; i++) if (!*argv[i] || strpbrk(argv[i], "\r\n") || strlen(argv[i]) > 1024) fail("invalid endpoint");
    char *end = NULL; long port = strtol(argv[5], &end, 10);
    if (*end || port < 1 || port > 65535) fail("invalid target port");
    char proxy_host[1025], target_host[1025];
    const char *hosts[] = {argv[2], argv[4]}; char *outputs[] = {proxy_host, target_host};
    for (int i = 0; i < 2; i++) {
        size_t size = strlen(hosts[i]); int brackets = hosts[i][0] == '[' && hosts[i][size - 1] == ']';
        size_t count = size - (brackets ? 2 : 0); memcpy(outputs[i], hosts[i] + brackets, count); outputs[i][count] = 0;
    }
    int fd = connect_proxy(proxy_host, argv[3]);
    if (!strcmp(argv[1], "http")) http_connect(fd, target_host, (unsigned)port);
    else if (!strcmp(argv[1], "socks5")) socks_connect(fd, target_host, (unsigned)port);
    else fail("unsupported proxy type");
    relay(fd); close(fd); return 0;
}
