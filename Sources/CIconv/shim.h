#include <iconv.h>
#include <errno.h>
static inline int myterm_convert(iconv_t converter, char *input, size_t *inputLeft, char *output, size_t *outputLeft) {
    size_t result = iconv(converter, &input, inputLeft, &output, outputLeft);
    return result == (size_t)-1 ? errno : 0;
}
static inline int myterm_iconv_invalid(iconv_t converter) { return converter == (iconv_t)-1; }
